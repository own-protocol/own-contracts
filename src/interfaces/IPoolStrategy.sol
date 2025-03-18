// SPDX-License-Identifier: GPL-3.0-or-later
// author: bhargavaparoksham

pragma solidity ^0.8.20;

/**
 * @title IPoolStrategy
 * @notice Interface for strategy contracts that manage pool economics
 * @dev Handles interest rates, collateral requirements, fees, etc.
 */
interface IPoolStrategy {
    
    // --------------------------------------------------------------------------------
    //                                    EVENTS
    // --------------------------------------------------------------------------------
    
    /**
     * @notice Emitted when interest rate parameters are updated
     */
    event InterestRateParamsUpdated(
        uint256 baseRate,
        uint256 interestRate1,
        uint256 maxRate,
        uint256 utilTier1,
        uint256 utilTier2,
        uint256 maxUtil
    );
    
    /**
     * @notice Emitted when fee parameters are updated
     */
    event FeeParamsUpdated(
        uint256 depositFee,
        uint256 redemptionFee,
        uint256 interestFee,
        uint256 yieldFee,
        address feeRecipient
    );
    
    /**
     * @notice Emitted when user collateral parameters are updated
     */
    event UserCollateralParamsUpdated(
        uint256 healthyRatio,
        uint256 liquidationRatio,
        uint256 liquidationReward
    );
    
    /**
     * @notice Emitted when LP collateral parameters are updated
     */
    event LPCollateralParamsUpdated(
        uint256 healthyRatio,
        uint256 warningThreshold,
        uint256 registrationRatio,
        uint256 liquidationReward
    );

    // --------------------------------------------------------------------------------
    //                             CONFIGURATION FUNCTIONS
    // --------------------------------------------------------------------------------
    
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
    ) external;
    
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
    ) external;
    
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
    ) external;
    
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
    ) external;
    
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
    );

    /**
     * @notice Returns the current interest rate based on utilization
     * @param utilization Current utilization rate of the pool (scaled by 10000)
     * @return rate Current interest rate (scaled by 10000)
     */
    function calculateInterestRate(uint256 utilization) external view returns (uint256 rate);
    
    // --------------------------------------------------------------------------------
    //                             FEE FUNCTIONS
    // --------------------------------------------------------------------------------
    
    /**
     * @notice Returns fee percentages for different operations
     * @return depositFee Fee percentage for deposits (scaled by 10000)
     * @return redemptionFee Fee percentage for redemptions (scaled by 10000)
     * @return interestFee Fee percentage taken by protocol from interest (scaled by 10000)
     * @return yieldFee Fee percentage taken by protocol from yield generated on reserve tokens (scaled by 10000)
     */
    function getFeePercentages() external view returns (
        uint256 depositFee,
        uint256 redemptionFee,
        uint256 interestFee,
        uint256 yieldFee
    );
    
    /**
     * @notice Returns the fee recipient address
     * @return recipient The fee recipient address
     */
    function getFeeRecipient() external view returns (address recipient);

    // --------------------------------------------------------------------------------
    //                             COLLATERAL FUNCTIONS
    // --------------------------------------------------------------------------------
    
    /**
     * @notice Returns user collateral parameters
     * @return healthyRatio Healthy collateral ratio (scaled by 10000)
     * @return liquidationThreshold Liquidation threshold (scaled by 10000)
     * @return liquidationReward Liquidation reward percentage (scaled by 10000)
     */
    function getUserCollateralParams() external view returns (
        uint256 healthyRatio,
        uint256 liquidationThreshold,
        uint256 liquidationReward
    );
    
    /**
     * @notice Returns LP collateral parameters
     * @return healthyRatio Healthy collateral ratio (scaled by 10000)
     * @return warningThreshold Warning threshold (scaled by 10000)
     * @return registrationRatio Registration minimum ratio (scaled by 10000)
     * @return liquidationReward Liquidation reward percentage (scaled by 10000)
     */
    function getLPCollateralParams() external view returns (
        uint256 healthyRatio,
        uint256 warningThreshold,
        uint256 registrationRatio,
        uint256 liquidationReward
    );
    
    /**
     * @notice Calculates required user collateral
     * @param assetPool Address of the asset pool
     * @param user Address of the user
     * @return requiredCollateral Required collateral amount
     */
    function calculateUserRequiredCollateral(
        address assetPool,
        address user
    ) external view returns (uint256 requiredCollateral);
    
    /**
     * @notice Calculates required LP collateral
     * @param liquidityManager Address of the LP Registry contract
     * @param lp Address of the LP
     */
    function calculateLPRequiredCollateral(
        address liquidityManager, 
        address lp
    ) external view returns (uint256 requiredCollateral);

    /**
     * @notice Check collateral health status of a user
     * @param assetPool Address of the asset pool
     * @param user User address
     * @return health 3 = Healthy, 2 = Warning, 1 = Liquidatable
     */
    function getUserCollateralHealth(address assetPool, address user) external view returns (uint8 health);

    /**
     * @notice Check collateral health status of an LP
     * @param liquidityManager Address of the pool liquidity manager
     * @param lp LP address
     * @return health 3 = Healthy, 2 = Warning, 1 = Liquidatable
     */
    function getLPCollateralHealth(address liquidityManager, address lp) external view returns (uint8 health);
}