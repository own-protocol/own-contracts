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
    //                             STRATEGY TYPE FUNCTIONS
    // --------------------------------------------------------------------------------
    
    /**
     * @notice Enum defining collateral calculation methods
     */
    enum CollateralMethod {
        VARIABLE_ASSET_BASED,   // Based on asset holdings (variable)
        FIXED_DEPOSIT_BASED     // Based on fixed percentage of deposit/liquidity
    }

    /**
     * @notice Returns the method used for calculating LP collateral
     * @return method The calculation method for LP collateral
     */
    function getLPCollateralMethod() external view returns (CollateralMethod);
    
    /**
     * @notice Returns the method used for calculating user collateral
     * @return method The calculation method for user collateral
     */
    function getUserCollateralMethod() external view returns (CollateralMethod);

    // --------------------------------------------------------------------------------
    //                             ASSET INTEREST FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Returns all interest rate parameters 
     * @return baseRate The base interest rate (scaled by 10000)
     * @return maxRate The maximum interest rate (scaled by 10000)
     * @return utilTier1 The first utilization tier (scaled by 10000)
     * @return utilTier2 The second utilization tier (scaled by 10000)
     * @return maxUtil The maximum utilization (scaled by 10000)
    */
    function getInterestRateParameters() external view returns (
        uint256 baseRate,
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
     * @return protocolFee Fee percentage taken by protocol from interest (scaled by 10000)
     */
    function getFeePercentages() external view returns (
        uint256 depositFee,
        uint256 redemptionFee,
        uint256 protocolFee
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