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
 * @notice Default implementation of pool strategy with standard interest and collateral models
 * @dev Uses variable LP collateral based on asset holdings and fixed user collateral based on deposits
 */
contract DefaultPoolStrategy is IPoolStrategy, Ownable {
    // --------------------------------------------------------------------------------
    //                               STATE VARIABLES
    // --------------------------------------------------------------------------------

    // cycle parameters
    uint256 public cycleLength;           // Length of each cycle (default 0, not used)
    uint256 public rebalanceLength;      // length of onchain rebalancing period (default: 3 hours)
    uint256 public oracleUpdateThreshold; // Threshold for oracle update (15 minutes)
    
    // Asset interest rate parameters
    uint256 public baseInterestRate;      // Base interest rate (e.g., 9%)
    uint256 public interestRate1;         // Tier 1 interest rate (e.g., 18%)
    uint256 public maxInterestRate;       // Maximum interest rate (e.g., 72%)
    uint256 public utilizationTier1;      // First utilization tier (e.g., 50%)
    uint256 public utilizationTier2;      // Second utilization tier (e.g., 85%)
    uint256 public maxUtilization;        // Maximum utilization (e.g., 100%)
    
    // Fee parameters
    uint256 public depositFeePercentage;  // Fee for deposits (e.g., 0.0%)
    uint256 public redemptionFeePercentage; // Fee for redemptions (e.g., 0.0%)
    uint256 public interestFeePercentage; // Fee on interest (e.g., 0.0%)
    uint256 public yieldFeePercentage;    // Fee on reserve token yield (e.g., 0.0%)
    address public feeRecipient;          // Address to receive fees
    
    // User collateral parameters (fixed deposit based)
    uint256 public userHealthyCollateralRatio;    // Healthy ratio (e.g., 20%)
    uint256 public userLiquidationThreshold;      // Liquidation threshold (e.g., 10%)
    uint256 public userLiquidationReward;         // Liquidation reward (e.g., 5%)
    
    // LP collateral parameters (variable asset based)
    uint256 public lpHealthyCollateralRatio;      // Healthy ratio (e.g., 50%)
    uint256 public lpWarningThreshold;            // Warning threshold (e.g., 30%) 
    uint256 public lpRegistrationRatio;           // Registration minimum (e.g., 20%)
    uint256 public lpLiquidationReward;           // Liquidation reward (e.g., 5%)
    
    // Constants
    uint256 private constant BPS = 100_00;  // 100% in basis points (10000)
    
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
     * @param _cycleLength Length of each cycle in seconds
     * @param _rebalanceLength Length of rebalancing period in seconds
     * @param _oracleUpdateThreshold Threshold for oracle update
     */
    function setCycleParams(
        uint256 _cycleLength, 
        uint256 _rebalanceLength,
        uint256 _oracleUpdateThreshold
    ) external onlyOwner {
        require(_rebalanceLength <= _cycleLength, "Rebalance length must be < cycle length");
        cycleLength = _cycleLength;
        rebalanceLength = _rebalanceLength;
        oracleUpdateThreshold = _oracleUpdateThreshold;

        emit CycleParamsUpdated(_cycleLength, _rebalanceLength, _oracleUpdateThreshold);
    }
    
    /**
     * @notice Sets the interest rate parameters
     * @param baseRate Base interest rate (scaled by 10000)
     * @param rate1 Tier 1 interest rate (scaled by 10000)
     * @param maxRate Maximum interest rate (scaled by 10000)
     * @param utilTier1 First utilization tier (scaled by 10000)
     * @param utilTier2 Second utilization tier (scaled by 10000)
     * @param maxUtil Maximum utilization (scaled by 10000)
     */
    function setInterestRateParams(
        uint256 baseRate,
        uint256 rate1,
        uint256 maxRate,
        uint256 utilTier1,
        uint256 utilTier2,
        uint256 maxUtil
    ) external onlyOwner {
        // Parameter validation
        require(baseRate <= rate1, "Base rate must be <= Interest rate 1");
        require(rate1 <= maxRate, "Interest rate 1 must be <= max rate");
        require(maxRate <= BPS, "Max rate cannot exceed 100%");
        require(utilTier1 < utilTier2, "Tier1 must be < Tier2");
        require(utilTier2 < maxUtil, "Tier2 must be < max utilization");
        
        baseInterestRate = baseRate;
        interestRate1 = rate1;
        maxInterestRate = maxRate;
        utilizationTier1 = utilTier1;
        utilizationTier2 = utilTier2;
        maxUtilization = maxUtil;
        
        emit InterestRateParamsUpdated(
            baseRate,
            interestRate1,
            maxRate,
            utilTier1,
            utilTier2,
            maxUtil
        );
    }
    
    /**
     * @notice Sets the fee parameters
     * @param depositFee Fee for deposits (scaled by 10000)
     * @param redemptionFee Fee for redemptions (scaled by 10000)
     * @param interestFee Fee on interest (scaled by 10000)
     * @param yieldFee Fee on reserve token yield (scaled by 10000)
     * @param _feeRecipient Address to receive fees
     */
    function setFeeParams(
        uint256 depositFee,
        uint256 redemptionFee,
        uint256 interestFee,
        uint256 yieldFee,
        address _feeRecipient
    ) external onlyOwner {
        require(
            depositFee <= BPS && 
            redemptionFee <= BPS && 
            interestFee <= BPS && 
            yieldFee <= BPS, 
            "Fees cannot exceed 100%"
        );
        require(_feeRecipient != address(0), "Invalid fee recipient");
        
        depositFeePercentage = depositFee;
        redemptionFeePercentage = redemptionFee;
        interestFeePercentage = interestFee;
        yieldFeePercentage = yieldFee;
        feeRecipient = _feeRecipient;
        
        emit FeeParamsUpdated(
            depositFee,
            redemptionFee,
            interestFee,
            yieldFee,
            _feeRecipient
        );
    }
    
    /**
     * @notice Sets the user collateral parameters
     * @param healthyRatio Healthy collateral ratio (scaled by 10000)
     * @param liquidationRatio Liquidation threshold (scaled by 10000)
     * @param liquidationReward Liquidation reward (scaled by 10000)
     */
    function setUserCollateralParams(
        uint256 healthyRatio,
        uint256 liquidationRatio,
        uint256 liquidationReward
    ) external onlyOwner {
        require(liquidationRatio < healthyRatio, "Liquidation ratio must be < healthy ratio");
        require(liquidationReward <= BPS, "Reward cannot exceed 100%");
        
        userHealthyCollateralRatio = healthyRatio;
        userLiquidationThreshold = liquidationRatio;
        userLiquidationReward = liquidationReward;
        
        emit UserCollateralParamsUpdated(
            healthyRatio,
            liquidationRatio,
            liquidationReward
        );
    }
    
    /**
     * @notice Sets the LP collateral parameters
     * @param healthyRatio Healthy collateral ratio (scaled by 10000)
     * @param warningThreshold Warning threshold (scaled by 10000)
     * @param registrationRatio Registration minimum ratio (scaled by 10000)
     * @param liquidationReward Liquidation reward (scaled by 10000)
     */
    function setLPCollateralParams(
        uint256 healthyRatio,
        uint256 warningThreshold,
        uint256 registrationRatio,
        uint256 liquidationReward
    ) external onlyOwner {
        require(warningThreshold < healthyRatio, "Warning threshold must be < healthy ratio");
        require(registrationRatio <= warningThreshold, "Registration ratio must be <= warning threshold");
        require(liquidationReward <= BPS, "Reward cannot exceed 100%");
        
        lpHealthyCollateralRatio = healthyRatio;
        lpWarningThreshold = warningThreshold;
        lpRegistrationRatio = registrationRatio;
        lpLiquidationReward = liquidationReward;
        
        emit LPCollateralParamsUpdated(
            healthyRatio,
            warningThreshold,
            registrationRatio,
            liquidationReward
        );
    }

    // --------------------------------------------------------------------------------
    //                             CYCLE FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Returns the cycle parameters
     * @return cyclePeriod Length of each cycle in seconds
     * @return rebalancePeriod Length of rebalancing period in seconds
     * @return oracleThreshold Threshold for oracle update
     */
    function getCycleParams() external view returns (
        uint256 cyclePeriod, 
        uint256 rebalancePeriod,
        uint256 oracleThreshold
    ) {
        return (cycleLength, rebalanceLength, oracleThreshold);
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
     * @return maxUtil The maximum utilization (scaled by 10000)
     */
    function getInterestRateParams() external view returns (
        uint256 baseRate,
        uint256 rate1,
        uint256 maxRate,
        uint256 utilTier1,
        uint256 utilTier2,
        uint256 maxUtil
    ) {
        return (
            baseInterestRate,
            interestRate1,
            maxInterestRate,
            utilizationTier1,
            utilizationTier2,
            maxUtilization
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
        } else if (utilization <= maxUtilization) {
            // Linear increase from interest rate 1 to max rate
            uint256 utilizationDelta = utilization - utilizationTier2;
            uint256 optimalDelta = maxUtilization - utilizationTier2;
            
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
     * @notice Returns fee percentages for different operations
     */
    function getFeePercentages() external view returns (
        uint256 depositFee,
        uint256 redemptionFee,
        uint256 interestFee,
        uint256 yieldFee
    ) {
        return (depositFeePercentage, redemptionFeePercentage, interestFeePercentage, yieldFeePercentage);
    }
    
    /**
     * @notice Returns the fee recipient address
     */
    function getFeeRecipient() external view returns (address) {
        return feeRecipient;
    }
    
    // --------------------------------------------------------------------------------
    //                             COLLATERAL FUNCTIONS
    // --------------------------------------------------------------------------------
    
    /**
     * @notice Returns user collateral parameters
     */
    function getUserCollateralParams() external view returns (
        uint256 healthyRatio,
        uint256 liquidationThreshold,
        uint256 liquidationReward
    ) {
        return (
            userHealthyCollateralRatio,
            userLiquidationThreshold,
            userLiquidationReward
        );
    }
    
    /**
     * @notice Returns LP collateral parameters
     */
    function getLPCollateralParams() external view returns (
        uint256 healthyRatio,
        uint256 warningThreshold,
        uint256 registrationRatio,
        uint256 liquidationReward
    ) {
        return (
            lpHealthyCollateralRatio,
            lpWarningThreshold,
            lpRegistrationRatio,
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
        (uint256 assetAmount, , uint256 interestDebt) = pool.userPosition(user);

        IAssetOracle oracle = IAssetOracle(pool.getAssetOracle());
        uint256 assetValue = assetAmount * oracle.assetPrice();
        
        uint256 baseCollateral = Math.mulDiv(assetValue, userHealthyCollateralRatio, BPS);
        return baseCollateral + interestDebt;
    }
    
    /**
     * @notice Calculates required LP collateral
     * @param liquidityManager Address of the pool liquidity manager
     * @param lp Address of the LP
     */
    function calculateLPRequiredCollateral(address liquidityManager, address lp) external view returns (uint256) {
        
        IPoolLiquidityManager manager = IPoolLiquidityManager(liquidityManager);
        uint256 lpAssetValue = manager.getLPAssetHoldingValue(lp);

        return Math.mulDiv(lpAssetValue, lpHealthyCollateralRatio, BPS);
    }

    /**
     * @notice Check collateral health status of a user
     * @param user User address
     * @return health 3 = Healthy, 2 = Warning, 1 = Liquidatable
     */
    function getUserCollateralHealth(address assetPool, address user) external view returns (uint8 health) {
        IAssetPool pool = IAssetPool(assetPool);
        
        ( uint256 assetAmount,
          uint256 collateralAmount, 
          uint256 interestDebt
        ) = pool.userPosition(user);

        if (assetAmount == 0) {
            return 3; // Healthy - no asset balance means no risk
        }

        IAssetOracle oracle = IAssetOracle(pool.getAssetOracle());
        uint256 assetValue = assetAmount * oracle.assetPrice();

        uint256 healthyCollateral = Math.mulDiv(assetValue, userHealthyCollateralRatio, BPS);
        uint256 reqCollateral = Math.mulDiv(assetValue, userLiquidationThreshold, BPS);
        
        if (collateralAmount >= healthyCollateral + interestDebt) {
            return 3; // Healthy
        } else if (collateralAmount >= reqCollateral + interestDebt) {
            return 2; // Warning
        } else {
            return 1; // Liquidatable
        }
    }

    /**
     * @notice Check collateral health status of an LP
     * @param lp Address of the LP
     * @return health 3 = Healthy, 2 = Warning, 1 = Liquidatable
     */
    function getLPCollateralHealth(address liquidityManager, address lp) external view returns (uint8 health) {
        IPoolLiquidityManager manager = IPoolLiquidityManager(liquidityManager);
        
        uint256 lpAssetValue = manager.getLPAssetHoldingValue(lp);
        IPoolLiquidityManager.CollateralInfo memory lpInfo = manager.getLPInfo(lp);
        uint256 collateralAmount = lpInfo.collateralAmount;
        
        uint256 healthyCollateral = Math.mulDiv(lpAssetValue, lpHealthyCollateralRatio, BPS);
        uint256 reqCollateral = Math.mulDiv(lpAssetValue, lpWarningThreshold, BPS);
        
        if (collateralAmount >= healthyCollateral) {
            return 3; // Healthy
        } else if (collateralAmount >= reqCollateral) {
            return 2; // Warning
        } else {
            return 1; // Liquidatable
        }
    }
}