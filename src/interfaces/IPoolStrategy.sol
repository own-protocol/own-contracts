// SPDX-License-Identifier: GPL-3.0-or-later
// author: bhargavaparoksham

pragma solidity ^0.8.20;

/**
 * @title IPoolStrategy
 * @notice Interface for strategy contracts that manage pool economics
 * @dev Handles interest rates, collateral & liquidity requirements, fees, etc.
 */
interface IPoolStrategy {
    
    // --------------------------------------------------------------------------------
    //                                    EVENTS
    // --------------------------------------------------------------------------------
    

    /**
     * @notice Emitted when cycle parameters are updated
     */
    event CycleParamsUpdated(
        uint256 rebalancePeriod,
        uint256 oracleUpdateThreshold,
        uint256 poolHaltThreshold
    );

    /**
     * @notice Emitted when interest rate parameters are updated
     */
    event InterestRateParamsUpdated(
        uint256 baseRate,
        uint256 interestRate1,
        uint256 maxRate,
        uint256 utilTier1,
        uint256 utilTier2
    );
    
    /**
     * @notice Emitted when fee parameters are updated
     */
    event FeeParamsUpdated(
        uint256 protocolFee,
        address feeRecipient
    );
    
    /**
     * @notice Emitted when user collateral parameters are updated
     */
    event UserCollateralParamsUpdated(
        uint256 healthyRatio,
        uint256 liquidationRatio
    );
    
    /**
     * @notice Emitted when LP liquidity parameters are updated
     */
    event LPLiquidityParamsUpdated(
        uint256 healthyRatio,
        uint256 liquidationThreshold,
        uint256 liquidationReward
    );

    // --------------------------------------------------------------------------------
    //                             CONFIGURATION FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Sets the cycle parameters
     * @param rebalancePeriod Length of rebalancing period in seconds
     * @param oracleUpdateThreshold Threshold for Oracle update
     * @param haltThreshold Threshold for halting the pool
     */
    function setCycleParams(
        uint256 rebalancePeriod,
        uint256 oracleUpdateThreshold,
        uint256 haltThreshold
    ) external;
    
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
    ) external;
    
    /**
     * @notice Sets the fee parameters
     * @param protocolFee Protocol fee (scaled by 10000)
     * @param _feeRecipient Address to receive fees
     */
    function setProtocolFeeParams(
        uint256 protocolFee,
        address _feeRecipient
    ) external;
    
    /**
     * @notice Sets the user collateral parameters
     * @param healthyRatio Healthy collateral ratio (scaled by 10000)
     * @param liquidationRatio Liquidation threshold (scaled by 10000)
     */
    function setUserCollateralParams(
        uint256 healthyRatio,
        uint256 liquidationRatio
    ) external;
    
    /**
     * @notice Sets the LP liquidity parameters
     * @param healthyRatio Healthy liquidity ratio (scaled by 10000)
     * @param liquidationThreshold Liquidation threshold (scaled by 10000)
     * @param liquidationReward Liquidation reward (scaled by 10000)
     */
    function setLPLiquidityParams(
        uint256 healthyRatio,
        uint256 liquidationThreshold,
        uint256 liquidationReward
    ) external;

    // --------------------------------------------------------------------------------
    //                             CYCLE FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Returns the cycle parameters
     * @return rebalancePeriod Length of rebalancing period in seconds
     * @return oracleThreshold Threshold for Oracle update
     * @return poolHaltThreshold Threshold for halting the pool
     */
    function getCycleParams() external view returns (
        uint256 rebalancePeriod, 
        uint256 oracleThreshold,
        uint256 poolHaltThreshold
    );
    
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
     * @notice Returns Protocol fee percentage
     * @return protocolFee Fee percentage (scaled by 10000)
     */
    function getProtocolFee() external view returns (uint256 protocolFee);
    
    /**
     * @notice Returns the fee recipient address
     * @return recipient The fee recipient address
     */
    function getFeeRecipient() external view returns (address recipient);

    // --------------------------------------------------------------------------------
    //                             COLLATERAL & LIQUIDITY FUNCTIONS
    // --------------------------------------------------------------------------------
    
    /**
     * @notice Returns user collateral parameters
     * @return healthyRatio Healthy collateral ratio (scaled by 10000)
     * @return liquidationThreshold Liquidation threshold (scaled by 10000)
     */
    function getUserCollateralParams() external view returns (
        uint256 healthyRatio,
        uint256 liquidationThreshold
    );
    
    /**
     * @notice Returns LP liquidity parameters
     * @return healthyRatio Healthy liquidity ratio (scaled by 10000)
     * @return liquidationThreshold Liquidation threshold (scaled by 10000)
     * @return liquidationReward Liquidation reward percentage (scaled by 10000)
     */
    function getLPLiquidityParams() external view returns (
        uint256 healthyRatio,
        uint256 liquidationThreshold,
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
     * @notice Check liquidity health status of an LP
     * @param liquidityManager Address of the pool liquidity manager
     * @param lp LP address
     * @return health 3 = Healthy, 2 = Warning, 1 = Liquidatable
     */
    function getLPLiquidityHealth(address liquidityManager, address lp) external view returns (uint8 health);
}