// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IAssetPool} from "../interfaces/IAssetPool.sol";
import {IAssetOracle} from "../interfaces/IAssetOracle.sol";
import {IXToken} from "../interfaces/IXToken.sol";
import {IPoolCycleManager} from "../interfaces/IPoolCycleManager.sol";
import {IPoolLiquidityManager} from "../interfaces/IPoolLiquidityManager.sol";
import {IPoolStrategy} from "../interfaces/IPoolStrategy.sol";
import {PoolStorage} from "./PoolStorage.sol";

/**
 * @title PoolLiquidityManager
 * @notice Manages LP liquidity requirements and registry for the asset pool
 */
contract PoolLiquidityManager is IPoolLiquidityManager, PoolStorage, ReentrancyGuard {
    
    // Total liquidity committed by LPs
    uint256 public totalLPLiquidityCommited;

    // Total lp collateral
    uint256 public totalLPCollateral;
    
    // Number of registered LPs
    uint256 public lpCount;

    // Mapping of LP addresses to their liquidity info
    mapping(address => LPPosition) private lpPositions;
    
    // Mapping to check if an address is a registered LP
    mapping(address => bool) public registeredLPs;

    // --------------------------------------------------------------------------------
    //                                  MODIFIERS
    // --------------------------------------------------------------------------------

    /**
     * @dev Ensures the caller is the pool cycle manager
     */
    modifier onlyPoolCycleManager() {
        if (msg.sender != address(poolCycleManager)) revert NotPoolCycleManager();
        _;
    }

    /**
     * @notice Modifier to ensure the caller is a registered LP
     */
    modifier onlyRegisteredLP() {
        if (!registeredLPs[msg.sender]) revert NotRegisteredLP();
        _;
    }

    /**
     * @dev Empty constructor
     * Used for the implementation contract only, not for clones
     */
    constructor() {
        // This disables initialization of the implementation contract
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract - replaces the constructor for clones
     * @param _reserveToken Address of the reserve token
     * @param _assetToken Address of the asset token
     * @param _assetOracle Address of the asset oracle
     * @param _assetPool Address of the asset pool
     * @param _poolCycleManager Address of the pool cycle manager
     * @param _poolStrategy Address of the pool strategy
     */
    function initialize(
        address _reserveToken,
        address _assetToken,
        address _assetOracle,
        address _assetPool,
        address _poolCycleManager,
        address _poolStrategy
    ) external initializer {
        if (_reserveToken == address(0) || _assetToken == address(0) || _assetPool == address(0) || 
            _poolCycleManager == address(0) || _assetOracle == address(0)) {
            revert ZeroAddress();
        }
            
        reserveToken = IERC20Metadata(_reserveToken);
        assetToken = IXToken(_assetToken);
        assetPool = IAssetPool(_assetPool);
        poolCycleManager = IPoolCycleManager(_poolCycleManager);
        poolStrategy = IPoolStrategy(_poolStrategy);
        assetOracle = IAssetOracle(_assetOracle);

        _initializeDecimalFactor(address(reserveToken), address(assetToken));
        
    }

    /**
     * @notice Register as a liquidity provider
     * @param amount The amount of liquidity commitment to provide
     */
    function registerLP(uint256 amount) external nonReentrant {
        if (registeredLPs[msg.sender]) revert AlreadyRegistered();
        if (amount == 0) revert InvalidAmount();

        (uint256 healthyRatio, ,) = poolStrategy.getLPLiquidityParams();
        
        // Calculate required collateral (20% of liquidity)
        uint256 requiredCollateral = Math.mulDiv(amount, healthyRatio, BPS);
        
        // Transfer liquidity from LP to contract
        reserveToken.transferFrom(msg.sender, address(this), requiredCollateral);
        
        // Update LP info
        registeredLPs[msg.sender] = true;
        lpPositions[msg.sender] = LPPosition({
            liquidityCommitment: amount,
            collateralAmount: requiredCollateral,
            interestAccrued: 0
        });
        
        // Update pool stats
        totalLPLiquidityCommited += amount;
        totalLPCollateral += requiredCollateral;
        lpCount++;
        
        emit LPRegistered(msg.sender, amount, requiredCollateral);
    }

    /**
     * @notice Unregister LP from registry
     * @param lp The address of the LP
     */
    function unregisterLP(address lp) external {
        if (msg.sender != lp) revert Unauthorized();
        if (!registeredLPs[lp]) revert NotRegisteredLP();
        
        LPPosition storage position = lpPositions[lp];
        if (position.liquidityCommitment > 0) revert("LP has active liquidity commitment");
        
        // Refund any remaining collateral
        if (position.collateralAmount > 0) {
            uint256 refundAmount = position.collateralAmount;
            position.collateralAmount = 0;
            reserveToken.transfer(lp, refundAmount);
        }
        
        registeredLPs[lp] = false;
        lpCount--;
        
        emit LPRemoved(lp);
    }

    /**
     * @notice Increase your liquidity commitment
     * @param amount The amount of liquidity to add
     */
    function increaseLiquidityCommitment(uint256 amount) external nonReentrant onlyRegisteredLP {
        if (amount == 0) revert InvalidAmount();
        
        LPPosition storage position = lpPositions[msg.sender];

        (uint256 healthyRatio, ,) = poolStrategy.getLPLiquidityParams();
        
        // Calculate additional required collateral (20% of new liquidity)
        uint256 additionalCollateral = Math.mulDiv(amount, healthyRatio, BPS);
        
        // Transfer additional collateral
        reserveToken.transferFrom(msg.sender, address(this), additionalCollateral);
        
        // Update LP position
        position.liquidityCommitment += amount;
        position.collateralAmount += additionalCollateral;
        
        // Update total liquidity
        totalLPLiquidityCommited += amount;
        totalLPCollateral += additionalCollateral;
        
        emit LiquidityIncreased(msg.sender, amount);
    }

    /**
     * @notice Decrease your liquidity commitment
     * @param amount The amount of liquidity to remove
     */
    function decreaseLiquidityCommitment(uint256 amount) external nonReentrant onlyRegisteredLP {
        if (amount == 0) revert InvalidAmount();
        
        LPPosition storage position = lpPositions[msg.sender];
        if (amount > position.liquidityCommitment) revert InsufficientLiquidity();

        (uint256 healthyRatio, ,) = poolStrategy.getLPLiquidityParams();
        
        // Calculate releasable collateral (20% of removed liquidity)
        uint256 releasableCollateral = Math.mulDiv(amount, healthyRatio, BPS);
        
        // Update LP position
        position.liquidityCommitment -= amount;
        
        // Ensure remaining collateral meets minimum requirements
        uint256 requiredCollateral = poolStrategy.calculateLPRequiredLiquidity(address(this), msg.sender);
        
        // Can only release excess liquidity if remaining above minimum required
        if (position.collateralAmount - releasableCollateral >= requiredCollateral) {
            position.collateralAmount -= releasableCollateral;
            reserveToken.transfer(msg.sender, releasableCollateral);
        }
        
        // Update total liquidity
        totalLPLiquidityCommited -= amount;
        totalLPCollateral -= releasableCollateral;
        
        emit LiquidityDecreased(msg.sender, amount);
    }

    /**
     * @notice Deposit additional collateral beyond the minimum
     * @param amount Amount of collateral to deposit
     */
    function depositCollateral(uint256 amount) external nonReentrant onlyRegisteredLP {
        if (amount == 0) revert ZeroAmount();
        
        reserveToken.transferFrom(msg.sender, address(this), amount);
        lpPositions[msg.sender].collateralAmount += amount;

        totalLPCollateral += amount;
        
        emit CollateralDeposited(msg.sender, amount);
    }

    /**
     * @notice Withdraw excess collateral if above minimum requirements
     * @param amount Amount of collateral to withdraw
     */
    function withdrawCollateral(uint256 amount) external nonReentrant onlyRegisteredLP {
        LPPosition storage position = lpPositions[msg.sender];
        if (amount == 0 || amount > position.collateralAmount) revert InvalidWithdrawalAmount();
        
        uint256 requiredCollateral = poolStrategy.calculateLPRequiredLiquidity(address(this), msg.sender);
        if (position.collateralAmount - amount < requiredCollateral) {
            revert InsufficientLiquidity();
        }
        
        position.collateralAmount -= amount;
        totalLPCollateral -= amount;
        reserveToken.transfer(msg.sender, amount);
        
        emit CollateralWithdrawn(msg.sender, amount);
    }

    /**
    * @notice Liquidate an LP below threshold 
    * @param lp Address of the LP to liquidate
    */
    function liquidateLP(address lp) external nonReentrant onlyRegisteredLP {
        if (!registeredLPs[lp] || lp == msg.sender) revert InvalidLiquidation();
        
    }

    /**
     * @notice Deduct rebalance amount from LP's collateral
     * @param lp Address of the LP
     * @param amount Amount to deduct
     */
    function deductRebalanceAmount(address lp, uint256 amount) external onlyPoolCycleManager {
        if (!registeredLPs[lp]) revert NotRegisteredLP();
            
        LPPosition storage position = lpPositions[lp];
        if (amount > position.collateralAmount) revert InsufficientLiquidity();

        uint8 liquidityHealth = poolStrategy.getLPLiquidityHealth(address(this), lp);
        if (liquidityHealth == 1) revert InsufficientLiquidity();
            
        position.collateralAmount -= amount;
        totalLPCollateral -= amount;
        reserveToken.transfer(address(assetPool), amount);
        
        emit RebalanceDeducted(lp, amount);
    }

    /**
     * @notice Add interest amount to LP's position
     * @param lp Address of the LP
     * @param amount Amount to add
     */
    function addToInterest(address lp, uint256 amount) external onlyPoolCycleManager {
        if (!registeredLPs[lp]) revert NotRegisteredLP();
        
        lpPositions[lp].interestAccrued += amount;
    }

    /**
     * @notice Calculate Lp's current asset holding value (in reserve token)
     * @param lp Address of the LP
     */
    function getLPAssetHoldingValue(address lp) public view returns (uint256) {
        if (!registeredLPs[lp]) return 0;
        
        uint256 poolValue = assetPool.getPoolValue();
        uint256 lpShare = getLPLiquidityShare(lp);

        uint256 lpAssetHolding = Math.mulDiv(lpShare, poolValue * reserveToAssetDecimalFactor, PRECISION);
        
        return lpAssetHolding;
    }

    /**
     * @notice Get LP's current liquidity share of the pool
     * @param lp Address of the LP
     */
    function getLPLiquidityShare(address lp) public view returns (uint256) {
        if (!registeredLPs[lp]) return 0;
        // If no total liquidity, return 0
        if (totalLPLiquidityCommited == 0) return 0;
        return Math.mulDiv(lpPositions[lp].liquidityCommitment, PRECISION, totalLPLiquidityCommited);
    }
    
    /**
     * @notice Get LP's current liquidity position
     * @param lp Address of the LP
     */
    function getLPPosition(address lp) external view returns (LPPosition memory) {
        return lpPositions[lp];
    }
    
    /**
     * @notice Check if an address is a registered LP
     * @param lp The address to check
     * @return bool True if the address is a registered LP
     */
    function isLP(address lp) external view returns (bool) {
        return registeredLPs[lp];
    }
    
    /**
     * @notice Returns the number of LPs registered
     * @return uint256 The number of registered LPs
     */
    function getLPCount() external view returns (uint256) {
        return lpCount;
    }
    
    /**
     * @notice Returns the current liquidity commited by the LP
     * @param lp The address of the LP
     * @return uint256 The current liquidity amount
     */
    function getLPLiquidityCommitment(address lp) external view returns (uint256) {
        return lpPositions[lp].liquidityCommitment;
    }
    
    /**
     * @notice Returns the total liquidity amount
     * @return uint256 The total liquidity amount
     */
    function getTotalLPLiquidityCommited() external view returns (uint256) {
        return totalLPLiquidityCommited;
    }

    /**
     * @notice Returns the total lp collateral
     * @return uint256 The total lp collateral
     */
    function getTotalLPCollateral() external view returns (uint256) {
        return totalLPCollateral;
    }

    /**
     * @notice Returns the reserve to asset decimal factor
     */
    function getReserveToAssetDecimalFactor() external view returns (uint256) {
        return reserveToAssetDecimalFactor;
    }
}