// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/protocol/DefaultInterestRateStrategy.sol";
import "../src/interfaces/IInterestRateStrategy.sol";

contract DefaultInterestRateStrategyTest is Test {
    DefaultInterestRateStrategy public strategy;
    
    // Test constants
    uint256 constant BASE_RATE = 6_00;       // 6%
    uint256 constant MAX_RATE = 36_00;       // 36%
    uint256 constant UTIL_TIER1 = 50_00;     // 50%
    uint256 constant UTIL_TIER2 = 75_00;     // 75%
    uint256 constant MAX_UTIL = 95_00;       // 95%
    uint256 constant BPS = 100_00;           // 100% in basis points

    function setUp() public {
        // Deploy interest rate strategy with default parameters
        strategy = new DefaultInterestRateStrategy(
            BASE_RATE,
            MAX_RATE,
            UTIL_TIER1,
            UTIL_TIER2,
            MAX_UTIL
        );
    }
    
    // --------------------------------------------------------------------------------
    //                         CONSTRUCTOR VALIDATION TESTS
    // --------------------------------------------------------------------------------
    
    function testConstructorInvalidBaseRate() public {
        // Base rate can't be higher than max rate
        vm.expectRevert(DefaultInterestRateStrategy.InvalidParameter.selector);
        new DefaultInterestRateStrategy(
            50_00,   // Base rate higher than max rate
            36_00,
            UTIL_TIER1,
            UTIL_TIER2,
            MAX_UTIL
        );
    }
    
    function testConstructorInvalidMaxRate() public {
        // Max rate can't exceed 100%
        vm.expectRevert(DefaultInterestRateStrategy.InvalidParameter.selector);
        new DefaultInterestRateStrategy(
            BASE_RATE,
            101_00,  // Over 100%
            UTIL_TIER1,
            UTIL_TIER2,
            MAX_UTIL
        );
    }
    
    function testConstructorInvalidTiers() public {
        // Tier2 can't be less than or equal to Tier1
        vm.expectRevert(DefaultInterestRateStrategy.InvalidParameter.selector);
        new DefaultInterestRateStrategy(
            BASE_RATE,
            MAX_RATE,
            50_00,
            50_00,   // Equal to Tier1
            MAX_UTIL
        );
        
        // Tier2 can't be greater than or equal to Max Utilization
        vm.expectRevert(DefaultInterestRateStrategy.InvalidParameter.selector);
        new DefaultInterestRateStrategy(
            BASE_RATE,
            MAX_RATE,
            50_00,
            96_00,   // Greater than MaxUtil
            95_00
        );
    }
    
    // --------------------------------------------------------------------------------
    //                         INTEREST RATE CALCULATION TESTS
    // --------------------------------------------------------------------------------
    
    function testRateAtZeroUtilization() public view {
        uint256 rate = strategy.calculateInterestRate(0);
        assertEq(rate, BASE_RATE, "Rate should be base rate at 0% utilization");
    }
    
    function testRateAtTier1Utilization() public view {
        uint256 rate = strategy.calculateInterestRate(UTIL_TIER1);
        assertEq(rate, BASE_RATE, "Rate should be base rate at Tier1 utilization");
    }
    
    function testRateAtTier2Utilization() public view {
        uint256 rate = strategy.calculateInterestRate(UTIL_TIER2);
        assertEq(rate, MAX_RATE, "Rate should be max rate at Tier2 utilization");
    }
    
    function testRateAboveTier2Utilization() public view {
        uint256 rate = strategy.calculateInterestRate(80_00); // 80%
        assertEq(rate, MAX_RATE, "Rate should be max rate above Tier2 utilization");
    }
    
    function testRateBetweenTiers() public view {
        // At 62.5% utilization (halfway between 50% and 75%)
        uint256 midPoint = (UTIL_TIER1 + UTIL_TIER2) / 2;
        uint256 rate = strategy.calculateInterestRate(midPoint);
        
        // Should be halfway between BASE_RATE and MAX_RATE
        uint256 expectedRate = BASE_RATE + (MAX_RATE - BASE_RATE) / 2;
        assertEq(rate, expectedRate, "Rate should be halfway between base and max");
    }
    
    function testLinearRateIncrease() public view {
        // Test several points between Tier1 and Tier2
        uint256 step = (UTIL_TIER2 - UTIL_TIER1) / 5;
        
        for (uint256 i = 1; i <= 4; i++) {
            uint256 utilization = UTIL_TIER1 + step * i;
            uint256 rate = strategy.calculateInterestRate(utilization);
            
            // Calculate expected rate with linear interpolation
            uint256 utilizationDelta = utilization - UTIL_TIER1;
            uint256 optimalDelta = UTIL_TIER2 - UTIL_TIER1;
            uint256 expectedRate = BASE_RATE + ((MAX_RATE - BASE_RATE) * utilizationDelta) / optimalDelta;
            
            assertEq(rate, expectedRate, "Rate should follow linear increase");
        }
    }
    
    // --------------------------------------------------------------------------------
    //                                GETTER TESTS
    // --------------------------------------------------------------------------------
    
    function testGetters() public view {
        assertEq(strategy.getBaseInterestRate(), BASE_RATE);
        assertEq(strategy.getMaxInterestRate(), MAX_RATE);
        assertEq(strategy.getUtilizationTier1(), UTIL_TIER1);
        assertEq(strategy.getUtilizationTier2(), UTIL_TIER2);
        assertEq(strategy.getMaxUtilization(), MAX_UTIL);
    }
}