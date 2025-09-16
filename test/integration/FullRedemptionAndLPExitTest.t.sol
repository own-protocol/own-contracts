// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "../utils/ProtocolTestUtils.sol";

/**
 * @title FullRedemptionAndLPExitTest
 * @notice Integration test for complete user redemption at higher price followed by LP liquidity removal
 * @dev Tests the edge case scenario where:
 *      1. LP adds liquidity
 *      2. User deposits and mints assets
 *      3. After one cycle, user redeems full amount & the price goes up in the same cycle
 *      4. LP removes full liquidity & exits completely
 *      This tests potential underflow scenarios in updateCycleData and liquidity management
 */
contract FullRedemptionAndLPExitTest is ProtocolTestUtils {
    // Base amounts (will be adjusted based on token decimals)
    uint256 constant INITIAL_PRICE = 100 * 1e18; // $100.00 per asset (always 18 decimals)ß
    uint256 constant HIGHER_PRICE = 130 * 1e18;   // $130.00 per asset (30% increase)
    uint256 constant USER_INITIAL_BALANCE = 100_000;
    uint256 constant LP_INITIAL_BALANCE = 1_000_000;
    uint256 constant LP_LIQUIDITY_AMOUNT = 500_000;
    uint256 constant USER_DEPOSIT_AMOUNT = 50_000; // Larger deposit to test edge cases
    uint256 constant COLLATERAL_RATIO = 20; // 20% collateral

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
    }

    /**
     * @notice Main integration test: Full user redemption at higher price + LP exit
     * @dev This tests the complete flow that could potentially cause underflows
     */
    function testFullRedemptionAndLPExit() public {

        // ==================== PHASE 1: USER DEPOSIT AND CLAIM ====================
        
        // User makes a deposit
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        uint256 totalUserDeposit = depositAmount + collateralAmount;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Verify deposit request
        (IAssetPool.RequestType reqType, uint256 reqAmount, uint256 reqCollateral, uint256 reqCycle) = assetPool.userRequests(user1);
        assertEq(uint(reqType), uint(IAssetPool.RequestType.DEPOSIT), "Should have deposit request");
        assertEq(reqAmount, depositAmount, "Request amount should match");
        assertEq(reqCollateral, collateralAmount, "Collateral amount should match");
        
        // Complete cycle at initial price to process deposit
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // User claims assets
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Verify user received assets
        uint256 userAssetBalance = assetToken.balanceOf(user1);
        assertGt(userAssetBalance, 0, "User should have received assets");
        
        // Calculate expected asset amount
        uint256 expectedAssetAmount = getExpectedAssetAmount(depositAmount, INITIAL_PRICE);
        assertApproxEqRel(userAssetBalance, expectedAssetAmount, 0.01e18, "Asset amount should match expected");

        // ==================== PHASE 2: FULL USER REDEMPTION ====================
        
        // User redeems ALL their assets at the higher price
        vm.startPrank(user1);
        assetToken.approve(address(assetPool), userAssetBalance);
        assetPool.redemptionRequest(userAssetBalance);
        vm.stopPrank();
        
        // Verify redemption request
        (reqType, reqAmount, , reqCycle) = assetPool.userRequests(user1);
        assertEq(uint(reqType), uint(IAssetPool.RequestType.REDEEM), "Should have redemption request");
        assertEq(reqAmount, userAssetBalance, "Redemption amount should match user's full balance");

        // Complete cycle to process the redemption
        completeCycleWithPriceChange(HIGHER_PRICE);

        // User claims reserve tokens
        uint256 userReserveBeforeRedemptionClaim = reserveToken.balanceOf(user1);
        
        vm.prank(user1);
        assetPool.claimReserve(user1);
        
        uint256 userReserveAfterRedemptionClaim = reserveToken.balanceOf(user1);
        uint256 redemptionPayout = userReserveAfterRedemptionClaim - userReserveBeforeRedemptionClaim;
        
        // Calculate expected redemption amount at higher price
        uint256 expectedRedemptionReserve = getExpectedReserveAmount(userAssetBalance, HIGHER_PRICE);
        uint256 expectedTotalRedemption = expectedRedemptionReserve + collateralAmount;
        
        // User should receive more than initial deposit due to price increase
        assertGt(redemptionPayout, totalUserDeposit, "User should receive more due to price increase");
        assertApproxEqRel(redemptionPayout, expectedTotalRedemption, 0.03e18, "Redemption payout should be approximately correct");
        
        // Verify user's asset balance is now zero
        assertEq(assetToken.balanceOf(user1), 0, "User should have no assets after redemption");

        // Verify total asset supply is zero
        uint256 totalAssetSupply = assetToken.totalSupply();
        assertEq(totalAssetSupply, 0, "Total asset supply should be zero after full redemption");

         // ==================== PHASE 3: COMPLETE LP EXIT ====================
        
        // Get initial LP positions and protocol state
        IPoolLiquidityManager.LPPosition memory lp1Position = liquidityManager.getLPPosition(liquidityProvider1);
        IPoolLiquidityManager.LPPosition memory lp2Position = liquidityManager.getLPPosition(liquidityProvider2);
        uint256 initialTotalCommitment = liquidityManager.totalLPLiquidityCommited();
        
        // Record LP balances before exit for comparison
        uint256 lp1BalanceBefore = reserveToken.balanceOf(liquidityProvider1);
        uint256 lp2BalanceBefore = reserveToken.balanceOf(liquidityProvider2);
        
        // Verify LPs have liquidity committed initially
        assertGt(lp1Position.liquidityCommitment, 0, "LP1 should have liquidity commitment");
        assertGt(lp2Position.liquidityCommitment, 0, "LP2 should have liquidity commitment");
        assertGt(lp1Position.collateralAmount, 0, "LP1 should have collateral");
        assertGt(lp2Position.collateralAmount, 0, "LP2 should have collateral");
        assertGt(initialTotalCommitment, 0, "Protocol should have total liquidity commitment");
        
        // LP1 reduces all their liquidity
        vm.startPrank(liquidityProvider1);
        liquidityManager.reduceLiquidity(lp1Position.liquidityCommitment);
        vm.stopPrank();
        
        // LP2 reduces all their liquidity  
        vm.startPrank(liquidityProvider2);
        liquidityManager.reduceLiquidity(lp2Position.liquidityCommitment);
        vm.stopPrank();
        
        // Verify reduction requests are created
        IPoolLiquidityManager.LPRequest memory lp1Request = liquidityManager.getLPRequest(liquidityProvider1);
        IPoolLiquidityManager.LPRequest memory lp2Request = liquidityManager.getLPRequest(liquidityProvider2);
        
        assertEq(uint(lp1Request.requestType), uint(IPoolLiquidityManager.RequestType.REDUCE_LIQUIDITY), "LP1 should have reduction request");
        assertEq(lp1Request.requestAmount, lp1Position.liquidityCommitment, "LP1 reduction amount should match full commitment");
        
        assertEq(uint(lp2Request.requestType), uint(IPoolLiquidityManager.RequestType.REDUCE_LIQUIDITY), "LP2 should have reduction request");
        assertEq(lp2Request.requestAmount, lp2Position.liquidityCommitment, "LP2 reduction amount should match full commitment");
        
        // Complete cycle to process LP liquidity reductions
        completeCycleWithPriceChange(HIGHER_PRICE);
        
        // ==================== PHASE 4: VERIFY LP LIQUIDITY EXIT ====================
        
        // Verify both LPs have zero liquidity commitment after cycle completion
        IPoolLiquidityManager.LPPosition memory lp1PositionAfterReduction = liquidityManager.getLPPosition(liquidityProvider1);
        IPoolLiquidityManager.LPPosition memory lp2PositionAfterReduction = liquidityManager.getLPPosition(liquidityProvider2);
        
        assertEq(lp1PositionAfterReduction.liquidityCommitment, 0, "LP1 should have zero liquidity commitment");
        assertEq(lp2PositionAfterReduction.liquidityCommitment, 0, "LP2 should have zero liquidity commitment");
        
        // Verify protocol total commitment is zero
        uint256 finalTotalCommitment = liquidityManager.totalLPLiquidityCommited();
        assertEq(finalTotalCommitment, 0, "Protocol should have zero total liquidity commitment");
        
        // Verify LPs are no longer active but still registered
        assertFalse(liquidityManager.isLPActive(liquidityProvider1), "LP1 should not be active");
        assertFalse(liquidityManager.isLPActive(liquidityProvider2), "LP2 should not be active");
        assertTrue(liquidityManager.isLP(liquidityProvider1), "LP1 should still be registered");
        assertTrue(liquidityManager.isLP(liquidityProvider2), "LP2 should still be registered");
        
        // LPs still have collateral and potentially interest that they need to exit to claim
        assertGt(lp1PositionAfterReduction.collateralAmount, 0, "LP1 should still have collateral");
        assertGt(lp2PositionAfterReduction.collateralAmount, 0, "LP2 should still have collateral");
        
        // ==================== PHASE 5: COMPLETE LP EXIT WITH COLLATERAL & INTEREST ====================
        
        // Now LPs can exit since they're inactive (zero liquidity commitment)
        // LP1 exits completely to claim collateral and interest
        vm.prank(liquidityProvider1);
        liquidityManager.exitPool();
        
        // LP2 exits completely to claim collateral and interest
        vm.prank(liquidityProvider2);
        liquidityManager.exitPool();
        
        // ==================== PHASE 6: VERIFY COMPLETE LP EXIT ====================
        
        // Verify both LPs received their funds (collateral + any interest)
        uint256 lp1BalanceAfter = reserveToken.balanceOf(liquidityProvider1);
        uint256 lp2BalanceAfter = reserveToken.balanceOf(liquidityProvider2);
        
        assertGt(lp1BalanceAfter, lp1BalanceBefore, "LP1 should have received collateral and interest");
        assertGt(lp2BalanceAfter, lp2BalanceBefore, "LP2 should have received collateral and interest");
        
        // The amount received should at least equal their initial collateral
        uint256 lp1Received = lp1BalanceAfter - lp1BalanceBefore;
        uint256 lp2Received = lp2BalanceAfter - lp2BalanceBefore;
        
        assertGe(lp1Received, lp1Position.collateralAmount, "LP1 should receive at least their collateral");
        assertGe(lp2Received, lp2Position.collateralAmount, "LP2 should receive at least their collateral");
        
        // Verify LP positions are completely cleared
        IPoolLiquidityManager.LPPosition memory lp1FinalPosition = liquidityManager.getLPPosition(liquidityProvider1);
        IPoolLiquidityManager.LPPosition memory lp2FinalPosition = liquidityManager.getLPPosition(liquidityProvider2);
        
        assertEq(lp1FinalPosition.liquidityCommitment, 0, "LP1 final liquidity commitment should be zero");
        assertEq(lp1FinalPosition.collateralAmount, 0, "LP1 final collateral should be zero");
        assertEq(lp1FinalPosition.interestAccrued, 0, "LP1 final interest should be zero");
        
        assertEq(lp2FinalPosition.liquidityCommitment, 0, "LP2 final liquidity commitment should be zero");
        assertEq(lp2FinalPosition.collateralAmount, 0, "LP2 final collateral should be zero");
        assertEq(lp2FinalPosition.interestAccrued, 0, "LP2 final interest should be zero");
        
        // Verify LPs are no longer registered in the protocol
        assertFalse(liquidityManager.isLP(liquidityProvider1), "LP1 should not be registered after complete exit");
        assertFalse(liquidityManager.isLP(liquidityProvider2), "LP2 should not be registered after complete exit");
        assertFalse(liquidityManager.isLPActive(liquidityProvider1), "LP1 should not be active after complete exit");
        assertFalse(liquidityManager.isLPActive(liquidityProvider2), "LP2 should not be active after complete exit");
        
        // Verify cycle liquidity commitment calculations are consistent
        uint256 cycleTotalLiquidity = liquidityManager.getCycleTotalLiquidityCommited();
        assertEq(cycleTotalLiquidity, 0, "Cycle total liquidity should be zero");
        
        // Verify no pending liquidity changes in cycle data
        assertEq(liquidityManager.cycleTotalAddLiquidityAmount(), 0, "Should have no pending additions");
        assertEq(liquidityManager.cycleTotalReduceLiquidityAmount(), 0, "Should have no pending reductions");
        
        // ==================== PHASE 7: VERIFY PROTOCOL STATE INTEGRITY ====================
        
        // The protocol should be in a valid state even with zero liquidity and no LPs
        // Asset supply should remain zero from user redemption
        assertEq(assetToken.totalSupply(), 0, "Asset supply should remain zero");
        
        // Pool should still be active (not halted) despite no LP liquidity or LPs
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_ACTIVE), "Pool should remain active");
        
        // Verify total LP collateral is zero
        assertEq(liquidityManager.totalLPCollateral(), 0, "Total LP collateral should be zero");
        
        // LP count should be zero since both LPs completely exited
        assertEq(liquidityManager.lpCount(), 0, "LP count should be zero");

    }
}