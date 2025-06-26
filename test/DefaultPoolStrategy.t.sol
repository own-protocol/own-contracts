// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/protocol/strategies/DefaultPoolStrategy.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockAssetOracle.sol";

contract DefaultPoolStrategyTest is Test {
    DefaultPoolStrategy public strategy;
    address public owner;
    address public feeRecipient;
    
    // Sample addresses for testing
    address public user1;
    address public user2;
    address public lp1;
    
    // Test constants
    uint256 public constant BPS = 100_00; // 100% in basis points
    
    function setUp() public {
        // Set up test accounts
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        lp1 = makeAddr("lp1");
        feeRecipient = makeAddr("feeRecipient");
        
        // Deploy the DefaultPoolStrategy
        strategy = new DefaultPoolStrategy();
        
        // Initialize strategy with default test parameters
        _initializeStrategy();
    }
    
    function _initializeStrategy() internal {
        // Set cycle parameters
        strategy.setCycleParams(
            1 days,        // Rebalance length
            15 minutes,    // Oracle update threshold
            5 days         // Halt threshold
        );
        
        // Set interest rate parameters
        strategy.setInterestRateParams(
            900,           // Base rate 9%
            1800,          // Tier 1 rate 18%
            7200,          // Max rate 72%
            6500,          // Util tier 1 65%
            8500           // Util tier 2 85%
        );
        
        // Set fee parameters
        strategy.setProtocolFeeParams(
            1000,          // Protocol fee 10%
            feeRecipient   // Fee recipient
        );
        
        // Set user collateral parameters
        strategy.setUserCollateralParams(
            2000,          // Healthy ratio 20%
            1250           // Liquidation ratio 12.5%
        );
        
        // Set LP liquidity parameters
        strategy.setLPLiquidityParams(
            3000,          // Healthy ratio 30%
            2000,          // Liquidation threshold 20%
            50,            // Liquidation reward 0.5%
            0              // Minimum commitment amount
        );
    }
    
    // ==================== CONFIGURATION TESTS ====================
    
    function testInitialSettings() public view {
        (uint256 rebalancePeriod, uint256 oracleThreshold, uint256 poolHaltThreshold) = strategy.getCycleParams();
        assertEq(rebalancePeriod, 1 days, "Rebalance period should be set correctly");
        assertEq(oracleThreshold, 15 minutes, "Oracle threshold should be set correctly");
        assertEq(poolHaltThreshold, 5 days, "Halt threshold should be set correctly");
        
        (uint256 baseRate, uint256 rate1, uint256 maxRate, uint256 utilTier1, uint256 utilTier2) = 
            strategy.getInterestRateParams();
        assertEq(baseRate, 900, "Base interest rate should be set correctly");
        assertEq(rate1, 1800, "Tier 1 interest rate should be set correctly");
        assertEq(maxRate, 7200, "Max interest rate should be set correctly");
        assertEq(utilTier1, 6500, "Utilization tier 1 should be set correctly");
        assertEq(utilTier2, 8500, "Utilization tier 2 should be set correctly");
        
        assertEq(strategy.protocolFee(), 1000, "Protocol fee should be set correctly");
        assertEq(strategy.feeRecipient(), feeRecipient, "Fee recipient should be set correctly");
        
        (uint256 userHealthyRatio, uint256 userLiquidationThreshold) = strategy.getUserCollateralParams();
        assertEq(userHealthyRatio, 2000, "User healthy ratio should be set correctly");
        assertEq(userLiquidationThreshold, 1250, "User liquidation threshold should be set correctly");
        
        (uint256 lpHealthyRatio, uint256 lpLiquidationThreshold, uint256 lpLiquidationReward) = 
            strategy.getLPLiquidityParams();
        assertEq(lpHealthyRatio, 3000, "LP healthy ratio should be set correctly");
        assertEq(lpLiquidationThreshold, 2000, "LP liquidation threshold should be set correctly");
        assertEq(lpLiquidationReward, 50, "LP liquidation reward should be set correctly");
    }
    
    function testCycleParamsUpdate() public {
        strategy.setCycleParams(2 days, 30 minutes, 10 days);
        
        (uint256 rebalancePeriod, uint256 oracleThreshold, uint256 poolHaltThreshold) = strategy.getCycleParams();
        assertEq(rebalancePeriod, 2 days, "Rebalance period should be updated");
        assertEq(oracleThreshold, 30 minutes, "Oracle threshold should be updated");
        assertEq(poolHaltThreshold, 10 days, "Halt threshold should be updated");
    }
    
    function testInterestRateParamsUpdate() public {
        strategy.setInterestRateParams(
            500,    // Base rate 5%
            1500,   // Tier 1 rate 15%
            6000,   // Max rate 60%
            7000,   // Util tier 1 70%
            9000    // Util tier 2 90%
        );
        
        (uint256 baseRate, uint256 rate1, uint256 maxRate, uint256 utilTier1, uint256 utilTier2) = 
            strategy.getInterestRateParams();
        assertEq(baseRate, 500, "Base interest rate should be updated");
        assertEq(rate1, 1500, "Tier 1 interest rate should be updated");
        assertEq(maxRate, 6000, "Max interest rate should be updated");
        assertEq(utilTier1, 7000, "Utilization tier 1 should be updated");
        assertEq(utilTier2, 9000, "Utilization tier 2 should be updated");
    }
    
    function testInterestRateParamsValidation() public {
        // Base rate > Interest rate 1
        vm.expectRevert("Base rate must be <= Interest rate 1");
        strategy.setInterestRateParams(2000, 1500, 6000, 7000, 9000);
        
        // Interest rate 1 > Max rate
        vm.expectRevert("Interest rate 1 must be <= max rate");
        strategy.setInterestRateParams(500, 7000, 6000, 7000, 9000);
        
        // Max rate > 100%
        vm.expectRevert("Max rate cannot exceed 100%");
        strategy.setInterestRateParams(500, 1500, 11000, 7000, 9000);
        
        // Tier1 >= Tier2
        vm.expectRevert("Tier1 must be < Tier2");
        strategy.setInterestRateParams(500, 1500, 6000, 9000, 9000);
        
        // Tier2 >= BPS
        vm.expectRevert("Tier2 must be < BPS");
        strategy.setInterestRateParams(500, 1500, 6000, 7000, 10000);
    }
    
    function testProtocolFeeParamsUpdate() public {
        address newFeeRecipient = makeAddr("newFeeRecipient");
        strategy.setProtocolFeeParams(2000, newFeeRecipient);
        
        assertEq(strategy.protocolFee(), 2000, "Protocol fee should be updated");
        assertEq(strategy.feeRecipient(), newFeeRecipient, "Fee recipient should be updated");
    }
    
    function testProtocolFeeParamsValidation() public {
        // Fee > 100%
        vm.expectRevert("Fees cannot exceed 100%");
        strategy.setProtocolFeeParams(10001, feeRecipient);
        
        // Invalid fee recipient
        vm.expectRevert("Invalid fee recipient");
        strategy.setProtocolFeeParams(1000, address(0));
    }
    
    function testUserCollateralParamsUpdate() public {
        strategy.setUserCollateralParams(2500, 1500);
        
        (uint256 userHealthyRatio, uint256 userLiquidationThreshold) = strategy.getUserCollateralParams();
        assertEq(userHealthyRatio, 2500, "User healthy ratio should be updated");
        assertEq(userLiquidationThreshold, 1500, "User liquidation threshold should be updated");
    }
    
    function testUserCollateralParamsValidation() public {
        // Liquidation ratio > Healthy ratio
        vm.expectRevert("Liquidation ratio must be <= healthy ratio");
        strategy.setUserCollateralParams(1500, 2000);
    }
    
    function testLPLiquidityParamsUpdate() public {
        strategy.setLPLiquidityParams(3500, 2500, 100, 0);
        
        (uint256 lpHealthyRatio, uint256 lpLiquidationThreshold, uint256 lpLiquidationReward) = 
            strategy.getLPLiquidityParams();
        assertEq(lpHealthyRatio, 3500, "LP healthy ratio should be updated");
        assertEq(lpLiquidationThreshold, 2500, "LP liquidation threshold should be updated");
        assertEq(lpLiquidationReward, 100, "LP liquidation reward should be updated");
    }
    
    function testLPLiquidityParamsValidation() public {
        // Liquidation threshold > Healthy ratio
        vm.expectRevert("liquidation threshold must be <= healthy ratio");
        strategy.setLPLiquidityParams(2000, 3000, 50, 0);
        strategy.setLPLiquidityParams(3000, 2000, 50, 0);
        
        // Reward > 100%
        vm.expectRevert("Reward cannot exceed 100%");
        strategy.setLPLiquidityParams(3000, 2000, 10001, 0);
    }
    
    function testYieldBearingToggle() public {
        assertFalse(strategy.isYieldBearing(), "Should start as non-yield bearing");
        
        strategy.setIsYieldBearing();
        assertTrue(strategy.isYieldBearing(), "Should be yield bearing after toggle");
        
        strategy.setIsYieldBearing();
        assertFalse(strategy.isYieldBearing(), "Should be non-yield bearing after second toggle");
    }
    
    // ==================== INTEREST RATE TESTS ====================
    
    function testCalculateInterestRate_BelowTier1() public view {
        // Utilization below Tier 1 should return base rate
        uint256 rate = strategy.calculateInterestRate(5000); // 50% utilization
        assertEq(rate, 900, "Should return base rate for utilization below Tier 1");
    }
    
    function testCalculateInterestRate_BetweenTiers() public view {
        // Utilization between Tier 1 and Tier 2
        // Linear increase from 900 to 1800 between 65% and 85% utilization
        
        // At exactly Tier 1 (65%)
        uint256 rate1 = strategy.calculateInterestRate(6500);
        assertEq(rate1, 900, "Should return base rate at Tier 1 threshold");
        
        // At 75% utilization (halfway between Tier 1 and Tier 2)
        // Expected rate: 900 + (1800-900)/2 = 900 + 450 = 1350
        uint256 rate2 = strategy.calculateInterestRate(7500);
        assertEq(rate2, 1350, "Should return halfway rate for utilization halfway between tiers");
        
        // At exactly Tier 2 (85%)
        uint256 rate3 = strategy.calculateInterestRate(8500);
        assertEq(rate3, 1800, "Should return Tier 1 rate at Tier 2 threshold");
    }
    
    function testCalculateInterestRate_AboveTier2() public view {
        // Utilization above Tier 2
        // Linear increase from 1800 to 7200 between 85% and 100% utilization
        
        // At 90% utilization (1/3 of the way from Tier 2 to 100%)
        // Expected rate: 1800 + (7200-1800)/3 = 1800 + 1800 = 3600
        uint256 rate1 = strategy.calculateInterestRate(9000);
        uint256 expectedRate = 1800 + ((7200 - 1800) * 500) / 1500;
        assertEq(rate1, expectedRate, "Should return increased rate for utilization above Tier 2");
        
        // At 100% utilization (max)
        uint256 rate2 = strategy.calculateInterestRate(10000);
        assertEq(rate2, 7200, "Should return max rate for 100% utilization");
        
        // Above 100% utilization (capped)
        uint256 rate3 = strategy.calculateInterestRate(12000);
        assertEq(rate3, 7200, "Should return max rate for utilization above 100%");
    }
    
    // ==================== YIELD CALCULATION TESTS ====================
    
    function testCalculateYieldAccrued() public view {
        // Test with no previous amount
        uint256 yield1 = strategy.calculateYieldAccrued(0, 1000, 0);
        assertEq(yield1, 0, "Should return 0 yield for 0 deposit amount");
        
        // Test with no change (no yield)
        uint256 yield2 = strategy.calculateYieldAccrued(1000, 1000, 1000);
        assertEq(yield2, 0, "Should return 0 yield when amount doesn't change");
        
        // Test with 10% increase
        uint256 prevAmount = 1000 * 1e18;
        uint256 currentAmount = 1100 * 1e18;
        uint256 depositAmount = 1000 * 1e18;
        uint256 yield3 = strategy.calculateYieldAccrued(prevAmount, currentAmount, depositAmount);
        assertEq(yield3, 0.1 * 1e18, "Should return 10% yield for 10% increase");
        
        // Test with decrease (negative yield)
        uint256 yield4 = strategy.calculateYieldAccrued(1000, 900, 1000);
        assertEq(yield4, 0, "Should handle negative yield correctly");
    }
    
    // ==================== ACCESS CONTROL TESTS ====================
    
    function testOnlyOwnerCanUpdateParams() public {
        // Transfer ownership away from test contract
        address newOwner = makeAddr("newOwner");
        strategy.transferOwnership(newOwner);
        
        // Try to update parameters as non-owner
        vm.expectRevert();
        strategy.setCycleParams(2 days, 30 minutes, 10 days);
        
        vm.expectRevert();
        strategy.setInterestRateParams(500, 1500, 6000, 7000, 9000);
        
        vm.expectRevert();
        strategy.setProtocolFeeParams(2000, feeRecipient);
        
        vm.expectRevert();
        strategy.setUserCollateralParams(2500, 1500);
        
        vm.expectRevert();
        strategy.setLPLiquidityParams(3500, 2500, 100, 0);
        
        vm.expectRevert();
        strategy.setIsYieldBearing();
        
        // Update as new owner should work
        vm.startPrank(newOwner);
        strategy.setCycleParams(2 days, 30 minutes, 10 days);
        
        (uint256 rebalancePeriod, ,) = strategy.getCycleParams();
        assertEq(rebalancePeriod, 2 days, "Parameter should be updated when called by owner");
        vm.stopPrank();
    }
    
    // ==================== REQUIRED COLLATERAL CALCULATION TESTS ====================
    
    // Helper function to setup the test environment for collateral calculation
    function _setupMockAssetPoolForCollateralCalc() internal returns (address mockAssetPool, address mockUser) {
        // Deploy a mock contract inline for testing collateral calculations
        MockAssetPoolForStrategy mockPool = new MockAssetPoolForStrategy();
        mockUser = makeAddr("testUser");
        
        // Set up the mock pool with test data
        mockPool.setUserPosition(mockUser, 100e18, 100e18, 20e18);
        mockPool.setReserveToAssetDecimalFactor(1);
        mockPool.setCycleManagerRebalancePrice(100e18);
        mockPool.setInterestDebt(0);
        
        return (address(mockPool), mockUser);
    }
    
    function testCalculateUserRequiredCollateral() public {
        (address mockPool, address mockUser) = _setupMockAssetPoolForCollateralCalc();
        
        // Calculate required collateral based on 20% healthy ratio
        uint256 requiredCollateral = strategy.calculateUserRequiredCollateral(mockPool, mockUser);
        
        // Expected: asset value (100 * 100) * 20% = 2000
        assertEq(requiredCollateral, 2000e18, "Required collateral should be 20% of asset value");
        
        // Change user collateral parameters
        strategy.setUserCollateralParams(3000, 1500); // 30% healthy, 15% liquidation
        
        // Calculate again
        uint256 newRequiredCollateral = strategy.calculateUserRequiredCollateral(mockPool, mockUser);
        
        // Expected: asset value (100 * 100) * 30% = 3000
        assertEq(newRequiredCollateral, 3000e18, "Required collateral should update based on new parameters");
    }
    
    function testCalculateLPRequiredCollateral() public {
        // Deploy mock liquidity manager for testing
        MockLiquidityManagerForStrategy mockLiquidityManager = new MockLiquidityManagerForStrategy();
        address mockLP = makeAddr("testLP");
        
        // Set up the mock with test data
        mockLiquidityManager.setLPLiquidityCommitment(mockLP, 100e18);
        
        // Calculate required collateral based on 30% healthy ratio for LP
        uint256 requiredCollateral = strategy.calculateLPRequiredCollateral(address(mockLiquidityManager), mockLP);
        
        // Expected: asset value (100) * 30% = 30
        assertEq(requiredCollateral, 30e18, "LP required collateral should be 30% of asset value");
        
        // Change LP liquidity parameters
        strategy.setLPLiquidityParams(4000, 2500, 50, 0); // 40% healthy, 25% liquidation, 0.5% reward
        
        // Calculate again
        uint256 newRequiredCollateral = strategy.calculateLPRequiredCollateral(address(mockLiquidityManager), mockLP);
        
        // Expected: asset value (100) * 40% = 40
        assertEq(newRequiredCollateral, 40e18, "LP required collateral should update based on new parameters");
    }
    
    function testGetUserCollateralHealth() public {
        (address mockPool, address mockUser) = _setupMockAssetPoolForCollateralCalc();
        MockAssetPoolForStrategy(mockPool).setUserPosition(mockUser, 100e18, 10000e18, 2500e18);
        
        // Should be healthy with 25% collateral (above 20% healthy threshold)
        uint8 health = strategy.getUserCollateralHealth(mockPool, mockUser);
        assertEq(health, 3, "User should have healthy status with collateral above healthy threshold");
        
        // Set collateral to 15% (below healthy but above liquidation threshold)
        MockAssetPoolForStrategy(mockPool).setUserPosition(mockUser, 100e18, 10000e18, 1500e18);
        health = strategy.getUserCollateralHealth(mockPool, mockUser);
        assertEq(health, 2, "User should have warning status with collateral between thresholds");
        
        // Set collateral to 10% (below liquidation threshold)
        MockAssetPoolForStrategy(mockPool).setUserPosition(mockUser, 100e18, 10000e18, 1000e18);
        health = strategy.getUserCollateralHealth(mockPool, mockUser);
        assertEq(health, 1, "User should have liquidatable status with collateral below liquidation threshold");
        
        // Test with no asset amount (always healthy)
        MockAssetPoolForStrategy(mockPool).setUserPosition(mockUser, 0, 100e18, 0);
        health = strategy.getUserCollateralHealth(mockPool, mockUser);
        assertEq(health, 3, "User should have healthy status with no asset amount");
    }
    
    function testGetLPLiquidityHealth() public {
        MockLiquidityManagerForStrategy mockLiquidityManager = new MockLiquidityManagerForStrategy();
        address mockLP = makeAddr("testLP");
        
        // Set up the mock with test data
        mockLiquidityManager.setLPLiquidityCommitment(mockLP, 100e18);
        
        // Test healthy case (35% collateral > 30% healthy threshold)
        mockLiquidityManager.setLPCollateral(mockLP, 35e18);
        uint8 health = strategy.getLPLiquidityHealth(address(mockLiquidityManager), mockLP);
        assertEq(health, 3, "LP should have healthy status with collateral above healthy threshold");
        
        // Test warning case (25% collateral, between healthy and liquidation thresholds)
        mockLiquidityManager.setLPCollateral(mockLP, 25e18);
        health = strategy.getLPLiquidityHealth(address(mockLiquidityManager), mockLP);
        assertEq(health, 2, "LP should have warning status with collateral between thresholds");
        
        // Test liquidatable case (15% collateral < 20% liquidation threshold)
        mockLiquidityManager.setLPCollateral(mockLP, 15e18);
        health = strategy.getLPLiquidityHealth(address(mockLiquidityManager), mockLP);
        assertEq(health, 1, "LP should have liquidatable status with collateral below liquidation threshold");
    }
}

