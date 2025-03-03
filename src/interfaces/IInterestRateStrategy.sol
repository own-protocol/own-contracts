// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

/**
 * @title IInterestRateStrategy
 * @notice Interface for interest rate strategy contracts
 * @dev This interface allows for different interest rate calculation strategies to be swapped
 */
interface IInterestRateStrategy {
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
     * @notice Returns the optimal utilization point
     * @return Optimal utilization point (scaled by 10000)
     */
    function getOptimalUtilization() external view returns (uint256);
    
    /**
     * @notice Updates the base interest rate
     * @param newBaseRate New base interest rate (scaled by 10000)
     */
    function setBaseInterestRate(uint256 newBaseRate) external;
    
    /**
     * @notice Updates the maximum interest rate
     * @param newMaxRate New maximum interest rate (scaled by 10000)
     */
    function setMaxInterestRate(uint256 newMaxRate) external;
    
    /**
     * @notice Updates the optimal utilization point
     * @param newOptimalUtilization New optimal utilization point (scaled by 10000)
     */
    function setOptimalUtilization(uint256 newOptimalUtilization) external;
}