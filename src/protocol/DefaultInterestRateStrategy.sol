// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;
import {IInterestRateStrategy} from "../interfaces/IInterestRateStrategy.sol";

/**
 * @title DefaultInterestRateStrategy
 * @notice Default implementation of interest rate strategy with a linear model
 * @dev Provides interest rates based on pool utilization with three tiers:
 *      1. Base rate when utilization <= 50%
 *      2. Linear increase from base to max rate when 50% < utilization <= 75%
 *      3. Constant max rate when 75% < utilization <= 95%
 */
contract DefaultInterestRateStrategy is IInterestRateStrategy {
    // --------------------------------------------------------------------------------
    //                               STATE VARIABLES
    // --------------------------------------------------------------------------------

    /**
     * @notice Base interest rate when utilization < 50% (scaled by 10000, default: 6%)
     */
    uint256 public baseInterestRate;

    /**
     * @notice Maximum interest rate at 75%+ utilization (scaled by 10000, default: 36%)
     */
    uint256 public maxInterestRate;

    /**
     * @notice First utilization tier breakpoint (default: 50%)
     */
    uint256 public utilizationTier1;

    /**
     * @notice Second utilization tier breakpoint (default: 75%)
     */
    uint256 public utilizationTier2;

    /**
     * @notice Maximum considered utilization (95%)
     */
    uint256 public maxUtilization;
    
    /**
     * @notice Basis points scaling factor
     */
    uint256 private constant BPS = 100_00;

    // --------------------------------------------------------------------------------
    //                                  ERRORS
    // --------------------------------------------------------------------------------

    error InvalidParameter();
    error AlreadyInitialized();
    error NotInitialized();

    /**
     * @dev Constructor that initializes the default interest rate strategy
     * @notice This constructor is called only once when deploying the implementation contract
     * @param _baseRate Base interest rate when utilization < 50% (scaled by 10000)
     * @param _maxRate Maximum interest rate at 75%+ utilization (scaled by 10000)
     * @param _utilTier1 First utilization tier breakpoint (scaled by 10000)
     * @param _utilTier2 Second utilization tier breakpoint (scaled by 10000)
     * @param _maxUtil Maximum considered utilization (scaled by 10000)
     */
    constructor(
        uint256 _baseRate,
        uint256 _maxRate,
        uint256 _utilTier1,
        uint256 _utilTier2,
        uint256 _maxUtil
    ) {
        if (_baseRate > _maxRate) revert InvalidParameter();
        if (_maxRate > BPS || maxUtilization > BPS) revert InvalidParameter();
        if (_utilTier2 <= _utilTier1 || _utilTier2 >= _maxUtil) revert InvalidParameter();
        
        baseInterestRate = _baseRate;
        maxInterestRate = _maxRate;
        utilizationTier1 = _utilTier1;
        utilizationTier2 = _utilTier2;
        maxUtilization = _maxUtil;
    }
    
    // --------------------------------------------------------------------------------
    //                            INTEREST CALCULATION
    // --------------------------------------------------------------------------------

    /**
     * @notice Calculate current interest rate based on pool utilization
     * @param utilization Current utilization rate of the pool (scaled by 10000)
     * @return rate Current interest rate (scaled by 10000)
     */
    function calculateInterestRate(uint256 utilization) external view returns (uint256 rate) {
        
        if (utilization <= utilizationTier1) {
            // Base rate when utilization <= 50%
            return baseInterestRate;
        } else if (utilization <= utilizationTier2) {
            // Linear increase from base rate to max rate
            uint256 utilizationDelta = utilization - utilizationTier1;
            uint256 optimalDelta = utilizationTier2 - utilizationTier1;
            
            uint256 additionalRate = ((maxInterestRate - baseInterestRate) * utilizationDelta) / optimalDelta;
            return baseInterestRate + additionalRate;
        } else {
            // Constant max rate when utilization > optimal
            return maxInterestRate;
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
     * @notice Returns the first utilization tier
     * @return First utilization tier (scaled by 10000)
     */
    function getUtilizationTier1() external view returns (uint256) {
        return utilizationTier1;
    }

    /**
     * @notice Returns the second utilization tier
     * @return Second utilization tier (scaled by 10000)
     */
    function getUtilizationTier2() external view returns (uint256) {
        return utilizationTier2;
    }

    /**
     * @notice Returns the maximum utilization point
     * @return Maximum utilization point (scaled by 10000)
     */
    function getMaxUtilization() external view returns (uint256) {
        return maxUtilization;
    }
}