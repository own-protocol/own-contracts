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
     * @notice Returns the maximum utilization point
     * @return Maximum utilization point (scaled by 10000)
     */
    function getMaxUtilization() external view returns (uint256);
    
}