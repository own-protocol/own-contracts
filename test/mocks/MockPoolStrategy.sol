// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "../../src/interfaces/IPoolStrategy.sol";
import "../../src/interfaces/IPoolLiquidityManager.sol";
import "../../src/interfaces/IAssetPool.sol";
import "../../src/interfaces/IXToken.sol";
import "../../src/interfaces/IAssetOracle.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title MockPoolStrategy
 * @notice Mock implementation of pool strategy for testing with properly implemented interface functions
 */
contract MockPoolStrategy is IPoolStrategy, Ownable {
    // --------------------------------------------------------------------------------
    //                               STATE VARIABLES
    // --------------------------------------------------------------------------------

    // cycle parameters
    uint256 public rebalanceLength;             // length of onchain rebalancing period 
    uint256 public oracleUpdateThreshold;       // Threshold for oracle update
    uint256 public haltThreshold;               // Threshold for halting the pool
    
    // Asset interest rate parameters
    uint256 public baseInterestRate;            // Base interest rate
    uint256 public interestRate1;               // Tier 1 interest rate
    uint256 public maxInterestRate;             // Maximum interest rate
    uint256 public utilizationTier1;            // First utilization tier
    uint256 public utilizationTier2;            // Second utilization tier
    
    // Fee parameters
    uint256 public protocolFeePercentage;       // Fee on interest
    address public feeRecipient;                // Address to receive fees
    
    // User collateral parameters 
    uint256 public userHealthyCollateralRatio;  // Healthy ratio
    uint256 public userLiquidationThreshold;    // Liquidation threshold
    
    // LP liquidity parameters 
    uint256 public lpHealthyLiquidityRatio;     // Healthy ratio
    uint256 public lpLiquidationThreshold;      // Liquidatiom threshold 
    uint256 public lpLiquidationReward;         // Liquidation reward

    // Yield generating reserve
    bool public isYieldBearing;                // Flag to indicate if the reserve is yield generating
    
    // Constants
    uint256 private constant BPS = 100_00;      // 100% in basis points (10000)
    uint256 private constant PRECISION = 1e18;  // Precision for calculations
    
    constructor() Ownable(msg.sender) {
        // Set default values for tests
        rebalanceLength = 1 days;
        oracleUpdateThreshold = 15 minutes;
        haltThreshold = 5 days;
        
        // Set interest rate parameters
        baseInterestRate = 900; // 9%
        interestRate1 = 1800;   // 18%
        maxInterestRate = 7200; // 72%
        utilizationTier1 = 6500; // 65%
        utilizationTier2 = 8500; // 85%
        
        // Set fee parameters  
        protocolFeePercentage = 1000; // 10%
        feeRecipient = address(this);
        
        // Set user collateral parameters
        userHealthyCollateralRatio = 2000; // 20%
        userLiquidationThreshold = 1250;  // 12.5%
        
        // Set LP parameters
        lpHealthyLiquidityRatio = 3000;  // 30%
        lpLiquidationThreshold = 2000;   // 20%
        lpLiquidationReward = 50;        // 0.5%
    }

    // --------------------------------------------------------------------------------
    //                                CONFIGURATION FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Sets the cycle parameters
     * @param _rebalanceLength Length of rebalancing period in seconds
     * @param _oracleUpdateThreshold Threshold for oracle update
     * @param _haltThreshold Threshold for halting the pool
     */
    function setCycleParams(
        uint256 _rebalanceLength,
        uint256 _oracleUpdateThreshold,
        uint256 _haltThreshold
    ) external override onlyOwner {
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
    ) external override onlyOwner {
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
    ) external override onlyOwner {
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
    ) external override onlyOwner {
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
    ) external override onlyOwner {
        lpHealthyLiquidityRatio = healthyRatio;
        lpLiquidationThreshold = liquidationThreshold;
        lpLiquidationReward = liquidationReward;
        
        emit LPLiquidityParamsUpdated(
            healthyRatio,
            liquidationThreshold,
            liquidationReward
        );
    }

    /**
     * @notice Sets the yield generating reserve flag
     */
    function setIsYieldBearing() external override onlyOwner {
        isYieldBearing = !isYieldBearing;
        
        emit IsYieldBearingUpdated(
            isYieldBearing
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
    function getCycleParams() external view override returns (
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
    function getInterestRateParams() external view override returns (
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
    function calculateInterestRate(uint256 utilization) external view override returns (uint256 rate) {
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
    function getProtocolFee() external view override returns (
        uint256 protocolFee
    ) {
        return protocolFeePercentage;
    }
    
    /**
     * @notice Returns the fee recipient address
     */
    function getFeeRecipient() external view override returns (address) {
        return feeRecipient;
    }
    
    // --------------------------------------------------------------------------------
    //                             COLLATERAL & LIQUIDITY FUNCTIONS
    // --------------------------------------------------------------------------------
    
    /**
     * @notice Returns user collateral parameters
     */
    function getUserCollateralParams() external view override returns (
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
    function getLPLiquidityParams() external view override returns (
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
    function calculateUserRequiredCollateral(address assetPool, address user) external view override returns (uint256) {
        IAssetPool pool = IAssetPool(assetPool);
        IPoolCycleManager cycleManager = IPoolCycleManager(pool.getPoolCycleManager());

        uint256 reserveToAssetDecimalFactor = pool.getReserveToAssetDecimalFactor();
        // Get the previous cycle's rebalance price
        uint256 prevCycle = cycleManager.cycleIndex() - 1;
        uint256 rebalancePrice = cycleManager.cycleRebalancePrice(prevCycle);
        (uint256 assetAmount , ,) = pool.userPositions(user);
        uint256 assetValue = Math.mulDiv(assetAmount, rebalancePrice, PRECISION);
        uint256 interestDebt = pool.getInterestDebt(user, prevCycle);
        
        uint256 requiredCollateral = Math.mulDiv(assetValue, userHealthyCollateralRatio, BPS);
        uint256 interestDebtValue = Math.mulDiv(interestDebt, rebalancePrice, PRECISION * reserveToAssetDecimalFactor);
        return requiredCollateral + interestDebtValue;
    }
    
    /**
     * @notice Calculates required LP collateral
     * @param liquidityManager Address of the pool liquidity manager
     * @param lp Address of the LP
     */
    function calculateLPRequiredCollateral(address liquidityManager, address lp) external view override returns (uint256) {
        IPoolLiquidityManager manager = IPoolLiquidityManager(liquidityManager);
        uint256 lpAssetValue = manager.getLPAssetHoldingValue(lp);

        return Math.mulDiv(lpAssetValue, lpHealthyLiquidityRatio, BPS);
    }

    /**
     * @notice Check collateral health status of a user
     * @param user User address
     * @return health 3 = Healthy, 2 = Warning, 1 = Liquidatable
     */
    function getUserCollateralHealth(address assetPool, address user) external view override returns (uint8 health) {
        IAssetPool pool = IAssetPool(assetPool);
        IPoolCycleManager cycleManager = IPoolCycleManager(pool.getPoolCycleManager());
        
       (uint256 assetAmount , , uint256 collateralAmount) = pool.userPositions(user);

        if (assetAmount == 0) {
            return 3; // Healthy - no asset balance means no risk
        }

        uint256 reserveToAssetDecimalFactor = pool.getReserveToAssetDecimalFactor();
        // Get the previous cycle's rebalance price
        uint256 prevCycle = cycleManager.cycleIndex() - 1;
        uint256 rebalancePrice = cycleManager.cycleRebalancePrice(prevCycle);
        uint256 interestDebt = pool.getInterestDebt(user, prevCycle);
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
    function getLPLiquidityHealth(address liquidityManager, address lp) external view override returns (uint8 health) {
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

    // --------------------------------------------------------------------------------
    //                             YIELD FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Calculates the reserve yield based on initial and current amounts
     * @param prevAmount Previous amount of tokens
     * @param currentAmount Current amount of tokens
     * @param depositAmount Amount of tokens deposited
     * @return yield The calculated yield (scaled by PRECISION)
     */
    function calculateYieldAccrued(
        uint256 prevAmount, 
        uint256 currentAmount,
        uint256 depositAmount
    ) external pure override returns (uint256) {  
        if (depositAmount == 0) {
            return 0; // No yield if no previous amount
        }      
        // Calculate yield
        uint256 yield = Math.mulDiv(currentAmount - prevAmount, PRECISION, depositAmount);
        return yield;
    }
}