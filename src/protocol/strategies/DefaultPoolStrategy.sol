// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "../../interfaces/IPoolStrategy.sol";
import "../../interfaces/IPoolLiquidityManager.sol";
import "../../interfaces/IAssetPool.sol";
import "../../interfaces/IXToken.sol";
import "../../interfaces/IAssetOracle.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title DefaultPoolStrategy
 * @notice Default implementation of pool strategy with standard interest, collateral & liquidity models
 */
contract DefaultPoolStrategy is IPoolStrategy, Ownable {
    // --------------------------------------------------------------------------------
    //                               STATE VARIABLES
    // --------------------------------------------------------------------------------

    // cycle parameters
    uint256 public rebalanceLength;       // length of onchain rebalancing period (default: 3 hours)
    uint256 public oracleUpdateThreshold; // Threshold for oracle update (default: 15 minutes)
    uint256 public haltThreshold;        // Threshold for halting the pool (default: 5 days)
    
    // Asset interest rate parameters
    uint256 public baseInterestRate;      // Base interest rate (e.g., 9%)
    uint256 public interestRate1;         // Tier 1 interest rate (e.g., 18%)
    uint256 public maxInterestRate;       // Maximum interest rate (e.g., 72%)
    uint256 public utilizationTier1;      // First utilization tier (e.g., 65%)
    uint256 public utilizationTier2;      // Second utilization tier (e.g., 85%)
    
    // Fee parameters
    uint256 public protocolFeePercentage; // Fee on interest (e.g., 10.0%)
    address public feeRecipient;          // Address to receive fees
    
    // User collateral parameters 
    uint256 public userHealthyCollateralRatio;    // Healthy ratio (e.g., 20%)
    uint256 public userLiquidationThreshold;      // Liquidation threshold (e.g., 12.5%)
    
    // LP liquidity parameters 
    uint256 public lpHealthyLiquidityRatio;      // Healthy ratio (e.g., 30%)
    uint256 public lpLiquidationThreshold;        // Liquidatiom threshold (e.g., 20%) 
    uint256 public lpLiquidationReward;           // Liquidation reward (e.g., 0.5%)
    
    // Constants
    uint256 private constant BPS = 100_00;  // 100% in basis points (10000)
    uint256 private constant PRECISION = 1e18; // Precision for calculations
    
    // --------------------------------------------------------------------------------
    //                                  CONSTRUCTOR
    // --------------------------------------------------------------------------------

    /**
     * @notice Initializes the DefaultPoolStrategy contract with default owner
     * @dev Parameters are set separately via setter functions
     */
    constructor() Ownable(msg.sender) {
    }
    
    // --------------------------------------------------------------------------------
    //                                CONFIGURATION FUNCTIONS
    // --------------------------------------------------------------------------------


    /**
     * @notice Sets the cycle parameters
     * @param _rebalanceLength Length of rebalancing period in seconds
     * @param _oracleUpdateThreshold Threshold for oracle update

     */
    function setCycleParams(
        uint256 _rebalanceLength,
        uint256 _oracleUpdateThreshold,
        uint256 _haltThreshold
    ) external onlyOwner {
        rebalanceLength = _rebalanceLength;
        oracleUpdateThreshold = _oracleUpdateThreshold;
        haltThreshold = _haltThreshold;

        emit CycleParamsUpdated(_rebalanceLength, _oracleUpdateThreshold, _haltThreshold);
    }
    
    /**
     * @notice Sets the interest rate parameters
     * @param baseRate Base interest rate (scaled by 10000)
     * @param rate1 Tier 1 interest rate (scaled by 10000)
     * @param maxRate Maximum interest rate (scaled by 10000)
     * @param utilTier1 First utilization tier (scaled by 10000)
     * @param utilTier2 Second utilization tier (scaled by 10000)
     */
    function setInterestRateParams(
        uint256 baseRate,
        uint256 rate1,
        uint256 maxRate,
        uint256 utilTier1,
        uint256 utilTier2
    ) external onlyOwner {
        // Parameter validation
        require(baseRate <= rate1, "Base rate must be <= Interest rate 1");
        require(rate1 <= maxRate, "Interest rate 1 must be <= max rate");
        require(maxRate <= BPS, "Max rate cannot exceed 100%");
        require(utilTier1 < utilTier2, "Tier1 must be < Tier2");
        require(utilTier2 < BPS, "Tier2 must be < BPS");
        
        baseInterestRate = baseRate;
        interestRate1 = rate1;
        maxInterestRate = maxRate;
        utilizationTier1 = utilTier1;
        utilizationTier2 = utilTier2;
        
        emit InterestRateParamsUpdated(
            baseRate,
            interestRate1,
            maxRate,
            utilTier1,
            utilTier2
        );
    }
    
    /**
     * @notice Sets the fee parameters
     * @param protocolFee fee on interest (scaled by 10000)
     * @param _feeRecipient Address to receive fees
     */
    function setProtocolFeeParams(
        uint256 protocolFee,
        address _feeRecipient
    ) external onlyOwner {
        require(
            protocolFee <= BPS, 
            "Fees cannot exceed 100%"
        );
        require(_feeRecipient != address(0), "Invalid fee recipient");
        
        protocolFeePercentage = protocolFee;
        feeRecipient = _feeRecipient;
        
        emit FeeParamsUpdated(
            protocolFee,
            _feeRecipient
        );
    }
    
    /**
     * @notice Sets the user collateral parameters
     * @param healthyRatio Healthy collateral ratio (scaled by 10000)
     * @param liquidationRatio Liquidation threshold (scaled by 10000)
     */
    function setUserCollateralParams(
        uint256 healthyRatio,
        uint256 liquidationRatio
    ) external onlyOwner {
        require(liquidationRatio <= healthyRatio, "Liquidation ratio must be <= healthy ratio");
        
        userHealthyCollateralRatio = healthyRatio;
        userLiquidationThreshold = liquidationRatio;
        
        emit UserCollateralParamsUpdated(
            healthyRatio,
            liquidationRatio
        );
    }
    
    /**
     * @notice Sets the LP liquidity parameters
     * @param healthyRatio Healthy liquidity ratio (scaled by 10000)
     * @param liquidationThreshold Warning threshold (scaled by 10000)
     * @param liquidationReward Liquidation reward (scaled by 10000)
     */
    function setLPLiquidityParams(
        uint256 healthyRatio,
        uint256 liquidationThreshold,
        uint256 liquidationReward
    ) external onlyOwner {
        require(liquidationThreshold <= healthyRatio, "liquidation threshold must be <= healthy ratio");
        require(liquidationReward <= BPS, "Reward cannot exceed 100%");
        
        lpHealthyLiquidityRatio = healthyRatio;
        lpLiquidationThreshold = liquidationThreshold;
        lpLiquidationReward = liquidationReward;
        
        emit LPLiquidityParamsUpdated(
            healthyRatio,
            liquidationThreshold,
            liquidationReward
        );
    }

    // --------------------------------------------------------------------------------
    //                             CYCLE FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Returns the cycle parameters
     * @return rebalancePeriod Length of rebalancing period in seconds
     * @return oracleThreshold Threshold for oracle update
     * @return poolHaltThreshold Threshold for halting the pool
     */
    function getCycleParams() external view returns (
        uint256 rebalancePeriod,
        uint256 oracleThreshold,
        uint256 poolHaltThreshold
    ) {
        return (rebalanceLength, oracleUpdateThreshold, haltThreshold);
    }
    
    // --------------------------------------------------------------------------------
    //                             ASSET INTEREST FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Returns all interest rate parameters
     * @return baseRate The base interest rate (scaled by 10000)
     * @return rate1 The tier 1 interest rate (scaled by 10000)
     * @return maxRate The maximum interest rate (scaled by 10000)
     * @return utilTier1 The first utilization tier (scaled by 10000)
     * @return utilTier2 The second utilization tier (scaled by 10000)
     */
    function getInterestRateParams() external view returns (
        uint256 baseRate,
        uint256 rate1,
        uint256 maxRate,
        uint256 utilTier1,
        uint256 utilTier2
    ) {
        return (
            baseInterestRate,
            interestRate1,
            maxInterestRate,
            utilizationTier1,
            utilizationTier2
        );
    }

    /**
     * @notice Calculate interest rate based on utilization
     * @param utilization Current utilization rate (scaled by 10000)
     * @return rate Current interest rate (scaled by 10000)
     */
    function calculateInterestRate(uint256 utilization) external view returns (uint256 rate) {
        if (utilization <= utilizationTier1) {
            // Base rate when utilization <= Tier1
            return baseInterestRate;
        } else if (utilization <= utilizationTier2) {
            // Linear increase from base rate to interest rate 1
            uint256 utilizationDelta = utilization - utilizationTier1;
            uint256 optimalDelta = utilizationTier2 - utilizationTier1;
            
            uint256 additionalRate = ((interestRate1 - baseInterestRate) * utilizationDelta) / optimalDelta;
            return baseInterestRate + additionalRate;
        } else if (utilization <= BPS) {
            // Linear increase from interest rate 1 to max rate
            uint256 utilizationDelta = utilization - utilizationTier2;
            uint256 optimalDelta = BPS - utilizationTier2;
            
            uint256 additionalRate = ((maxInterestRate - interestRate1) * utilizationDelta) / optimalDelta;
            return interestRate1 + additionalRate;
        } else {
            return maxInterestRate; // Max rate
        }
    }
    
    // --------------------------------------------------------------------------------
    //                             FEE FUNCTIONS
    // --------------------------------------------------------------------------------
    
    /**
     * @notice Returns protocol fee percentage
     */
    function getProtocolFee() external view returns (
        uint256 protocolFee
    ) {
        return protocolFeePercentage;
    }
    
    /**
     * @notice Returns the fee recipient address
     */
    function getFeeRecipient() external view returns (address) {
        return feeRecipient;
    }
    
    // --------------------------------------------------------------------------------
    //                             COLLATERAL & LIQUIDITY FUNCTIONS
    // --------------------------------------------------------------------------------
    
    /**
     * @notice Returns user collateral parameters
     */
    function getUserCollateralParams() external view returns (
        uint256 healthyRatio,
        uint256 liquidationThreshold
    ) {
        return (
            userHealthyCollateralRatio,
            userLiquidationThreshold
        );
    }
    
    /**
     * @notice Returns LP liquidity parameters
     */
    function getLPLiquidityParams() external view returns (
        uint256 healthyRatio,
        uint256 liquidationThreshold,
        uint256 liquidationReward
    ) {
        return (
            lpHealthyLiquidityRatio,
            lpLiquidationThreshold,
            lpLiquidationReward
        );
    }
    
    /**
     * @notice Calculates required user collateral
     * @param assetPool Address of the asset pool
     * @param user Address of the user
     */
    function calculateUserRequiredCollateral(address assetPool, address user) external view returns (uint256) {
        IAssetPool pool = IAssetPool(assetPool);
        IPoolCycleManager cycleManager = IPoolCycleManager(pool.getPoolCycleManager());

        uint256 reserveToAssetDecimalFactor = pool.getReserveToAssetDecimalFactor();
        // Get the previous cycle's rebalance price
        uint256 prevCycle = cycleManager.cycleIndex() - 1;
        uint256 rebalancePrice = cycleManager.cycleRebalancePrice(prevCycle);
        (uint256 assetAmount, , uint256 interestDebt) = pool.userPosition(user);
        uint256 assetValue = Math.mulDiv(assetAmount, rebalancePrice, PRECISION);
        
        uint256 requiredCollateral = Math.mulDiv(assetValue, userHealthyCollateralRatio, BPS);
        uint256 interestDebtValue = Math.mulDiv(interestDebt, rebalancePrice, PRECISION * reserveToAssetDecimalFactor);
        return requiredCollateral + interestDebtValue;
    }
    
    /**
     * @notice Calculates required LP collateral
     * @param liquidityManager Address of the pool liquidity manager
     * @param lp Address of the LP
     */
    function calculateLPRequiredCollateral(address liquidityManager, address lp) external view returns (uint256) {
        
        IPoolLiquidityManager manager = IPoolLiquidityManager(liquidityManager);
        uint256 lpAssetValue = manager.getLPAssetHoldingValue(lp);

        return Math.mulDiv(lpAssetValue, lpHealthyLiquidityRatio, BPS);
    }

    /**
     * @notice Check collateral health status of a user
     * @param user User address
     * @return health 3 = Healthy, 2 = Warning, 1 = Liquidatable
     */
    function getUserCollateralHealth(address assetPool, address user) external view returns (uint8 health) {
        IAssetPool pool = IAssetPool(assetPool);
        IPoolCycleManager cycleManager = IPoolCycleManager(pool.getPoolCycleManager());
        
        ( uint256 assetAmount,
          uint256 collateralAmount, 
          uint256 interestDebt
        ) = pool.userPosition(user);

        if (assetAmount == 0) {
            return 3; // Healthy - no asset balance means no risk
        }

        uint256 reserveToAssetDecimalFactor = pool.getReserveToAssetDecimalFactor();
        // Get the previous cycle's rebalance price
        uint256 prevCycle = cycleManager.cycleIndex() - 1;
        uint256 rebalancePrice = cycleManager.cycleRebalancePrice(prevCycle);
        uint256 assetValue = Math.mulDiv(assetAmount, rebalancePrice, PRECISION);
        uint256 userCollateralBalance = collateralAmount - Math.mulDiv(interestDebt, rebalancePrice, PRECISION * reserveToAssetDecimalFactor);

        uint256 healthyCollateral = Math.mulDiv(assetValue, userHealthyCollateralRatio, BPS);
        uint256 reqCollateral = Math.mulDiv(assetValue, userLiquidationThreshold, BPS);
        
        if (userCollateralBalance >= healthyCollateral) {
            return 3; // Healthy
        } else if (userCollateralBalance >= reqCollateral) {
            return 2; // Warning
        } else {
            return 1; // Liquidatable
        }
    }

    /**
     * @notice Check liquidity health status of an LP
     * @param lp Address of the LP
     * @return health 3 = Healthy, 2 = Warning, 1 = Liquidatable
     */
    function getLPLiquidityHealth(address liquidityManager, address lp) external view returns (uint8 health) {
        IPoolLiquidityManager manager = IPoolLiquidityManager(liquidityManager);
        
        uint256 lpAssetValue = manager.getLPAssetHoldingValue(lp);
        IPoolLiquidityManager.LPPosition memory position = manager.getLPPosition(lp);
        uint256 lpCollateral = position.collateralAmount;
        
        uint256 healthyLiquidity = Math.mulDiv(lpAssetValue, lpHealthyLiquidityRatio, BPS);
        uint256 reqLiquidity = Math.mulDiv(lpAssetValue, lpLiquidationThreshold, BPS);
        
        if (lpCollateral >= healthyLiquidity) {
            return 3; // Healthy
        } else if (lpCollateral >= reqLiquidity) {
            return 2; // Warning
        } else {
            return 1; // Liquidatable
        }
    }
}