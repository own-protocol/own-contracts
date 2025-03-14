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
    uint256 public baseInterestRate;      // Base interest rate (e.g., 6%)
    uint256 public maxInterestRate;       // Maximum interest rate (e.g., 36%)
    uint256 public utilizationTier1;      // First utilization tier (e.g., 50%)
    uint256 public utilizationTier2;      // Second utilization tier (e.g., 75%)
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
    
    // Reserve interest distribution
    uint256 public userInterestProtocolShare;     // Protocol share of user reserve interest
    uint256 public userInterestLPShare;           // LP share of user reserve interest
    uint256 public lpInterestProtocolShare;       // Protocol share of LP reserve interest
    uint256 public lpInterestLPShare;             // LP self-share of LP reserve interest
    
    // Configuration flags
    bool public isAToken;                 // Whether reserve token is an aToken
    address public underlyingToken;       // Underlying token for aToken (if applicable)
    
    // Constants
    uint256 private constant BPS = 100_00;  // 100% in basis points (10000)
    
    // --------------------------------------------------------------------------------
    //                                  CONSTRUCTOR
    // --------------------------------------------------------------------------------

    constructor(
        // Asset interest parameters
        uint256 _baseRate,
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
        uint256 _lpLiquidationReward,
        
        // Reserve interest parameters
        bool _isAToken,
        address _underlyingToken,
        uint256 _userInterestProtocolShare,
        uint256 _userInterestLPShare,
        uint256 _lpInterestProtocolShare,
        uint256 _lpInterestLPShare
    ) {
        // Parameter validation
        require(_baseRate <= _maxRate, "Base rate must be <= max rate");
        require(_maxRate <= BPS, "Max rate cannot exceed 100%");
        require(_utilTier1 < _utilTier2, "Tier1 must be < Tier2");
        require(_utilTier2 < _maxUtil, "Tier2 must be < max utilization");
        require(_userLiquidationRatio < _userHealthyRatio, "User liquidation ratio must be < healthy ratio");
        require(_lpWarningThreshold < _lpHealthyRatio, "LP warning threshold must be < healthy ratio");
        require(_lpRegistrationRatio <= _lpWarningThreshold, "LP registration ratio must be <= warning threshold");
        require(_depositFee <= BPS && _redemptionFee <= BPS && _protocolFee <= BPS, "Fees cannot exceed 100%");
        require(_feeRecipient != address(0), "Invalid fee recipient");
        
        if (_isAToken) {
            require(_underlyingToken != address(0), "Invalid underlying token");
            require(_userInterestProtocolShare + _userInterestLPShare == BPS, "User interest shares must sum to 100%");
            require(_lpInterestProtocolShare + _lpInterestLPShare == BPS, "LP interest shares must sum to 100%");
        }
        
        // Asset interest parameters
        baseInterestRate = _baseRate;
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
        
        // Reserve interest parameters
        isAToken = _isAToken;
        underlyingToken = _underlyingToken;
        userInterestProtocolShare = _userInterestProtocolShare;
        userInterestLPShare = _userInterestLPShare;
        lpInterestProtocolShare = _lpInterestProtocolShare;
        lpInterestLPShare = _lpInterestLPShare;
    }
    
    // --------------------------------------------------------------------------------
    //                             STRATEGY TYPE FUNCTIONS
    // --------------------------------------------------------------------------------
    
    /**
     * @notice Returns the method used for calculating LP collateral
     * @return method Variable asset-based for LP collateral
     */
    function getLPCollateralMethod() external pure returns (CollateralMethod) {
        return CollateralMethod.VARIABLE_ASSET_BASED;
    }
    
    /**
     * @notice Returns the method used for calculating user collateral
     * @return method Fixed deposit-based for user collateral
     */
    function getUserCollateralMethod() external pure returns (CollateralMethod) {
        return CollateralMethod.FIXED_DEPOSIT_BASED;
    }
    
    /**
     * @notice Returns whether aToken (yield-bearing) is being used
     * @return isAToken True if aToken is used as reserve token
     */
    function isATokenReserve() external view returns (bool) {
        return isAToken;
    }
    
    /**
     * @notice Returns whether profit sharing is enabled
     * @return isEnabled Always false for this strategy
     */
    function isProfitSharingEnabled() external pure returns (bool) {
        return false;
    }
    
    // --------------------------------------------------------------------------------
    //                             ASSET INTEREST FUNCTIONS
    // --------------------------------------------------------------------------------

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
            
            uint256 additionalRate = ((maxInterestRate - baseInterestRate) * utilizationDelta) / optimalDelta;
            return baseInterestRate + additionalRate;
        } else {
            // Constant max rate when utilization > Tier2
            return maxInterestRate;
        }
    }

    /**
     * @notice Returns the maximum utilization point
     * @return Maximum utilization point (scaled by 10000)
     */
    function getMaxUtilization() external view returns (uint256) {
        return maxUtilization;
    }
    
    // --------------------------------------------------------------------------------
    //                             RESERVE INTEREST FUNCTIONS
    // --------------------------------------------------------------------------------
    
    /**
     * @notice Returns the underlying token for aToken if applicable
     * @return underlyingToken The address of the underlying token
     */
    function getUnderlyingToken() external view returns (address) {
        return underlyingToken;
    }
    
    /**
     * @notice Calculates accrued interest from reserve tokens (aTokens)
     * @param currentBalance Current aToken balance
     * @param lastBalance Previous balance for comparison
     * @return interestAmount Amount of interest accrued
     */
    function calculateReserveInterest(
        uint256 currentBalance,
        uint256 lastBalance
    ) external pure returns (uint256) {
        return currentBalance > lastBalance ? currentBalance - lastBalance : 0;
    }
    
    /**
     * @notice Determines how reserve interest is distributed
     * @param interestAmount Total interest amount
     * @param isUserFunds Whether interest is from user funds or LP collateral
     * @return protocolAmount Amount for protocol
     * @return lpAmount Amount for LPs
     */
    function distributeReserveInterest(
        uint256 interestAmount,
        bool isUserFunds
    ) external view override returns (uint256 protocolAmount, uint256 lpAmount) {
        if (isUserFunds) {
            protocolAmount = interestAmount * userInterestProtocolShare / BPS;
            lpAmount = interestAmount * userInterestLPShare / BPS;
        } else {
            protocolAmount = interestAmount * lpInterestProtocolShare / BPS;
            lpAmount = interestAmount * lpInterestLPShare / BPS;
        }
        return (protocolAmount, lpAmount);
    }
    
    // --------------------------------------------------------------------------------
    //                             PROFIT SHARING FUNCTIONS
    // --------------------------------------------------------------------------------
    
    /**
     * @notice Calculates profit share distribution for an LP
     * @dev Always returns 0 for keepAmount since profit sharing is disabled
     */
    function calculateProfitShare(
        int256 rebalanceAmount,
        uint256 lpLiquidity,
        uint256 totalLPLiquidity
    ) external pure returns (uint256 keepAmount, uint256 poolAmount) {
        // No profit sharing in default strategy
        if (rebalanceAmount <= 0) {
            // Handle loss case
            poolAmount = uint256(-rebalanceAmount) * lpLiquidity / totalLPLiquidity;
            return (0, poolAmount);
        } else {
            // Handle profit case - LP contributes full amount to pool
            poolAmount = uint256(rebalanceAmount) * lpLiquidity / totalLPLiquidity;
            return (0, poolAmount);
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
     * @notice Calculates required user collateral (fixed based on deposit)
     * @param assetPool Address of the asset pool
     * @param user Address of the user
     */
    function calculateUserRequiredCollateral(address assetPool, address user) external view returns (uint256) {

        IAssetPool pool = IAssetPool(assetPool);
        IXToken assetToken = IXToken(pool.getAssetToken());
        
        uint256 userReserveBalance = assetToken.reserveBalanceOf(user);
        uint256 interestDebt = pool.getInterestDebt(user);
        uint256 baseCollateral = Math.mulDiv(userReserveBalance, userHealthyCollateralRatio, BPS);
        return baseCollateral + interestDebt;
    }
    
    /**
     * @notice Calculates required LP collateral (variable based on asset holdings)
     * @param liquidityManager Address of the pool liquidity manager
     * @param lp Address of the LP
     */
    function calculateLPRequiredCollateral(address liquidityManager, address lp) external view returns (uint256) {
        
        IPoolLiquidityManager manager = IPoolLiquidityManager(liquidityManager);
        uint256 lpAssetValue = manager.getLPAssetHolding(lp);
        uint256 decimalFactor = manager.getReserveToAssetDecimalFactor();

        //ToDo: Need to consider expectedNewAssetMints when calculating required collateral

        return Math.mulDiv(lpAssetValue, lpHealthyCollateralRatio, BPS * decimalFactor);
    }

    /**
     * @notice Check collateral health status of a user
     * @param user User address
     * @return health 3 = Healthy, 2 = Warning, 1 = Liquidatable
     */
    function getUserCollateralHealth(address assetPool, address user) external view returns (uint8 health) {
        IAssetPool pool = IAssetPool(assetPool);
        
        ( uint256 assetAmount, 
          uint256 reserveAmount, 
          uint256 collateralAmount, 
          uint256 interestDebt
        ) = pool.userPosition(user);

        if (assetAmount == 0) {
            return 3; // Healthy - no asset balance means no risk
        }

        uint256 healthyCollateral = Math.mulDiv(reserveAmount, userHealthyCollateralRatio, BPS);
        uint256 reqCollateral = Math.mulDiv(reserveAmount, userLiquidationThreshold, BPS);
        
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