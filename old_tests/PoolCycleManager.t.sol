// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./utils/ProtocolTestUtils.sol";

/**
 * @title PoolCycleManagerTest
 * @notice Unit and integration tests for the PoolCycleManager contract
 */
contract PoolCycleManagerTest is ProtocolTestUtils {
    // Constants for testing
    uint256 constant LP_LIQUIDITY_AMOUNT = 1_000_000 * 1e6; // 1M USDC
    uint256 constant USER_BALANCE = 1_000_000 * 1e6; // 1M USDC
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
    
    // Test cycle state transitions
    function testCycleStateTransitions() public {
        // Initial state should be ACTIVE with cycle 1
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.ACTIVE));
        assertEq(cycleManager.cycleIndex(), 1);
        
        // Try to initiate onchain rebalance directly (should fail)
        vm.expectRevert(IPoolCycleManager.InvalidCycleState.selector);
        cycleManager.initiateOnchainRebalance();
        
        // Try to initiate offchain rebalance before cycle length (should fail)
        vm.expectRevert(IPoolCycleManager.CycleInProgress.selector);
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to end of cycle
        vm.warp(block.timestamp + CYCLE_LENGTH);
        
        // Initiate offchain rebalance
        cycleManager.initiateOffchainRebalance();
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.REBALANCING_OFFCHAIN));
        
        // Try to initiate offchain rebalance again (should fail)
        vm.expectRevert(IPoolCycleManager.InvalidCycleState.selector);
        cycleManager.initiateOffchainRebalance();
        
        // Try to initiate onchain rebalance before rebalance length (should fail)
        vm.expectRevert(IPoolCycleManager.OffChainRebalanceInProgress.selector);
        cycleManager.initiateOnchainRebalance();
        
        // Advance time but don't update oracle (should fail)
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        vm.expectRevert(IPoolCycleManager.OracleNotUpdated.selector);
        cycleManager.initiateOnchainRebalance();
        
        // Update oracle and initiate onchain rebalance
        updateOraclePrice(INITIAL_PRICE);
        cycleManager.initiateOnchainRebalance();
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.REBALANCING_ONCHAIN));
        
        // LP1 rebalances
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, INITIAL_PRICE);
        
        // LP1 tries to rebalance again (should fail)
        vm.prank(liquidityProvider1);
        vm.expectRevert(IPoolCycleManager.AlreadyRebalanced.selector);
        cycleManager.rebalancePool(liquidityProvider1, INITIAL_PRICE);
        
        // LP2 rebalances - this should complete the cycle
        vm.prank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, INITIAL_PRICE);
        
        // Check state after all LPs rebalance
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.ACTIVE));
        assertEq(cycleManager.cycleIndex(), 2); // Should be in cycle 2 now
    }
    
    // Test rebalance calculations with deposits
    function testRebalanceWithDeposits() public {
        // User makes a deposit
        uint256 depositAmount = 100_000 * 1e6; // 100k USDC
        uint256 collateralAmount = 20_000 * 1e6; // 20k USDC
        
        vm.prank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        
        // Advance to end of cycle
        vm.warp(block.timestamp + CYCLE_LENGTH);
        
        // Start offchain rebalance
        cycleManager.initiateOffchainRebalance();
        
        // Advance time and update price
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        updateOraclePrice(INITIAL_PRICE);
        
        // Start onchain rebalance
        cycleManager.initiateOnchainRebalance();
        
        int256 netAssetDelta = cycleManager.netAssetDelta();
        
        // netAssetDelta should be positive (new assets being minted)
        assertTrue(netAssetDelta > 0, "Net asset delta should be positive");
        
        // LP1 rebalances with the correct price
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, INITIAL_PRICE);
        
        // LP2 rebalances with the correct price
        vm.prank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, INITIAL_PRICE);
        
        // Cycle should be complete
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.ACTIVE));
        assertEq(cycleManager.cycleIndex(), 2);
    }
    
    // Test rebalance calculations with redemptions
    function testRebalanceWithRedemptions() public {
        // First create a position with tokens
        uint256 depositAmount = 100_000 * 1e6;
        uint256 collateralAmount = 20_000 * 1e6;
        
        vm.prank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        
        // Complete a cycle to mint tokens
        simulateProtocolCycle(0, 0, INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimRequest(user1);
        
        // User redeems half of their tokens
        uint256 userBalance = assetToken.balanceOf(user1);
        uint256 redemptionAmount = userBalance / 2;
        
        vm.startPrank(user1);
        assetToken.approve(address(assetPool), redemptionAmount);
        assetPool.redemptionRequest(redemptionAmount);
        vm.stopPrank();
        
        // Advance to end of cycle
        vm.warp(block.timestamp + CYCLE_LENGTH);
        
        // Start offchain rebalance
        vm.prank(liquidityProvider2);
        cycleManager.initiateOffchainRebalance();
        
        // Advance time and update price
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        updateOraclePrice(INITIAL_PRICE * 2 );
        
        // Start onchain rebalance
        cycleManager.initiateOnchainRebalance();
        
        // Check rebalance calculation results
        int256 netAssetDelta = cycleManager.netAssetDelta();
        int256 rebalanceAmount = cycleManager.rebalanceAmount();
        
        // netAssetDelta should be negative (assets being burned)
        assertTrue(netAssetDelta < 0, "Net asset delta should be negative");
        // rebalanceAmount should be negative
        assertTrue(rebalanceAmount > 0, "Rebalance amount should be positive");
        
        // LP1 rebalances
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, INITIAL_PRICE * 2);
        
        // LP2 rebalances
        vm.prank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, INITIAL_PRICE * 2);
        
        // Cycle should be complete
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.ACTIVE));
        assertEq(cycleManager.cycleIndex(), 3);
    }
    
    // Test rebalance with price change
    function testRebalanceWithPriceChange() public {
        // User makes a deposit
        uint256 depositAmount = 100_000 * 1e6;
        uint256 collateralAmount = 20_000 * 1e6;
        
        vm.prank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        
        // Complete cycle 1
        simulateProtocolCycle(0, 0, INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimRequest(user1);
        
        // Price increases by 20%
        uint256 newPrice = INITIAL_PRICE * 120 / 100;
        
        // Another user makes a deposit
        vm.prank(user2);
        assetPool.depositRequest(depositAmount, collateralAmount);
        
        // Complete cycle 2 with new price
        simulateProtocolCycle(0, 0, newPrice);
        
        // User2 claims
        vm.prank(user2);
        assetPool.claimRequest(user2);
        
        // Check token balances - user2 should have fewer tokens due to higher price
        uint256 user1Tokens = assetToken.balanceOf(user1);
        uint256 user2Tokens = assetToken.balanceOf(user2);
        
        assertTrue(user2Tokens < user1Tokens, "User2 should have fewer tokens due to higher price");
        assertApproxEqRel(user2Tokens, user1Tokens * 100 / 120, 0.01e18, "Token ratio should match price ratio");
    }
    
    // Test LP rebalance deadline
    function testRebalanceDeadline() public {
        // User makes a deposit
        uint256 depositAmount = 100_000 * 1e6;
        uint256 collateralAmount = 20_000 * 1e6;
        
        vm.prank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        
        // Start cycle transition
        vm.warp(block.timestamp + CYCLE_LENGTH);
        cycleManager.initiateOffchainRebalance();
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        updateOraclePrice(INITIAL_PRICE);
        cycleManager.initiateOnchainRebalance();
        
        // Only LP1 rebalances
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, INITIAL_PRICE);
        
        // Time passes beyond rebalance window
        vm.warp(block.timestamp + REBALANCE_LENGTH + 1);
        
        // LP2 tries to rebalance (should fail)
        vm.prank(liquidityProvider2);
        vm.expectRevert(IPoolCycleManager.RebalancingExpired.selector);
        cycleManager.rebalancePool(liquidityProvider2, INITIAL_PRICE);
        
        // Settle the pool
        vm.prank(liquidityProvider1);
        cycleManager.settlePool();
        
        // Cycle should be complete despite incomplete rebalancing
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.ACTIVE));
        assertEq(cycleManager.cycleIndex(), 2);
    }
    
    // Test interest accrual
    function testInterestAccrual() public {
        // Prepare a state with assets earning interest
        uint256 depositAmount = 100_000 * 1e6;
        uint256 collateralAmount = 20_000 * 1e6;
        
        vm.prank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        
        // Complete a cycle
        simulateProtocolCycle(0, 0, INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimRequest(user1);
        
        // Record initial interest values
        uint256 initialCumulativeInterest = cycleManager.cumulativePoolInterest();
        uint256 initialCumulativeAmount = cycleManager.cumulativeInterestAmount();
        
        // Advance time significantly to accrue substantial interest
        vm.warp(block.timestamp + 365 days);
        
        // Trigger interest accrual
        cycleManager.initiateOffchainRebalance();
        
        // Check interest has accrued
        uint256 newCumulativeInterest = cycleManager.cumulativePoolInterest();
        uint256 newCumulativeAmount = cycleManager.cumulativeInterestAmount();
        
        assertTrue(newCumulativeInterest > initialCumulativeInterest, "Interest should have accrued");
        assertTrue(newCumulativeAmount > initialCumulativeAmount, "Interest amount should have increased");
        
        // Complete the cycle
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        updateOraclePrice(INITIAL_PRICE);
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // Check interest distribution to LPs
        uint256 cycleInterest = cycleManager.cycleInterestAmount();
        assertTrue(cycleInterest > 0, "Cycle interest should be positive");
        
        // Track LP collateral before rebalance
        uint256 lp1InitialCollateral = liquidityManager.getLPInfo(liquidityProvider1).collateralAmount;
        
        // LP1 rebalances
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, INITIAL_PRICE);
        
        // LP2 rebalances
        vm.prank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, INITIAL_PRICE);
        
        // Verify LP received interest
        uint256 lp1NewCollateral = liquidityManager.getLPInfo(liquidityProvider1).collateralAmount;
        assertTrue(lp1NewCollateral > lp1InitialCollateral, "LP should have received interest");
        
        // Approximate check that interest was split fairly between LPs
        uint256 lp1Interest = lp1NewCollateral - lp1InitialCollateral;
        assertApproxEqRel(lp1Interest, cycleInterest / 2, 0.01e18, "LP should receive about half the interest");
    }
    
    // Test startNewCycle with no requests
    function testStartNewCycleWithNoRequests() public {
        // Move to end of cycle
        vm.warp(block.timestamp + CYCLE_LENGTH);
        
        // Start offchain rebalance
        vm.prank(liquidityProvider1);
        cycleManager.initiateOffchainRebalance();
        
        // With no deposits/redemptions, should be able to start new cycle directly
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        updateOraclePrice(INITIAL_PRICE);
        
        // Try directly starting a new cycle
        vm.prank(liquidityProvider1);
        cycleManager.startNewCycle();
        
        // Cycle should be advancing correctly
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.ACTIVE));
        assertEq(cycleManager.cycleIndex(), 2);
    }

    // Test cycle with different LP liquidity proportions
    function testCycleWithDifferentLpProportions() public {
        // Reset setup with uneven LP distribution
        vm.prank(liquidityProvider1);
        liquidityManager.increaseLiquidity(LP_LIQUIDITY_AMOUNT); // Double LP1's liquidity
        
        // User makes a deposit
        uint256 depositAmount = 100_000 * 1e6;
        uint256 collateralAmount = 20_000 * 1e6;
        
        vm.prank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        
        // Complete a cycle
        simulateProtocolCycle(0, 0, INITIAL_PRICE);
        
        // // Check LP rebalance amounts - LP1 should handle 2/3 of rebalance
        // uint256 lp1CollateralIncrease = liquidityManager.getLPInfo(liquidityProvider1).collateralAmount -
        //                                  (LP_LIQUIDITY_AMOUNT * 2 * liquidityManager.registrationCollateralRatio() / 100_00);
        // uint256 lp2CollateralIncrease = liquidityManager.getLPInfo(liquidityProvider2).collateralAmount -
        //                                  (LP_LIQUIDITY_AMOUNT * liquidityManager.registrationCollateralRatio() / 100_00);

        // // LP1 has twice the liquidity so should receive twice the interest/rebalance benefit
        // assertApproxEqRel(lp1CollateralIncrease, lp2CollateralIncrease * 2, 0.01e18);
    }
    
    // Test price deviation limits
    function testPriceDeviationLimits() public {
        // User makes a deposit
        uint256 depositAmount = 100_000 * 1e6;
        uint256 collateralAmount = 20_000 * 1e6;
        
        vm.prank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        
        // Start cycle transition
        vm.warp(block.timestamp + CYCLE_LENGTH);
        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        updateOraclePrice(INITIAL_PRICE); // $100
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // Try to rebalance with price too low (more than 3% deviation)
        uint256 lowPrice = INITIAL_PRICE * 96 / 100; // $96 (4% lower than oracle price)
        vm.prank(liquidityProvider1);
        vm.expectRevert(IPoolCycleManager.PriceDeviationTooHigh.selector);
        cycleManager.rebalancePool(liquidityProvider1, lowPrice);
        
        // Try to rebalance with price too high
        uint256 highPrice = INITIAL_PRICE * 104 / 100; // $104 (4% higher than oracle price)
        vm.prank(liquidityProvider1);
        vm.expectRevert(IPoolCycleManager.PriceDeviationTooHigh.selector);
        cycleManager.rebalancePool(liquidityProvider1, highPrice);
        
        // Rebalance with acceptable price
        uint256 acceptablePrice = INITIAL_PRICE * 102 / 100; // $102 (2% higher than oracle price)
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, acceptablePrice);
        
        // Complete the cycle with LP2
        vm.prank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, INITIAL_PRICE);
        
        // Check that weighted average price is set correctly
        uint256 cyclePrice = cycleManager.cycleRebalancePrice(1);
        assertTrue(cyclePrice > INITIAL_PRICE && cyclePrice < acceptablePrice, "Cycle price should be weighted average");
    }
    
    // Test unauthorized access
    function testUnauthorizedAccess() public {
        // Non-LP tries to use LP functions
        vm.startPrank(user1);
        
        vm.expectRevert(IPoolCycleManager.NotLP.selector);
        cycleManager.rebalancePool(user1, INITIAL_PRICE);
        
        vm.expectRevert(IPoolCycleManager.NotLP.selector);
        cycleManager.settlePool();
        
        vm.stopPrank();
    }
}