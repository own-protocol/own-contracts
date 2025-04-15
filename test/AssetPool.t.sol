// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "./utils/ProtocolTestUtils.sol";

/**
 * @title AssetPoolTest
 * @notice Unit tests for the AssetPool contract focusing on deposit, redemption, and claim functionality
 */
contract AssetPoolTest is ProtocolTestUtils {
    // Base amounts (will be adjusted based on token decimals)
    uint256 constant INITIAL_PRICE = 100 * 1e18; // $100.00 per asset (always 18 decimals)
    uint256 constant USER_INITIAL_BALANCE = 100_000; 
    uint256 constant LP_INITIAL_BALANCE = 1_000_000;
    uint256 constant LP_LIQUIDITY_AMOUNT = 500_000;
    uint256 constant COLLATERAL_RATIO = 20; // 20% collateral

    // Test deposit amounts
    uint256 constant SMALL_DEPOSIT = 1_000;
    uint256 constant MEDIUM_DEPOSIT = 10_000;
    uint256 constant LARGE_DEPOSIT = 50_000;

    // Price scenarios
    uint256 constant PRICE = 100 * 1e18;

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

    // ==================== DEPOSIT REQUEST TESTS ====================

    /**
     * @notice Test basic deposit request functionality
     */
    function testDepositRequest() public {
        uint256 depositAmount = adjustAmountForDecimals(MEDIUM_DEPOSIT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        uint256 initialUserBalance = reserveToken.balanceOf(user1);
        uint256 initialPoolBalance = reserveToken.balanceOf(address(assetPool));
        
        // Execute deposit request
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Verify request state
        (IAssetPool.RequestType reqType, uint256 reqAmount, uint256 reqCollateral, uint256 reqCycle) = assetPool.userRequests(user1);
        
        // Assert request data
        assertEq(uint(reqType), uint(IAssetPool.RequestType.DEPOSIT), "Request type should be DEPOSIT");
        assertEq(reqAmount, depositAmount, "Request amount should match deposit amount");
        assertEq(reqCollateral, collateralAmount, "Request collateral should match collateral amount");
        assertEq(reqCycle, cycleManager.cycleIndex(), "Request cycle should match current cycle");
        
        // Assert balances
        assertEq(reserveToken.balanceOf(user1), initialUserBalance - depositAmount - collateralAmount, "User balance should be reduced by deposit + collateral");
        assertEq(reserveToken.balanceOf(address(assetPool)), initialPoolBalance + depositAmount + collateralAmount, "Pool balance should increase by deposit + collateral");
        
        // Assert cycle total deposits
        assertEq(assetPool.cycleTotalDeposits(), depositAmount, "Cycle total deposits should match deposit amount");
    }

    /**
     * @notice Test deposit request with insufficient collateral
     */
    function testDepositRequestInsufficientCollateral() public {
        uint256 depositAmount = adjustAmountForDecimals(MEDIUM_DEPOSIT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100 - 100; // 100 wei less than required
        
        // Expect revert when collateral is insufficient
        vm.startPrank(user1);
        vm.expectRevert(IAssetPool.InsufficientCollateral.selector);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
    }

    /**
     * @notice Test deposit request when user has a pending request
     */
    function testDepositRequestWithPendingRequest() public {
        uint256 depositAmount = adjustAmountForDecimals(MEDIUM_DEPOSIT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        // First deposit request
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        
        // Second deposit request should fail
        vm.expectRevert(IAssetPool.RequestPending.selector);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
    }

    /**
     * @notice Test deposit request when pool has insufficient liquidity
     */
    function testDepositRequestInsufficientLiquidity() public {
        // Calculate a deposit amount larger than total LP 
        uint256 _userAmount = adjustAmountForDecimals(LP_INITIAL_BALANCE * 2, 6);
        reserveToken.mint(user1, _userAmount);
        uint256 depositAmount = adjustAmountForDecimals(LP_INITIAL_BALANCE + 1, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        // Expect revert when requested amount exceeds available liquidity
        vm.startPrank(user1);
        vm.expectRevert(IAssetPool.InsufficientLiquidity.selector);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
    }

    /**
     * @notice Test deposit request with zero amount
     */
    function testDepositRequestZeroAmount() public {
        uint256 collateralAmount = adjustAmountForDecimals(1000, 6);
        
        // Expect revert when deposit amount is zero
        vm.startPrank(user1);
        vm.expectRevert(IAssetPool.InvalidAmount.selector);
        assetPool.depositRequest(0, collateralAmount);
        vm.stopPrank();
    }

    /**
     * @notice Test deposit request with zero collateral
     */
    function testDepositRequestZeroCollateral() public {
        uint256 depositAmount = adjustAmountForDecimals(MEDIUM_DEPOSIT, 6);
        
        // Expect revert when collateral amount is zero
        vm.startPrank(user1);
        vm.expectRevert(IAssetPool.InvalidAmount.selector);
        assetPool.depositRequest(depositAmount, 0);
        vm.stopPrank();
    }

    // ==================== REDEMPTION REQUEST TESTS ====================

    /**
     * @notice Test basic redemption request functionality
     * @dev First deposits and claims assets, then tests redemption
     */
    function testRedemptionRequest() public {
        // Setup: User deposits and claims assets
        uint256 depositAmount = adjustAmountForDecimals(MEDIUM_DEPOSIT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Complete cycle
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // Claim assets
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Get asset balance
        uint256 assetBalance = assetToken.balanceOf(user1);
        require(assetBalance > 0, "User should have assets to redeem");
        
        uint256 redeemAmount = assetBalance / 2; // Redeem half
        
        // Execute redemption request
        vm.startPrank(user1);
        assetToken.approve(address(assetPool), redeemAmount);
        assetPool.redemptionRequest(redeemAmount);
        vm.stopPrank();
        
        // Verify request state
        (IAssetPool.RequestType reqType, uint256 reqAmount, , uint256 reqCycle) = assetPool.userRequests(user1);
        
        // Assert request data
        assertEq(uint(reqType), uint(IAssetPool.RequestType.REDEEM), "Request type should be REDEEM");
        assertEq(reqAmount, redeemAmount, "Request amount should match redeem amount");
        assertEq(reqCycle, cycleManager.cycleIndex(), "Request cycle should match current cycle");
        
        // Assert asset balance
        assertEq(assetToken.balanceOf(user1), assetBalance - redeemAmount, "User asset balance should be reduced by redeem amount");
        assertEq(assetToken.balanceOf(address(assetPool)), redeemAmount, "Pool asset balance should increase by redeem amount");
        
        // Assert cycle total redemptions
        assertEq(assetPool.cycleTotalRedemptions(), redeemAmount, "Cycle total redemptions should match redeem amount");
    }

    /**
     * @notice Test redemption request with insufficient balance
     */
    function testRedemptionRequestInsufficientBalance() public {
        // Setup: User deposits and claims assets
        uint256 depositAmount = adjustAmountForDecimals(MEDIUM_DEPOSIT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        uint256 assetBalance = assetToken.balanceOf(user1);
        uint256 redeemAmount = assetBalance + 1; // More than balance
        
        // Expect revert when redemption amount exceeds balance
        vm.startPrank(user1);
        assetToken.approve(address(assetPool), redeemAmount);
        vm.expectRevert(); // Either InsufficientBalance or ERC20 error
        assetPool.redemptionRequest(redeemAmount);
        vm.stopPrank();
    }

    /**
     * @notice Test redemption request with pending request
     */
    function testRedemptionRequestWithPendingRequest() public {
        // Setup: User deposits and claims assets
        uint256 depositAmount = adjustAmountForDecimals(MEDIUM_DEPOSIT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        uint256 assetBalance = assetToken.balanceOf(user1);
        uint256 redeemAmount = assetBalance / 2;
        
        // First redemption request
        vm.startPrank(user1);
        assetToken.approve(address(assetPool), assetBalance);
        assetPool.redemptionRequest(redeemAmount);
        
        // Second redemption request should fail
        vm.expectRevert(IAssetPool.RequestPending.selector);
        assetPool.redemptionRequest(redeemAmount);
        vm.stopPrank();
    }

    /**
     * @notice Test redemption request with zero amount
     */
    function testRedemptionRequestZeroAmount() public {
        // Setup: User deposits and claims assets
        uint256 depositAmount = adjustAmountForDecimals(MEDIUM_DEPOSIT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Expect revert when redemption amount is zero
        vm.startPrank(user1);
        vm.expectRevert(IAssetPool.InvalidAmount.selector);
        assetPool.redemptionRequest(0);
        vm.stopPrank();
    }

    // ==================== CLAIM ASSET TESTS ====================

    /**
     * @notice Test basic claim asset functionality
     */
    function testClaimAsset() public {
        // Setup: User deposits
        uint256 depositAmount = adjustAmountForDecimals(MEDIUM_DEPOSIT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Complete cycle
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // Initial state checks
        uint256 initialAssetBalance = assetToken.balanceOf(user1);
        assertEq(initialAssetBalance, 0, "User should have no assets initially");
        
        // Execute claim
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Verify claim
        uint256 finalAssetBalance = assetToken.balanceOf(user1);
        assertGt(finalAssetBalance, 0, "User should have assets after claim");
        
        // Calculate expected asset amount
        uint256 expectedAssetAmount = getExpectedAssetAmount(depositAmount, INITIAL_PRICE);
        assertEq(finalAssetBalance, expectedAssetAmount, "Asset balance should match expected amount");
        
        // Verify request was cleared
        (IAssetPool.RequestType reqType, , , ) = assetPool.userRequests(user1);
        assertEq(uint(reqType), uint(IAssetPool.RequestType.NONE), "Request should be cleared after claim");
        
        // Verify user position is updated
        (uint256 posAssetAmount, uint256 posDepositAmount, uint256 posCollateralAmount) = assetPool.userPositions(user1);
        assertEq(posAssetAmount, finalAssetBalance, "Position asset amount should match balance");
        assertEq(posDepositAmount, depositAmount, "Position deposit amount should match deposit");
        assertEq(posCollateralAmount, collateralAmount, "Position collateral amount should match collateral");
    }

    /**
     * @notice Test claim asset with no pending claim
     */
    function testClaimAssetNoPendingClaim() public {
        // Expect revert when there's no pending claim
        vm.prank(user1);
        vm.expectRevert(IAssetPool.NothingToClaim.selector);
        assetPool.claimAsset(user1);
    }

    /**
     * @notice Test claim asset in same cycle (not yet processed)
     */
    function testClaimAssetSameCycle() public {
        // Setup: User deposits
        uint256 depositAmount = adjustAmountForDecimals(MEDIUM_DEPOSIT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Attempt to claim in same cycle
        vm.prank(user1);
        vm.expectRevert(IAssetPool.NothingToClaim.selector);
        assetPool.claimAsset(user1);
    }

    /**
     * @notice Test claim asset with wrong request type
     */
    function testClaimAssetWrongRequestType() public {
        // Setup: User deposits and claims
        uint256 depositAmount = adjustAmountForDecimals(MEDIUM_DEPOSIT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Setup redemption request
        uint256 assetBalance = assetToken.balanceOf(user1);
        
        vm.startPrank(user1);
        assetToken.approve(address(assetPool), assetBalance);
        assetPool.redemptionRequest(assetBalance);
        vm.stopPrank();
        
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // Try to claim asset for a redemption request
        vm.prank(user1);
        vm.expectRevert(IAssetPool.NothingToClaim.selector);
        assetPool.claimAsset(user1);
    }

    // ==================== CLAIM RESERVE TESTS ====================

    /**
     * @notice Test basic claim reserve functionality
     */
    function testClaimReserve() public {
        // Setup: User deposits, claims, then redeems
        uint256 depositAmount = adjustAmountForDecimals(MEDIUM_DEPOSIT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        uint256 assetBalance = assetToken.balanceOf(user1);
        uint256 initialReserveBalance = reserveToken.balanceOf(user1);
        
        // Make redemption request
        vm.startPrank(user1);
        assetToken.approve(address(assetPool), assetBalance);
        assetPool.redemptionRequest(assetBalance);
        vm.stopPrank();
        
        completeCycleWithPriceChange(INITIAL_PRICE);

        // Execute claim reserve
        vm.prank(user1);
        assetPool.claimReserve(user1);
        
        // Verify reserve claim
        uint256 finalReserveBalance = reserveToken.balanceOf(user1);
        uint256 claimedAmount = finalReserveBalance - initialReserveBalance;
        
        assertGt(claimedAmount, 0, "User should have received reserve tokens");
        
        // Calculate expected reserve amount (including collateral)
        uint256 expectedReserveAmount = depositAmount + collateralAmount;
        
        // Check claim amount is close to expected (accounting for interest)
        assertApproxEqRel(claimedAmount, expectedReserveAmount, 0.01e18, "Claimed amount should be close to expected");
        
        // Verify request was cleared
        (IAssetPool.RequestType reqType, , , ) = assetPool.userRequests(user1);
        assertEq(uint(reqType), uint(IAssetPool.RequestType.NONE), "Request should be cleared after claim");
        
        // Verify user position is cleared
        (uint256 posAssetAmount, uint256 posDepositAmount, uint256 posCollateralAmount) = assetPool.userPositions(user1);
        assertEq(posAssetAmount, 0, "Position asset amount should be zero");
        assertEq(posDepositAmount, 0, "Position deposit amount should be zero");
        assertEq(posCollateralAmount, 0, "Position collateral amount should be zero");
    }

    /**
     * @notice Test claim reserve with no pending claim
     */
    function testClaimReserveNoPendingClaim() public {
        // Expect revert when there's no pending claim
        vm.prank(user1);
        vm.expectRevert(IAssetPool.NothingToClaim.selector);
        assetPool.claimReserve(user1);
    }

    /**
     * @notice Test claim reserve in same cycle (not yet processed)
     */
    function testClaimReserveSameCycle() public {
        // Setup: User deposits, claims, then redeems
        uint256 depositAmount = adjustAmountForDecimals(MEDIUM_DEPOSIT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        uint256 assetBalance = assetToken.balanceOf(user1);
        
        // Make redemption request
        vm.startPrank(user1);
        assetToken.approve(address(assetPool), assetBalance);
        assetPool.redemptionRequest(assetBalance);
        vm.stopPrank();
        
        // Attempt to claim in same cycle
        vm.prank(user1);
        vm.expectRevert(IAssetPool.NothingToClaim.selector);
        assetPool.claimReserve(user1);
    }

    /**
     * @notice Test claim reserve with wrong request type
     */
    function testClaimReserveWrongRequestType() public {
        // Setup: User deposits
        uint256 depositAmount = adjustAmountForDecimals(MEDIUM_DEPOSIT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // Try to claim reserve for a deposit request
        vm.prank(user1);
        vm.expectRevert(IAssetPool.NothingToClaim.selector);
        assetPool.claimReserve(user1);
    }


    // ==================== COLLATERAL TESTS ====================

    /**
     * @notice Test adding collateral to a position
     */
    function testAddCollateral() public {
        // Setup: User deposits and claims
        uint256 depositAmount = adjustAmountForDecimals(MEDIUM_DEPOSIT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Initial collateral check
        (, , uint256 initialCollateral) = assetPool.userPositions(user1);
        assertEq(initialCollateral, collateralAmount, "Initial collateral should match deposit");
        
        // Add more collateral
        uint256 additionalCollateral = adjustAmountForDecimals(5_000, 6);
        uint256 initialBalance = reserveToken.balanceOf(user1);
        
        vm.startPrank(user1);
        assetPool.addCollateral(user1, additionalCollateral);
        vm.stopPrank();
        
        // Verify collateral was added
        (, , uint256 finalCollateral) = assetPool.userPositions(user1);
        assertEq(finalCollateral, initialCollateral + additionalCollateral, "Collateral should increase by added amount");
        
        // Verify user balance decreased
        assertEq(reserveToken.balanceOf(user1), initialBalance - additionalCollateral, "User balance should decrease by collateral amount");
    }

    /**
     * @notice Test reducing collateral from a position
     */
    function testReduceCollateral() public {
        // Setup: User deposits and claims with excess collateral
        uint256 depositAmount = adjustAmountForDecimals(MEDIUM_DEPOSIT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        collateralAmount *= 2; // Double collateral for this test
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount );
        vm.stopPrank();
        
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Calculate minimum required collateral
        uint256 minCollateral = (depositAmount * COLLATERAL_RATIO) / 100;
        uint256 excessCollateral = collateralAmount - minCollateral;
        
        // Reduce collateral
        uint256 reduceAmount = excessCollateral / 2; // Reduce by half
        uint256 initialBalance = reserveToken.balanceOf(user1);
        
        vm.startPrank(user1);
        assetPool.reduceCollateral(reduceAmount);
        vm.stopPrank();
        
        // Verify collateral was reduced
        (, , uint256 finalCollateral) = assetPool.userPositions(user1);
        assertEq(finalCollateral, collateralAmount - reduceAmount, "Collateral should decrease by reduced amount");
        
        // Verify user balance increased
        assertEq(reserveToken.balanceOf(user1), initialBalance + reduceAmount, "User balance should increase by reduced amount");
    }

    /**
     * @notice Test reducing too much collateral
     */
    function testReduceCollateralExcessive() public {
        // Setup: User deposits and claims
        uint256 depositAmount = adjustAmountForDecimals(MEDIUM_DEPOSIT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100; // Minimum required
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Try to reduce any collateral (should fail as we're at minimum)
        vm.startPrank(user1);
        vm.expectRevert(IAssetPool.ExcessiveWithdrawal.selector);
        assetPool.reduceCollateral(1);
        vm.stopPrank();
    }

    /**
     * @notice Test that functions can only be called during active pool state
     * @dev Puts the pool in rebalancing state and attempts operations that require active state
     */
    function testOnlyActivePoolModifier() public {
        // First check that operations work in active state
        assertTrue(_isPoolActive(), "Pool should start in active state");
        
        // Setup a basic deposit to verify it works in active state
        uint256 depositAmount = adjustAmountForDecimals(SMALL_DEPOSIT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Now initiate rebalancing to change pool state
        vm.startPrank(owner);
        assetOracle.setMarketOpen(true);
        cycleManager.initiateOffchainRebalance();
        vm.stopPrank();
        
        // Verify state is no longer active
        assertFalse(_isPoolActive(), "Pool should be in rebalancing state");
        
        // Try operations that require active state - all should revert
        
        // 1. Deposit request
        vm.startPrank(user2);
        vm.expectRevert("Pool not active");
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // 2. Redemption request
        vm.startPrank(user2);        
        vm.expectRevert("Pool not active");
        uint256 assetBalance = adjustAmountForDecimals(SMALL_DEPOSIT, 18);
        assetPool.redemptionRequest(assetBalance);
        vm.stopPrank();
        
        // 3. Liquidation request
        vm.startPrank(user3);
        vm.expectRevert("Pool not active");
        assetPool.liquidationRequest(user2, 1);
        vm.stopPrank();
        
        // Return pool to active state for cleanup
        vm.startPrank(owner);
        assetOracle.setMarketOpen(false);
        updateOraclePrice(PRICE);
        cycleManager.initiateOnchainRebalance();
        vm.stopPrank();

        // Try claim asset & reserve which should revert
        vm.startPrank(user1);
        vm.expectRevert("Pool not active or halted");
        assetPool.claimAsset(user2);
        vm.expectRevert("Pool not active or halted");
        assetPool.claimReserve(user2);
        vm.stopPrank();
        
        // Complete rebalance with LPs
        vm.startPrank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, INITIAL_PRICE);
        vm.stopPrank();
        
        vm.startPrank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, INITIAL_PRICE);
        vm.stopPrank();
        
        // Pool should be active again
        assertTrue(_isPoolActive(), "Pool should be active after rebalance");
    }


    /**
     * @notice Helper function to check if pool is active
     * @return True if pool is in active state
     */
    function _isPoolActive() internal view returns (bool) {
        return cycleManager.cycleState() == IPoolCycleManager.CycleState.POOL_ACTIVE;
    }

}