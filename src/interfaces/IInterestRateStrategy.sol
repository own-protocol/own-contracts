// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

/**
 * @title IInterestRateStrategy
 * @notice Interface for interest rate strategy contracts
 * @dev This interface allows for different interest rate calculation strategies to be swapped
 */
interface IInterestRateStrategy {

    // --------------------------------------------------------------------------------
    //                                  ERRORS
    // --------------------------------------------------------------------------------

    error InvalidParameter();
    error AlreadyInitialized();
    error NotInitialized();

    /**
     * @notice Returns the current interest rate based on utilization
     * @param utilization Current utilization rate of the pool (scaled by 10000)
     * @return rate Current interest rate (scaled by 10000)
     */
    function calculateInterestRate(uint256 utilization) external view returns (uint256 rate);
    
    /**
     * @notice Returns the base interest rate of the strategy
     * @return Base interest rate (scaled by 10000)
     */
    function getBaseInterestRate() external view returns (uint256);
    
    /**
     * @notice Returns the maximum interest rate of the strategy
     * @return Maximum interest rate (scaled by 10000)
     */
    function getMaxInterestRate() external view returns (uint256);
    
    /**
     * @notice Returns the first utilization tier
     * @return First utilization tier (scaled by 10000)
     */
    function getUtilizationTier1() external view returns (uint256);

    /**
     * @notice Returns the second utilization tier
     * @return Second utilization tier (scaled by 10000)
     */
    function getUtilizationTier2() external view returns (uint256);

    /**
     * @notice Returns the maximum utilization point
     * @return Maximum utilization point (scaled by 10000)
     */
    function getMaxUtilization() external view returns (uint256);
    
    /**
     * @notice Initializes the strategy with parameters
     * @param _baseRate Base interest rate (scaled by 10000)
     * @param _maxRate Maximum interest rate (scaled by 10000) 
     * @param _optimalUtil Optimal utilization point (scaled by 10000)
     * @param _maxUtil Maximum utilization point (scaled by 10000)
     * @param _owner Address of the owner
     */
    function initialize(
        uint256 _baseRate,
        uint256 _maxRate,
        uint256 _optimalUtil,
        uint256 _maxUtil,
        address _owner
    ) external;
}