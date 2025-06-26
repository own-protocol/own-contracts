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
        uint256 liquidationReward,
        uint256 minCommitment
    );

    /**
     * @notice Emitted when the yield-generating reserve status is updated
     * @param isYieldBearing True if the reserve is yield-generating, false otherwise
     */
    event IsYieldBearingUpdated(
        bool isYieldBearing
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
     * @param _protocolFee Protocol fee (scaled by 10000)
     * @param _feeRecipient Address to receive fees
     */
    function setProtocolFeeParams(
        uint256 _protocolFee,
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
     * @param healthyRatio Healthy collateral ratio (scaled by 10000)
     * @param liquidationThreshold Liquidation threshold (scaled by 10000)
     * @param liquidationReward Liquidation reward (scaled by 10000)
     * @param minCommitment Minimum commitment amount for LPs
     */
    function setLPLiquidityParams(
        uint256 healthyRatio,
        uint256 liquidationThreshold,
        uint256 liquidationReward,
        uint256 minCommitment
    ) external;

    /**
     * @notice Sets the yield generating reserve flag
     */
    function setIsYieldBearing() external;

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
     * @return healthyRatio Healthy collateral ratio (scaled by 10000)
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

    // --------------------------------------------------------------------------------
    //                             YIELD FUNCTIONS
    // --------------------------------------------------------------------------------
    /**
     * @notice Returns the yield-bearing status of the reserve
     * @return True if the reserve is yield-bearing, false otherwise
     */
    function isYieldBearing() external view returns (bool);

    /**
     * @notice Calculates the reserve yield based on initial and current amounts
     * @param prevAmount Previous amount of tokens
     * @param currentAmount Current amount of tokens
     * @param depositAmount Amount of tokens deposited
     * @return yield The calculated yield (scaled by PRECISION)
     * @dev The yield is calculated as (currentAmount - initialAmount) / depositAmount
     * @dev The result is scaled by a precision factor (e.g., 1e18) to maintain accuracy
     */
    function calculateYieldAccrued(
        uint256 prevAmount, 
        uint256 currentAmount,
        uint256 depositAmount
    ) external pure returns (uint256 yield);

    // --------------------------------------------------------------------------------
    //                             POOL FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Calculate utilised liquidity (including cycle changes)
     * @param assetPool Address of the asset pool
     * @return cycleUtilisedLiquidity Total utilised liquidity
     */
    function calculateCycleUtilisedLiquidity(address assetPool) external view returns (uint256 cycleUtilisedLiquidity);

    /**
     * @notice Calculate current interest rate based on pool utilization
     * @return rate Current interest rate (scaled by 10000)
     */
    function calculatePoolInterestRate(address assetPool) external view returns (uint256 rate);

    /**
     * @notice Calculate interest rate based on pool utilization (including cycle changes)
     * @dev This function gives the expected interest rate for the next cycle
     * @dev It takes into account the new deposits, redemptions & liquidity changes in the cycle
     * @return rate interest rate (scaled by 10000)
     */
    function calculateCycleInterestRate(address assetPool) external view returns (uint256 rate);

    /**
     * @notice Calculate pool utilization ratio
     * @return utilization Pool utilization as a percentage (scaled by 10000)
     */
    function calculatePoolUtilizationRatio(address assetPool) external view returns (uint256 utilization);

    /**
     * @notice Calculate pool utilization ratio (including cycle changes)
     * @dev This function gives the expected utilization for the next cycle
     * @dev It takes into account the new deposits, redemptions & liquidity changes in the cycle
     * @return utilization Pool utilization as a percentage (scaled by 10000)
     */    
    function calculateCyclePoolUtilizationRatio(address assetPool) external view returns (uint256 utilization);

    /**
     * @notice Calculate available liquidity in the pool
     * @return availableLiquidity Available liquidity in reserve tokens
     */
    function calculateAvailableLiquidity(address assetPool) external view returns (uint256 availableLiquidity);

    /**
     * @notice Calculate available liquidity in the pool (including cycle changes)
     * @dev This function gives the expected available liquidity for the next cycle
     * @dev It takes into account the new deposits, redemptions & liquidity changes in the cycle
     * @return availableLiquidity Available liquidity in reserve tokens
     */
    function calculateCycleAvailableLiquidity(address assetPool) external view returns (uint256 availableLiquidity);


    // --------------------------------------------------------------------------------
    //                             VIEW FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Returns the rebalance length for onchain rebalancing period
     * @return The rebalance length in seconds
     */
    function rebalanceLength() external view returns (uint256);

    /**
     * @notice Returns the threshold for Oracle updates
     * @return The oracle update threshold in seconds
     */
    function oracleUpdateThreshold() external view returns (uint256);

    /**
     * @notice Returns the threshold for halting the pool
     * @return The halt threshold in seconds
     */
    function haltThreshold() external view returns (uint256);

    /**
     * @notice Returns the base interest rate
     * @return The base interest rate (scaled by 10000)
     */
    function baseInterestRate() external view returns (uint256);

    /**
     * @notice Returns the tier 1 interest rate
     * @return The tier 1 interest rate (scaled by 10000)
     */
    function interestRate1() external view returns (uint256);

    /**
     * @notice Returns the maximum interest rate
     * @return The maximum interest rate (scaled by 10000)
     */
    function maxInterestRate() external view returns (uint256);

    /**
     * @notice Returns the first utilization tier
     * @return The first utilization tier (scaled by 10000)
     */
    function utilizationTier1() external view returns (uint256);

    /**
     * @notice Returns the second utilization tier
     * @return The second utilization tier (scaled by 10000)
     */
    function utilizationTier2() external view returns (uint256);

    /**
     * @notice Returns the protocol fee percentage
     * @return The protocol fee (scaled by 10000)
     */
    function protocolFee() external view returns (uint256);

    /**
     * @notice Returns the address that receives fees
     * @return The fee recipient address
     */
    function feeRecipient() external view returns (address);

    /**
     * @notice Returns the healthy collateral ratio for users
     * @return The user healthy collateral ratio (scaled by 10000)
     */
    function userHealthyCollateralRatio() external view returns (uint256);

    /**
     * @notice Returns the user liquidation threshold
     * @return The liquidation threshold for users (scaled by 10000)
     */
    function userLiquidationThreshold() external view returns (uint256);

    /**
     * @notice Returns the healthy collateral ratio for LPs
     * @return The LP healthy collateral ratio (scaled by 10000)
     */
    function lpHealthyCollateralRatio() external view returns (uint256);

    /**
     * @notice Returns the LP liquidation threshold
     * @return The liquidation threshold for LPs (scaled by 10000)
     */
    function lpLiquidationThreshold() external view returns (uint256);

    /**
     * @notice Returns the LP liquidation reward percentage
     * @return The liquidation reward for LPs (scaled by 10000)
     */
    function lpLiquidationReward() external view returns (uint256);

    /**
     * @notice Returns the minimum commitment amount for LPs
     * @return The minimum commitment amount for LPs
     */
    function lpMinCommitment() external view returns (uint256);
}