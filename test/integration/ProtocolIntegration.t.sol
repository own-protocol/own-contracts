// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../utils/ProtocolTestUtils.sol";

/**
 * @title ProtocolIntegrationTest
 * @notice Integration tests for the full protocol workflow
 */
contract ProtocolIntegrationTest is ProtocolTestUtils {
    // Constants for testing
    uint256 constant LP_LIQUIDITY_AMOUNT = 1_000_000 * 1e6; // 1M USDC
    uint256 constant USER_BALANCE = 100_000 * 1e6; // 100k USDC
    uint256 constant LP_BALANCE = 2_000_000 * 1e6; // 2M USDC
    uint256 constant INITIAL_PRICE = 100 * 1e18; // $100.00 per asset
    
    function setUp() public {
        // Deploy protocol with 6 decimals for USDC
        deployProtocol("xTSLA", "TSLA", 6);
        
        // Fund accounts
        fundAccounts(USER_BALANCE, LP_BALANCE);
        
        // Setup liquidity providers
        setupLiquidityProviders(LP_LIQUIDITY_AMOUNT);
        
        // Set initial asset price
        updateOraclePrice(INITIAL_PRICE);
    }
    
    // Test the full happy path workflow
    function testFullProtocolHappyPath() public {
        // Initial deposit requests
        uint256 depositAmount = 10_000 * 1e6; // 10k USDC
        uint256 collateralAmount = 2_000 * 1e6; // 2k USDC (20%)
        
        // User1 submits deposit request
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Verify deposit request state
        (uint256 reqAmount, uint256 reqCollateral, bool isDeposit, uint256 reqCycle) = assetPool.userRequest(user1);
        assertEq(reqAmount, depositAmount);
        assertEq(reqCollateral, collateralAmount);
        assertTrue(isDeposit);
        assertEq(reqCycle, 0); // First cycle
        
        // Move to offchain rebalance
        vm.warp(block.timestamp + CYCLE_LENGTH);
        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        
        // Check cycle state
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.REBALANCING_OFFCHAIN));
        
        // Advance time and update oracle price
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        updateOraclePrice(INITIAL_PRICE);
        
        // Initiate onchain rebalance
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // Check cycle state
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.REBALANCING_ONCHAIN));
        
        // LPs perform rebalancing
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, INITIAL_PRICE);
        
        vm.prank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, INITIAL_PRICE);
        
        // Check cycle state - should be active after all LPs rebalance
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.ACTIVE));
        assertEq(cycleManager.cycleIndex(), 1); // Now in cycle 1
        
        // User1 claims their xTokens
        vm.prank(user1);
        assetPool.claimRequest(user1);
        
        // Calculate expected xToken amount: depositAmount * 10^18 / assetPrice
        uint256 expectedXTokens = (depositAmount * 1e18 * assetPool.reserveToAssetDecimalFactor()) / INITIAL_PRICE;
        
        // Check user1's xToken balance
        assertApproxEqRel(assetToken.balanceOf(user1), expectedXTokens, 0.01e18); // Allow 1% deviation
        
        // User1 submits redemption request for half their tokens
        uint256 redemptionAmount = assetToken.balanceOf(user1) / 2;
        
        vm.startPrank(user1);
        assetToken.approve(address(assetPool), redemptionAmount);
        assetPool.redemptionRequest(redemptionAmount);
        vm.stopPrank();
        
        // Simulate another cycle
        advanceCycle();
        
        // User1 claims their redemption
        vm.prank(user1);
        assetPool.claimRequest(user1);
        
        // Verify user1's updated xToken balance
        assertApproxEqRel(assetToken.balanceOf(user1), expectedXTokens - redemptionAmount, 0.01e18);
    }
    
    // Test cancel deposit request
    function testCancelDepositRequest() public {
        // User submits deposit request
        uint256 depositAmount = 10_000 * 1e6;
        uint256 collateralAmount = 2_000 * 1e6;
        
        uint256 initialBalance = reserveToken.balanceOf(user1);
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        
        // Verify request is recorded
        (uint256 reqAmount, , , ) = assetPool.userRequest(user1);
        assertEq(reqAmount, depositAmount);
        
        // Cancel the request
        assetPool.cancelRequest();
        vm.stopPrank();
        
        // Verify request is cleared
        (reqAmount, , , ) = assetPool.userRequest(user1);
        assertEq(reqAmount, 0);
        
        // Verify tokens are returned
        assertEq(reserveToken.balanceOf(user1), initialBalance);
    }
    
    // Test price deviation limits during rebalance
    function testPriceDeviationCheck() public {
        // User submits deposit request
        uint256 depositAmount = 10_000 * 1e6;
        uint256 collateralAmount = 2_000 * 1e6;
        
        vm.prank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        
        // Initiate offchain rebalance
        vm.warp(block.timestamp + CYCLE_LENGTH);
        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        
        // Advance time and update oracle price
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        updateOraclePrice(INITIAL_PRICE); // $100
        
        // Initiate onchain rebalance
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // LP1 tries to rebalance with price too low (more than 3% deviation)
        uint256 lowPrice = INITIAL_PRICE * 96 / 100; // $96 is 4% lower
        
        vm.prank(liquidityProvider1);
        vm.expectRevert(IPoolCycleManager.PriceDeviationTooHigh.selector);
        cycleManager.rebalancePool(liquidityProvider1, lowPrice);
        
        // LP1 tries to rebalance with price too high
        uint256 highPrice = INITIAL_PRICE * 104 / 100; // $104 is 4% higher
        
        vm.prank(liquidityProvider1);
        vm.expectRevert(IPoolCycleManager.PriceDeviationTooHigh.selector);
        cycleManager.rebalancePool(liquidityProvider1, highPrice);
        
        // LP1 rebalances with acceptable price (within 3%)
        uint256 acceptablePrice = INITIAL_PRICE * 102 / 100; // $102 is 2% higher
        
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, acceptablePrice);
        
        // LP2 rebalances with another acceptable price
        uint256 anotherAcceptablePrice = INITIAL_PRICE * 98 / 100; // $98 is 2% lower
        
        vm.prank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, anotherAcceptablePrice);
    }
    
    // Test interest accumulation
    function testInterestAccumulation() public {
        // User deposits and mints xTokens
        uint256 depositAmount = 10_000 * 1e6;
        
        // Complete a cycle to mint xTokens
        simulateProtocolCycle(depositAmount, 0, INITIAL_PRICE);
        
        // Store initial interest values
        uint256 initialCumulativeInterest = cycleManager.cumulativePoolInterest();
        
        // Advance time by one cycle to accrue interest
        vm.warp(block.timestamp + CYCLE_LENGTH);
        
        // Trigger interest accrual by starting offchain rebalance
        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        
        // Check that interest accrued
        uint256 newCumulativeInterest = cycleManager.cumulativePoolInterest();
        assertTrue(newCumulativeInterest > initialCumulativeInterest, "Interest should have accrued");
        
        // Complete the cycle
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // Check that cycle interest amount is set
        uint256 cycleInterestAmount = cycleManager.cycleInterestAmount();
        assertTrue(cycleInterestAmount > 0, "Cycle interest amount should be positive");
        
        // LPs rebalance to collect interest
        uint256 lpInitialCollateral = liquidityManager.getLPInfo(liquidityProvider1).collateralAmount;
        
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, INITIAL_PRICE);
        
        vm.prank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, INITIAL_PRICE);
        
        // Verify LP received interest
        uint256 lpNewCollateral = liquidityManager.getLPInfo(liquidityProvider1).collateralAmount;
        assertTrue(lpNewCollateral > lpInitialCollateral, "LP should have received interest");
    }
}