// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IInterestRateStrategy} from "../interfaces/IInterestRateStrategy.sol";

/**
 * @title DefaultInterestRateStrategy
 * @notice Default implementation of interest rate strategy with a kinked model
 * @dev Provides interest rates based on pool utilization with three tiers:
 *      1. Base rate when utilization <= 50%
 *      2. Linear increase from base to optimal rate when 50% < utilization <= optimal
 *      3. Exponential increase from optimal to max when optimal < utilization <= 90%
 */
contract DefaultInterestRateStrategy is IInterestRateStrategy, Ownable {
    // --------------------------------------------------------------------------------
    //                               STATE VARIABLES
    // --------------------------------------------------------------------------------

    /**
     * @notice Base interest rate when utilization < 50% (scaled by 10000, default: 6%)
     */
    uint256 public baseInterestRate = 6_00;

    /**
     * @notice Maximum interest rate at 90% utilization (scaled by 10000, default: 36%)
     */
    uint256 public maxInterestRate = 36_00;

    /**
     * @notice Optimal utilization point (scaled by 10000, default: 80%)
     */
    uint256 public optimalUtilization = 80_00;
    
    /**
     * @notice Basis points scaling factor
     */
    uint256 private constant BPS = 100_00;
    
    /**
     * @notice First utilization tier breakpoint (50%)
     */
    uint256 private constant UTILIZATION_TIER_1 = 50_00;
    
    /**
     * @notice Maximum considered utilization (90%)
     */
    uint256 private constant MAX_UTILIZATION = 90_00;

    // --------------------------------------------------------------------------------
    //                                  ERRORS
    // --------------------------------------------------------------------------------

    error InvalidParameter();

    /**
     * @dev Constructor that sets the owner
     * @param _owner Address of the owner
     */
    constructor(address _owner) Ownable(_owner) {}
    
    // --------------------------------------------------------------------------------
    //                            INTEREST CALCULATION
    // --------------------------------------------------------------------------------

    /**
     * @notice Calculate current interest rate based on pool utilization
     * @param utilization Current utilization rate of the pool (scaled by 10000)
     * @return rate Current interest rate (scaled by 10000)
     */
    function calculateInterestRate(uint256 utilization) external view returns (uint256 rate) {
        if (utilization <= UTILIZATION_TIER_1) {
            // Base rate when utilization <= 50%
            return baseInterestRate;
        } else if (utilization <= optimalUtilization) {
            // Linear increase from base rate to optimal rate
            uint256 utilizationDelta = utilization - UTILIZATION_TIER_1;
            uint256 optimalDelta = optimalUtilization - UTILIZATION_TIER_1;
            uint256 optimalRate = (maxInterestRate * 2) / 3; // 2/3 of max rate at optimal utilization
            
            uint256 additionalRate = ((optimalRate - baseInterestRate) * utilizationDelta) / optimalDelta;
            return baseInterestRate + additionalRate;
        } else {
            // Exponential increase from optimal to max utilization
            uint256 utilizationDelta = utilization - optimalUtilization;
            uint256 maxDelta = MAX_UTILIZATION - optimalUtilization;
            uint256 optimalRate = (maxInterestRate * 2) / 3;
            
            uint256 additionalRate = ((maxInterestRate - optimalRate) * utilizationDelta * utilizationDelta) 
                                    / (maxDelta * maxDelta);
            return optimalRate + additionalRate;
        }
    }
    
    // --------------------------------------------------------------------------------
    //                              GETTER FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Returns the base interest rate
     * @return Base interest rate (scaled by 10000)
     */
    function getBaseInterestRate() external view returns (uint256) {
        return baseInterestRate;
    }
    
    /**
     * @notice Returns the maximum interest rate
     * @return Maximum interest rate (scaled by 10000)
     */
    function getMaxInterestRate() external view returns (uint256) {
        return maxInterestRate;
    }
    
    /**
     * @notice Returns the optimal utilization point
     * @return Optimal utilization point (scaled by 10000)
     */
    function getOptimalUtilization() external view returns (uint256) {
        return optimalUtilization;
    }
    
    // --------------------------------------------------------------------------------
    //                              SETTER FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Updates the base interest rate
     * @param newBaseRate New base interest rate (scaled by 10000)
     */
    function setBaseInterestRate(uint256 newBaseRate) external onlyOwner {
        if (newBaseRate > maxInterestRate) revert InvalidParameter();
        
        baseInterestRate = newBaseRate;
    }
    
    /**
     * @notice Updates the maximum interest rate
     * @param newMaxRate New maximum interest rate (scaled by 10000)
     */
    function setMaxInterestRate(uint256 newMaxRate) external onlyOwner {
        if (newMaxRate < baseInterestRate) revert InvalidParameter();
        if (newMaxRate > BPS) revert InvalidParameter();
        
        maxInterestRate = newMaxRate;
    }
    
    /**
     * @notice Updates the optimal utilization point
     * @param newOptimalUtilization New optimal utilization point (scaled by 10000)
     */
    function setOptimalUtilization(uint256 newOptimalUtilization) external onlyOwner {
        if (newOptimalUtilization <= UTILIZATION_TIER_1 || newOptimalUtilization >= MAX_UTILIZATION) {
            revert InvalidParameter();
        }
        
        optimalUtilization = newOptimalUtilization;
    }
}