// Mock contracts for testing collateral calculations

contract MockAssetPoolForStrategy {
    struct UserPosition {
        uint256 assetAmount;
        uint256 depositAmount;
        uint256 collateralAmount;
    }
    
    mapping(address => UserPosition) public userPositions;
    address public poolCycleManager;
    uint256 public reserveToAssetDecimalFactor;
    uint256 public interestDebtValue;
    
    constructor() {
        poolCycleManager = address(new MockCycleManager());
    }
    
    function setUserPosition(
        address user,
        uint256 assetAmount,
        uint256 depositAmount,
        uint256 collateralAmount
    ) external {
        userPositions[user] = UserPosition({
            assetAmount: assetAmount,
            depositAmount: depositAmount,
            collateralAmount: collateralAmount
        });
    }
    
    function setReserveToAssetDecimalFactor(uint256 factor) external {
        reserveToAssetDecimalFactor = factor;
    }
    
    function setCycleManagerRebalancePrice(uint256 price) external {
        MockCycleManager(poolCycleManager).setRebalancePrice(price);
    }
    
    function setInterestDebt(uint256 debt) external {
        interestDebtValue = debt;
    }
    
    // Interface functions required by DefaultPoolStrategy
    
    function getPoolCycleManager() external view returns (address) {
        return poolCycleManager;
    }
    
    function getReserveToAssetDecimalFactor() external view returns (uint256) {
        return reserveToAssetDecimalFactor;
    }

    function getInterestDebt(address, uint256) external view returns (uint256) {
        return interestDebtValue;
    }
}

