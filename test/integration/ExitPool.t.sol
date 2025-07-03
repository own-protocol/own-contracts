// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "../utils/ProtocolTestUtils.sol";

/**
 * @title ExitPoolTest
 * @notice Tests the exitPool functionality for both users and LPs when pool is halted
 * @dev Tests various scenarios for exiting the pool in halted state
 */
contract ExitPoolTest is ProtocolTestUtils {
    // Base amounts (will be adjusted based on token decimals)
    uint256 constant INITIAL_PRICE = 100 * 1e18; // $100.00 per asset (always 18 decimals)
    uint256 constant USER_INITIAL_BALANCE = 100_000; 
    uint256 constant LP_INITIAL_BALANCE = 1_000_000;
    uint256 constant LP_LIQUIDITY_AMOUNT = 500_000;
    uint256 constant USER_DEPOSIT_AMOUNT = 10_000;
    uint256 constant COLLATERAL_RATIO = 20; // 20% collateral

    // Additional liquidity provider for testing forced rebalance
    address public liquidityProvider3;

    function setUp() public {
        // Setup protocol with 6 decimal token (like USDC)
        bool success = setupProtocol(
            "xTSLA",                // Asset symbol
            6,                      // Reserve token decimals (USDC like)
            INITIAL_PRICE,          // Initial price
            USER_INITIAL_BALANCE,   // User amount (base units)
            LP_INITIAL_BALANCE,     // LP amount (base units)
            LP_LIQUIDITY_AMOUNT     // LP liquidity (base units)
        );
        
        require(success, "Protocol setup failed");

        // Create a third LP that will later not rebalance (for force rebalance tests)
        liquidityProvider3 = makeAddr("lp3");
        reserveToken.mint(liquidityProvider3, adjustAmountForDecimals(LP_INITIAL_BALANCE, 6));
        
        vm.startPrank(liquidityProvider3);
        reserveToken.approve(address(liquidityManager), type(uint256).max);
        reserveToken.approve(address(cycleManager), type(uint256).max);
        liquidityManager.addLiquidity(adjustAmountForDecimals(LP_LIQUIDITY_AMOUNT, 6));
        vm.stopPrank();
        
        _completeCycle();
        
        // Verify pool is back to active state
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_ACTIVE), "Pool should be in ACTIVE state after rebalance");
    }

    /**
     * @notice Tests forcing the pool into halted state
     */
    function testForcePoolIntoHaltedState() public {
        // Create some user activity to have non-zero balances
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Complete a cycle
        _completeCycle();
        
        // User claims assets
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Start another rebalance process
        vm.prank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        
        vm.warp(block.timestamp + 1 hours);
        
        vm.prank(owner);
        assetOracle.setMarketOpen(false);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // LP1 and LP2 rebalance normally, but LP3 doesn't
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, INITIAL_PRICE);
        
        vm.prank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, INITIAL_PRICE);
        
        // At this point, LP3 has not rebalanced, but we need to advance past the rebalance window
        // Get the halt threshold from the strategy
        uint256 haltThreshold = poolStrategy.haltThreshold();

        // Advance time past the halt threshold
        vm.warp(block.timestamp + haltThreshold + 1);
        
        // Force rebalance LP3 which should halt the pool
        vm.prank(owner);
        cycleManager.forceRebalanceLP(liquidityProvider3);
        
        // Verify pool is halted
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_HALTED), "Pool should be in HALTED state");
    }

    /**
     * @notice Tests user exit pool functionality
     */
    function testUserExitPool() public {
        // Put pool in halted state
        testForcePoolIntoHaltedState();
        
        // Verify user1 has assets
        uint256 userAssetBalance = assetToken.balanceOf(user1);
        assertTrue(userAssetBalance > 0, "User should have assets to exit with");
        
        uint256 userReserveBalanceBefore = reserveToken.balanceOf(user1);
        
        // User exits the pool
        vm.prank(user1);
        assetPool.exitPool(userAssetBalance);
        
        // Verify user has received reserve tokens
        uint256 userReserveBalanceAfter = reserveToken.balanceOf(user1);
        assertTrue(userReserveBalanceAfter > userReserveBalanceBefore, "User should have received reserve tokens");
        
        // Verify user assets are burned
        assertEq(assetToken.balanceOf(user1), 0, "User asset balance should be zero after exit");
        
        // Verify user position is cleared
        (uint256 assetAmount, uint256 depositAmount, uint256 collateralAmount) = assetPool.userPositions(user1);
        assertEq(assetAmount, 0, "User asset amount should be zero after exit");
        assertEq(depositAmount, 0, "User deposit amount should be zero after exit");
        assertEq(collateralAmount, 0, "User collateral amount should be zero after exit");
    }

    /**
     * @notice Tests user exit pool with partial assets
     */
    function testUserExitPoolPartial() public {
        // Put pool in halted state
        testForcePoolIntoHaltedState();
        
        // Verify user1 has assets
        uint256 userAssetBalance = assetToken.balanceOf(user1);
        assertTrue(userAssetBalance > 0, "User should have assets to exit with");
        
        uint256 userReserveBalanceBefore = reserveToken.balanceOf(user1);
        uint256 partialAmount = userAssetBalance / 2;
        
        // User exits the pool with partial amount
        vm.prank(user1);
        assetPool.exitPool(partialAmount);
        
        // Verify user has received reserve tokens
        uint256 userReserveBalanceAfter = reserveToken.balanceOf(user1);
        assertTrue(userReserveBalanceAfter > userReserveBalanceBefore, "User should have received reserve tokens");
        
        // Verify user assets are partially burned
        assertEq(assetToken.balanceOf(user1), userAssetBalance - partialAmount, "User should have partial assets remaining");
        
        // Verify user position is partially updated
        (uint256 assetAmount, uint256 depositAmount, uint256 collateralAmount) = assetPool.userPositions(user1);
        assertTrue(assetAmount > 0, "User should have asset amount remaining");
        assertTrue(depositAmount > 0, "User should have deposit amount remaining");
        assertTrue(collateralAmount > 0, "User should have collateral amount remaining");
    }

    /**
     * @notice Tests user claim asset functionality when pool is halted
     */
    function testUserClaimAssetWhenHalted() public {
        // First create a deposit request
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user2);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Now put pool in halted state
        testForcePoolIntoHaltedState();
        
        // Attempt to claim assets in halted state
        vm.prank(user2);
        assetPool.claimAsset(user2);
        
        // Verify user received assets
        assertTrue(assetToken.balanceOf(user2) > 0, "User should have received assets");
    }

    /**
     * @notice Tests user claim reserve functionality when pool is halted
     */
    function testUserClaimReserveWhenHalted() public {
        // First create a redemption request
        // Setup: User3 deposits and claims assets
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user3);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Complete a cycle and claim assets
        _completeCycle();
        
        vm.prank(user3);
        assetPool.claimAsset(user3);
        
        // Create a redemption request
        uint256 assetBalance = assetToken.balanceOf(user3);
        
        vm.startPrank(user3);
        assetToken.approve(address(assetPool), assetBalance);
        assetPool.redemptionRequest(assetBalance);
        vm.stopPrank();
        
        // Now put pool in halted state
        testForcePoolIntoHaltedState();
        
        uint256 user3ReserveBalanceBefore = reserveToken.balanceOf(user3);
        
        // Attempt to claim reserves in halted state
        vm.prank(user3);
        assetPool.claimReserve(user3);
        
        // Verify user received reserves
        uint256 user3ReserveBalanceAfter = reserveToken.balanceOf(user3);
        assertTrue(user3ReserveBalanceAfter > user3ReserveBalanceBefore, "User should have received reserve tokens");
    }

    /**
     * @notice Tests LP exit pool functionality
     */
    function testLPExitPool() public {
        // Put pool in halted state
        testForcePoolIntoHaltedState();
        
        // Check initial state of LP1
        uint256 lp1ReserveBalanceBefore = reserveToken.balanceOf(liquidityProvider1);
        IPoolLiquidityManager.LPPosition memory initialPosition = liquidityManager.getLPPosition(liquidityProvider1);
        
        assertTrue(initialPosition.liquidityCommitment > 0, "LP should have liquidity committed");
        assertTrue(initialPosition.collateralAmount > 0, "LP should have collateral");
        assertTrue(liquidityManager.isLP(liquidityProvider1), "LP1 should be registered as LP");
        
        // LP1 exits the pool
        vm.prank(liquidityProvider1);
        liquidityManager.exitPool();
        
        // Verify LP1 has received reserve tokens
        uint256 lp1ReserveBalanceAfter = reserveToken.balanceOf(liquidityProvider1);
        assertTrue(lp1ReserveBalanceAfter > lp1ReserveBalanceBefore, "LP should have received reserve tokens");
        
        // Verify LP position is cleared
        IPoolLiquidityManager.LPPosition memory finalPosition = liquidityManager.getLPPosition(liquidityProvider1);
        assertEq(finalPosition.liquidityCommitment, 0, "LP liquidity commitment should be zero after exit");
        assertEq(finalPosition.collateralAmount, 0, "LP collateral amount should be zero after exit");
        
        // Verify LP is no longer registered
        assertFalse(liquidityManager.isLP(liquidityProvider1), "LP should not be registered after exit");
    }

    /**
     * @notice Tests the forced LP exiting after force rebalance
     */
    function testForcedLPExitPool() public {
        // Put pool in halted state
        testForcePoolIntoHaltedState();
        
        // Check initial state of LP2 (the one that was force rebalanced)
        uint256 lp2ReserveBalanceBefore = reserveToken.balanceOf(liquidityProvider2);        
        // Verify LP2 is still an LP after force rebalance
        assertTrue(liquidityManager.isLP(liquidityProvider3), "LP2 should still be registered as LP");
        
        // LP2 exits the pool
        vm.prank(liquidityProvider2);
        liquidityManager.exitPool();
        
        // Verify LP2 has received reserve tokens
        uint256 lp2ReserveBalanceAfter = reserveToken.balanceOf(liquidityProvider2);
        assertTrue(lp2ReserveBalanceAfter > lp2ReserveBalanceBefore, "LP should have received reserve tokens");
        
        // Verify LP position is cleared
        IPoolLiquidityManager.LPPosition memory finalPosition = liquidityManager.getLPPosition(liquidityProvider2);
        assertEq(finalPosition.liquidityCommitment, 0, "LP liquidity commitment should be zero after exit");
        assertEq(finalPosition.collateralAmount, 0, "LP collateral amount should be zero after exit");
        
        // Verify LP is no longer registered
        assertFalse(liquidityManager.isLP(liquidityProvider2), "LP should not be registered after exit");
    }

    /**
     * @notice Tests that exitPool reverts when pool is not halted (for Users)
     */
    function testExitPoolFailsWhenPoolNotHalted_User() public {
        // Create user with assets
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Complete a cycle and claim assets
        _completeCycle();
        
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        uint256 userAssetBalance = assetToken.balanceOf(user1);
        
        // Attempt to exit pool when it's active - should fail
        vm.startPrank(user1);
        vm.expectRevert("Pool not halted");
        assetPool.exitPool(userAssetBalance);
        vm.stopPrank();
    }

    /**
     * @notice Tests that exitPool reverts when pool is not halted (for LPs)
     */
    function testExitPoolFailsWhenPoolNotHalted_LP() public {
        // Attempt to exit pool when it's active - should fail
        vm.startPrank(liquidityProvider1);
        vm.expectRevert(IPoolCycleManager.InvalidCycleState.selector);
        liquidityManager.exitPool();
        vm.stopPrank();
    }

    /**
     * @notice Tests edge case: User with pending request tries to exitPool
     */
    function testExitPoolWithPendingRequest() public {
        // Create a deposit request
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user2);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Now put pool in halted state
        testForcePoolIntoHaltedState();

        // Make sure user2 has some assets already
        vm.startPrank(user1);
        assetToken.transfer(user2, assetToken.balanceOf(user1) / 2);
        vm.stopPrank();

        uint256 user2AssetBalance = assetToken.balanceOf(user2);
        // Attempt to exit pool with pending request - should fail
        vm.startPrank(user2);
        assetToken.approve(address(assetPool), user2AssetBalance);
        vm.expectRevert(IAssetPool.RequestPending.selector);
        assetPool.exitPool(user2AssetBalance);
        vm.stopPrank();
    }


    function _completeCycle() internal {
        // Start the off-chain rebalance phase
        vm.prank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        
        vm.warp(block.timestamp + 1 hours);
        
        // Start the on-chain rebalance phase
        vm.prank(owner);
        assetOracle.setMarketOpen(false);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // All 3 LPs participate in the initial rebalance
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, INITIAL_PRICE);
        
        vm.prank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, INITIAL_PRICE);
        
        vm.prank(liquidityProvider3);
        cycleManager.rebalancePool(liquidityProvider3, INITIAL_PRICE);
    }
}