// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "../../interfaces/IPoolStrategy.sol";
import "../../interfaces/IPoolLiquidityManager.sol";
import "../../interfaces/IAssetPool.sol";
import "../../interfaces/IXToken.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

/**
 * @title DefaultPoolStrategy
 * @notice Default implementation of pool strategy with standard interest and collateral models
 * @dev Uses variable LP collateral based on asset holdings and fixed user collateral based on deposits
 */
contract DefaultPoolStrategy is IPoolStrategy {
    // --------------------------------------------------------------------------------
    //                               STATE VARIABLES
    // --------------------------------------------------------------------------------
    
    // Asset interest rate parameters
    uint256 public baseInterestRate;      // Base interest rate (e.g., 9%)
    uint256 public interestRate1;       // Maximum interest rate (e.g., 18%)
    uint256 public maxInterestRate;       // Maximum interest rate (e.g., 72%)
    uint256 public utilizationTier1;      // First utilization tier (e.g., 50%)
    uint256 public utilizationTier2;      // Second utilization tier (e.g., 85%)
    uint256 public maxUtilization;        // Maximum utilization (e.g., 95%)
    
    // Fee parameters
    uint256 public depositFeePercentage;  // Fee for deposits (e.g., 0.5%)
    uint256 public redemptionFeePercentage; // Fee for redemptions (e.g., 0.5%)
    uint256 public protocolFeePercentage; // Protocol fee on interest (e.g., 20%)
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

    constructor(
        // Asset interest parameters
        uint256 _baseRate,
        uint256 _interestRate1,
        uint256 _maxRate,
        uint256 _utilTier1,
        uint256 _utilTier2,
        uint256 _maxUtil,
        
        // Fee parameters
        uint256 _depositFee,
        uint256 _redemptionFee,
        uint256 _protocolFee,
        address _feeRecipient,
        
        // User collateral parameters
        uint256 _userHealthyRatio,
        uint256 _userLiquidationRatio,
        uint256 _userLiquidationReward,
        
        // LP collateral parameters
        uint256 _lpHealthyRatio,
        uint256 _lpWarningThreshold,
        uint256 _lpRegistrationRatio,
        uint256 _lpLiquidationReward
    ) {
        // Parameter validation
        require(_baseRate <= _interestRate1, "Base rate must be <= Interest rate 1");
        require(_interestRate1 <= _maxRate, "Interest rate 1 must be <= max rate");
        require(_maxRate <= BPS, "Max rate cannot exceed 100%");
        require(_utilTier1 < _utilTier2, "Tier1 must be < Tier2");
        require(_utilTier2 < _maxUtil, "Tier2 must be < max utilization");
        require(_userLiquidationRatio < _userHealthyRatio, "User liquidation ratio must be < healthy ratio");
        require(_lpWarningThreshold < _lpHealthyRatio, "LP warning threshold must be < healthy ratio");
        require(_lpRegistrationRatio <= _lpWarningThreshold, "LP registration ratio must be <= warning threshold");
        require(_depositFee <= BPS && _redemptionFee <= BPS && _protocolFee <= BPS, "Fees cannot exceed 100%");
        require(_feeRecipient != address(0), "Invalid fee recipient");
        
        // Asset interest parameters
        baseInterestRate = _baseRate;
        interestRate1 = _interestRate1;
        maxInterestRate = _maxRate;
        utilizationTier1 = _utilTier1;
        utilizationTier2 = _utilTier2;
        maxUtilization = _maxUtil;
        
        // Fee parameters
        depositFeePercentage = _depositFee;
        redemptionFeePercentage = _redemptionFee;
        protocolFeePercentage = _protocolFee;
        feeRecipient = _feeRecipient;
        
        // User collateral parameters
        userHealthyCollateralRatio = _userHealthyRatio;
        userLiquidationThreshold = _userLiquidationRatio;
        userLiquidationReward = _userLiquidationReward;
        
        // LP collateral parameters
        lpHealthyCollateralRatio = _lpHealthyRatio;
        lpWarningThreshold = _lpWarningThreshold;
        lpRegistrationRatio = _lpRegistrationRatio;
        lpLiquidationReward = _lpLiquidationReward;
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
    function getInterestRateParameters() external view returns (
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
            // Linear increase from base rate to max rate
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
        uint256 protocolFee
    ) {
        return (depositFeePercentage, redemptionFeePercentage, protocolFeePercentage);
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
        (uint256 assetAmount, , , uint256 interestDebt) = pool.userPosition(user);

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
        uint256 lpAssetValue = manager.getLPAssetHolding(lp);

        return Math.mulDiv(lpAssetValue, lpHealthyCollateralRatio, BPS);
    }

    /**
     * @notice Check collateral health status of a user
     * @param user User address
     * @return health 3 = Healthy, 2 = Warning, 1 = Liquidatable
     */
    function getUserCollateralHealth(address assetPool, address user) external view returns (uint8 health) {
        IAssetPool pool = IAssetPool(assetPool);
        
        ( uint256 assetAmount, , 
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
        
        uint256 lpAssetValue = manager.getLPAssetHolding(lp);
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