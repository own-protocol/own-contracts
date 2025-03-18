// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
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
 * @notice Manages LP collateral requirements and registry for the asset pool
 */
contract PoolLiquidityManager is IPoolLiquidityManager, PoolStorage, Ownable, ReentrancyGuard {
    
    // Total liquidity in the pool
    uint256 public totalLPLiquidity;
    
    // Number of registered LPs
    uint256 public lpCount;

    // Mapping of LP addresses to their collateral info
    mapping(address => CollateralInfo) private lpInfo;
    
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
     * @dev Empty constructor that transfers ownership to the deployer
     * Used for the implementation contract only, not for clones
     */
    constructor() Ownable(msg.sender) {
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
     * @param _owner Address of the owner
     */
    function initialize(
        address _reserveToken,
        address _assetToken,
        address _assetOracle,
        address _assetPool,
        address _poolCycleManager,
        address _poolStrategy,
        address _owner
    ) external initializer {
        if (_reserveToken == address(0) || _assetToken == address(0) || _assetPool == address(0) || 
            _poolCycleManager == address(0) || _assetOracle == address(0) || _owner == address(0)) {
            revert ZeroAddress();
        }
            
        reserveToken = IERC20Metadata(_reserveToken);
        assetToken = IXToken(_assetToken);
        assetPool = IAssetPool(_assetPool);
        poolCycleManager = IPoolCycleManager(_poolCycleManager);
        poolStrategy = IPoolStrategy(_poolStrategy);
        assetOracle = IAssetOracle(_assetOracle);

        _initializeDecimalFactor(address(reserveToken), address(assetToken));
        
        // Initialize Ownable
        _transferOwnership(_owner);
    }

    /**
     * @notice Register as a liquidity provider
     * @param liquidityAmount The amount of liquidity to provide
     */
    function registerLP(uint256 liquidityAmount) external nonReentrant {
        if (registeredLPs[msg.sender]) revert AlreadyRegistered();
        if (liquidityAmount == 0) revert InvalidAmount();

        (, , uint256 registrationRatio, ) = poolStrategy.getLPCollateralParams();
        
        // Calculate required collateral (20% of liquidity)
        uint256 requiredCollateral = Math.mulDiv(liquidityAmount, registrationRatio, BPS);
        
        // Transfer collateral from LP to contract
        reserveToken.transferFrom(msg.sender, address(this), requiredCollateral);
        
        // Update LP info
        registeredLPs[msg.sender] = true;
        lpInfo[msg.sender] = CollateralInfo({
            collateralAmount: requiredCollateral,
            liquidityAmount: liquidityAmount
        });
        
        // Update pool stats
        totalLPLiquidity += liquidityAmount;
        lpCount++;
        
        emit LPRegistered(msg.sender, liquidityAmount, requiredCollateral);
    }

    /**
     * @notice Remove LP from registry
     * @param lp The address of the LP to remove
     */
    function removeLP(address lp) external {
        if (msg.sender != lp) revert Unauthorized();
        if (!registeredLPs[lp]) revert NotRegisteredLP();
        
        CollateralInfo storage info = lpInfo[lp];
        if (info.liquidityAmount > 0) revert("LP has active liquidity");
        
        // Refund any remaining collateral
        if (info.collateralAmount > 0) {
            uint256 refundAmount = info.collateralAmount;
            info.collateralAmount = 0;
            reserveToken.transfer(lp, refundAmount);
        }
        
        // Remove LP
        registeredLPs[lp] = false;
        lpCount--;
        
        emit LPRemoved(lp);
    }

    /**
     * @notice Increase your liquidity amount
     * @param amount The amount of liquidity to add
     */
    function increaseLiquidity(uint256 amount) external nonReentrant onlyRegisteredLP {
        if (amount == 0) revert InvalidAmount();
        
        CollateralInfo storage info = lpInfo[msg.sender];

        (, , uint256 registrationRatio, ) = poolStrategy.getLPCollateralParams();
        
        // Calculate additional required collateral (20% of new liquidity)
        uint256 additionalCollateral = Math.mulDiv(amount, registrationRatio, BPS);
        
        // Transfer additional collateral
        reserveToken.transferFrom(msg.sender, address(this), additionalCollateral);
        
        // Update LP info
        info.liquidityAmount += amount;
        info.collateralAmount += additionalCollateral;
        
        // Update total liquidity
        totalLPLiquidity += amount;
        
        emit LiquidityIncreased(msg.sender, amount);
    }

    /**
     * @notice Decrease your liquidity amount
     * @param amount The amount of liquidity to remove
     */
    function decreaseLiquidity(uint256 amount) external nonReentrant onlyRegisteredLP {
        if (amount == 0) revert InvalidAmount();
        
        CollateralInfo storage info = lpInfo[msg.sender];
        if (amount > info.liquidityAmount) revert InsufficientLiquidity();

        (, , uint256 registrationRatio, ) = poolStrategy.getLPCollateralParams();
        
        // Calculate releasable collateral (20% of removed liquidity)
        uint256 releasableCollateral = Math.mulDiv(amount, registrationRatio, BPS);
        
        // Update LP info
        info.liquidityAmount -= amount;
        
        // Ensure remaining collateral meets minimum requirements for remaining liquidity
        uint256 requiredCollateral = poolStrategy.calculateLPRequiredCollateral(address(this), msg.sender);
        
        // Can only release excess collateral if remaining above minimum required
        if (info.collateralAmount - releasableCollateral >= requiredCollateral) {
            info.collateralAmount -= releasableCollateral;
            reserveToken.transfer(msg.sender, releasableCollateral);
        }
        
        // Update total liquidity
        totalLPLiquidity -= amount;
        
        emit LiquidityDecreased(msg.sender, amount);
    }

    /**
     * @notice Deposit additional collateral beyond the minimum
     * @param amount Amount of collateral to deposit
     */
    function deposit(uint256 amount) external nonReentrant onlyRegisteredLP {
        if (amount == 0) revert ZeroAmount();
        
        reserveToken.transferFrom(msg.sender, address(this), amount);
        lpInfo[msg.sender].collateralAmount += amount;
        
        emit CollateralDeposited(msg.sender, amount);
    }

    /**
     * @notice Withdraw excess collateral if above minimum requirements
     * @param amount Amount of collateral to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant onlyRegisteredLP {
        CollateralInfo storage info = lpInfo[msg.sender];
        if (amount == 0 || amount > info.collateralAmount) revert InvalidWithdrawalAmount();
        
        uint256 requiredCollateral = poolStrategy.calculateLPRequiredCollateral(address(this), msg.sender);
        if (info.collateralAmount - amount < requiredCollateral) {
            revert InsufficientCollateral();
        }
        
        info.collateralAmount -= amount;
        reserveToken.transfer(msg.sender, amount);
        
        emit CollateralWithdrawn(msg.sender, amount);
    }

    /**
    * @notice Liquidate an LP below threshold - Gas optimized version
    * @param lp Address of the LP to liquidate
    */
    function liquidateLP(address lp) external nonReentrant onlyRegisteredLP {
        if (!registeredLPs[lp] || lp == msg.sender) revert InvalidLiquidation();
        
        CollateralInfo memory targetInfo = lpInfo[lp];
        uint256 lpLiquidity = targetInfo.liquidityAmount;
        uint256 lpCollateral = targetInfo.collateralAmount;
        
        if (lpLiquidity == 0) revert NoLiquidityToLiquidate();
        
        uint256 lpAssetHolding = getLPAssetHolding(lp);

        (, uint256 warningThreshold, , uint256 liquidationReward) = poolStrategy.getLPCollateralParams();
        
        // Check liquidation eligibility
         // we need to convert the assetHolding to the same decimal factor as the reserve token i.e collateral
        if (lpCollateral * BPS * reserveToAssetDecimalFactor >= lpAssetHolding * warningThreshold) {
            revert NotEligibleForLiquidation();
        }
        
        // Calculate liquidation reward
        uint256 reward = lpCollateral * liquidationReward / BPS;
        
        // Calculate remaining collateral
        uint256 remainingCollateral = lpCollateral - reward;
        
        // Calculate liquidator's new position requirements
        CollateralInfo memory callerInfo = lpInfo[msg.sender];
        uint256 callerAssetHolding = getLPAssetHolding(msg.sender);
        
        // Add target LP's asset holding to caller's
        uint256 newCallerAssetHolding = callerAssetHolding + lpAssetHolding;
         // we need to convert the assetHolding to the same decimal factor as the reserve token i.e collateral
        uint256 newRequiredCollateral = newCallerAssetHolding * warningThreshold / 100_00 * reserveToAssetDecimalFactor;
        
        // Check if additional collateral is needed
        uint256 additionalCollateralNeeded = 0;
        if (newRequiredCollateral > callerInfo.collateralAmount) {
            additionalCollateralNeeded = newRequiredCollateral - callerInfo.collateralAmount;
            
            // Transfer additional collateral in one go if needed
            reserveToken.transferFrom(msg.sender, address(this), additionalCollateralNeeded);
        }
        
        lpInfo[msg.sender].liquidityAmount = callerInfo.liquidityAmount + lpLiquidity;
        lpInfo[msg.sender].collateralAmount = callerInfo.collateralAmount + additionalCollateralNeeded + reward;
        
        // Reset liquidated LP's position
        delete lpInfo[lp];
        
        if (remainingCollateral > 0) {
            reserveToken.transfer(lp, remainingCollateral);
        }
        
        emit LPLiquidated(lp, msg.sender, reward);
    }

    /**
     * @notice Deduct rebalance amount from LP's collateral
     * @param lp Address of the LP
     * @param amount Amount to deduct
     */
    function deductRebalanceAmount(address lp, uint256 amount) external onlyPoolCycleManager {
        if (!registeredLPs[lp]) revert NotRegisteredLP();
            
        CollateralInfo storage info = lpInfo[lp];
        if (amount > info.collateralAmount) revert InsufficientCollateral();

        uint8 collateralHealth = poolStrategy.getLPCollateralHealth(address(this), lp);
        if (collateralHealth == 1) revert InsufficientCollateral();
            
        info.collateralAmount -= amount;
        reserveToken.transfer(address(assetPool), amount);
        
        emit RebalanceDeducted(lp, amount);
    }

    /**
     * @notice Add rebalance amount or interest to LP's collateral
     * @param lp Address of the LP
     * @param amount Amount to add
     */
    function addToCollateral(address lp, uint256 amount) external onlyPoolCycleManager {
        if (!registeredLPs[lp]) revert NotRegisteredLP();
        
        lpInfo[lp].collateralAmount += amount;
        
        emit RebalanceAdded(lp, amount);
    }

    /**
     * @notice Calculate Lp's current asset holding
     * @param lp Address of the LP
     */
    function getLPAssetHolding(address lp) public view returns (uint256) {
        if (!registeredLPs[lp]) return 0;
        
        uint256 poolValue = assetPool.getPoolValue();
        uint256 lpShare = getLPLiquidityShare(lp);

        uint256 lpAssetHolding = Math.mulDiv(lpShare, poolValue, PRECISION);
        
        return lpAssetHolding;
    }

    /**
     * @notice Get LP's current liquidity share of the pool
     * @param lp Address of the LP
     */
    function getLPLiquidityShare(address lp) public view returns (uint256) {
        if (!registeredLPs[lp]) return 0;
        // If no total liquidity, no collateral required
        if (totalLPLiquidity == 0) return 0;
        return Math.mulDiv(lpInfo[lp].liquidityAmount, PRECISION, totalLPLiquidity);
    }
    
    /**
     * @notice Get LP's current collateral and liquidity info
     * @param lp Address of the LP
     */
    function getLPInfo(address lp) external view returns (CollateralInfo memory) {
        return lpInfo[lp];
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
     * @notice Returns the current liquidity amount for an LP
     * @param lp The address of the LP
     * @return uint256 The current liquidity amount
     */
    function getLPLiquidity(address lp) external view returns (uint256) {
        return lpInfo[lp].liquidityAmount;
    }
    
    /**
     * @notice Returns the total liquidity amount
     * @return uint256 The total liquidity amount
     */
    function getTotalLPLiquidity() external view returns (uint256) {
        return totalLPLiquidity;
    }

    /**
     * @notice Returns the reserve to asset decimal factor
     */
    function getReserveToAssetDecimalFactor() external view returns (uint256) {
        return reserveToAssetDecimalFactor;
    }
}