contract MockCycleManager {
    uint256 public cycleIndex = 1;
    mapping(uint256 => uint256) public cycleRebalancePrice;
    
    function setRebalancePrice(uint256 price) external {
        cycleRebalancePrice[cycleIndex - 1] = price;
    }
}

contract MockLiquidityManagerForStrategy {
    mapping(address => uint256) public lpAssetHoldingValues;
    mapping(address => uint256) public lpLiquidityCommitments;
    mapping(address => uint256) public lpCollateralValues;
    
    struct LPPosition {
        uint256 liquidityCommitment;
        uint256 collateralAmount;
        uint256 interestAccrued;
    }
    
    function setLPAssetHoldingValue(address lp, uint256 value) external {
        lpAssetHoldingValues[lp] = value;
    }
    
    function setLPCollateral(address lp, uint256 collateral) external {
        lpCollateralValues[lp] = collateral;
    }

    function setLPLiquidityCommitment(address lp, uint256 commitment) external {
        lpLiquidityCommitments[lp] = commitment;
    }
    
    // Interface functions required by DefaultPoolStrategy

    function getLPLiquidityCommitment(address lp) external view returns (uint256) {
        return lpLiquidityCommitments[lp];
    }
    
    function getLPAssetHoldingValue(address lp) external view returns (uint256) {
        return lpAssetHoldingValues[lp];
    }
    
    function getLPPosition(address lp) external view returns (LPPosition memory) {
        return LPPosition({
            liquidityCommitment: 100e18,
            collateralAmount: lpCollateralValues[lp],
            interestAccrued: 0
        });
    }
}