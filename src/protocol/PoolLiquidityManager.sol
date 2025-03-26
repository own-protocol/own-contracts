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
     * @notice Add liquidity to the pool
     * @param amount The amount of liquidity to add
     */
    function addLiquidity(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        (uint256 healthyRatio, ,) = poolStrategy.getLPLiquidityParams();
        // Calculate additional required collateral
        uint256 requiredCollateral = Math.mulDiv(amount, healthyRatio, BPS);
        // Transfer required collateral
        reserveToken.transferFrom(msg.sender, address(this), requiredCollateral);
        
        if (registeredLPs[msg.sender]) {

            LPPosition storage position = lpPositions[msg.sender];            
            // Update LP position
            position.liquidityCommitment += amount;
            position.collateralAmount += requiredCollateral;
            
            // Update total liquidity
            totalLPLiquidityCommited += amount;
            totalLPCollateral += requiredCollateral;
            
            emit LiquidityAdded(msg.sender, amount, requiredCollateral);
        } else {
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
            
            emit LPAdded(msg.sender, amount, requiredCollateral);
        }
    }

    /**
     * @notice Remove an lp's liquidity
     * @param amount The amount of liquidity to reduce
     */
    function reduceLiquidity(uint256 amount) external nonReentrant onlyRegisteredLP {
        if (amount == 0) revert InvalidAmount();
        
        LPPosition storage position = lpPositions[msg.sender];
        if (amount > position.liquidityCommitment) revert InsufficientLiquidity();

        (uint256 healthyRatio, ,) = poolStrategy.getLPLiquidityParams();
        
        // Calculate releasable collateral
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
        
        emit LiquidityReduced(msg.sender, amount, releasableCollateral);

        if (position.liquidityCommitment == 0) {
            if (position.interestAccrued > 0) {
                reserveToken.transfer(msg.sender, position.interestAccrued);
                position.interestAccrued = 0;
            }
            registeredLPs[msg.sender] = false;
            lpCount--;
            delete lpPositions[msg.sender];
            emit LPRemoved(msg.sender);
        }
    }

    /**
     * @notice Add additional collateral beyond the minimum
     * @param amount Amount of collateral to deposit
     */
    function addCollateral(uint256 amount) external nonReentrant onlyRegisteredLP {
        if (amount == 0) revert ZeroAmount();
        
        reserveToken.transferFrom(msg.sender, address(this), amount);
        lpPositions[msg.sender].collateralAmount += amount;

        totalLPCollateral += amount;
        
        emit CollateralAdded(msg.sender, amount);
    }

    /**
     * @notice Remove excess collateral if above minimum requirements
     * @param amount Amount of collateral to reduce
     */
    function reduceCollateral(uint256 amount) external nonReentrant onlyRegisteredLP {
        LPPosition storage position = lpPositions[msg.sender];
        if (amount == 0 || amount > position.collateralAmount) revert InvalidWithdrawalAmount();
        
        uint256 requiredCollateral = poolStrategy.calculateLPRequiredLiquidity(address(this), msg.sender);
        if (position.collateralAmount - amount < requiredCollateral) {
            revert InsufficientLiquidity();
        }
        
        position.collateralAmount -= amount;
        totalLPCollateral -= amount;
        reserveToken.transfer(msg.sender, amount);
        
        emit CollateralReduced(msg.sender, amount);
    }

    /**
     * @notice Claim interest accrued on LP position
     */
    function claimInterest() external nonReentrant onlyRegisteredLP {
        LPPosition storage position = lpPositions[msg.sender];
        uint256 interestAccrued = position.interestAccrued;
        if (interestAccrued == 0) revert NoInterestAccrued();
        
        position.interestAccrued = 0;
        reserveToken.transfer(msg.sender, interestAccrued);
        
        emit InterestClaimed(msg.sender, interestAccrued);
    }

    /**
    * @notice Liquidate an LP below threshold 
    * @param lp Address of the LP to liquidate
    */
    function liquidateLP(address lp) external nonReentrant onlyRegisteredLP {
        if (!registeredLPs[lp] || lp == msg.sender) revert InvalidLiquidation();
        
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