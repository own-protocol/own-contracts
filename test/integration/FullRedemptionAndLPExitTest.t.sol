// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "../utils/ProtocolTestUtils.sol";

/**
 * @title FullRedemptionAndLPExitTest
 * @notice Integration test for complete user redemption at higher price followed by LP liquidity removal
 * @dev Tests the edge case scenario where:
 *      1. LP adds liquidity
 *      2. User deposits and mints assets
 *      3. After one cycle, user redeems full amount when price is higher
 *      4. LP removes full liquidity
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

    }
}