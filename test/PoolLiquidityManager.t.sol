// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "./utils/ProtocolTestUtils.sol";

/**
 * @title PoolLiquidityManagerTest
 * @notice Unit tests for the PoolLiquidityManager contract focusing on LP management,
 * @notice liquidity addition/reduction, collateral management, and interest claims
 */
contract PoolLiquidityManagerTest is ProtocolTestUtils {
    // Base amounts (will be adjusted based on token decimals)
    uint256 constant INITIAL_PRICE = 100 * 1e18; // $100.00 per asset (always 18 decimals)
    uint256 constant USER_INITIAL_BALANCE = 100_000; 
    uint256 constant LP_INITIAL_BALANCE = 1_000_000;
    uint256 constant LP_LIQUIDITY_AMOUNT = 500_000;
    
    // Test LP amounts
    uint256 constant SMALL_LIQUIDITY = 10_000;
    uint256 constant MEDIUM_LIQUIDITY = 100_000;
    uint256 constant LARGE_LIQUIDITY = 500_000;
    
    // Collateral ratios
    uint256 constant COLLATERAL_RATIO = 30; // 30% for LPs

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

    // ==================== LP REGISTRATION TESTS ====================

    /**
     * @notice Test adding a new LP through the liquidity addition process
     */
    function testAddNewLP() public {
        address newLP = makeAddr("newLP");
        uint256 liquidityAmount = adjustAmountForDecimals(MEDIUM_LIQUIDITY, 6);
        
        // Fund the new LP with tokens
        reserveToken.mint(newLP, liquidityAmount * 2);
        
        // Approve tokens
        vm.startPrank(newLP);
        reserveToken.approve(address(liquidityManager), type(uint256).max);
        vm.stopPrank();
        
        // Verify LP not registered initially
        assertFalse(liquidityManager.isLP(newLP), "LP should not be registered initially");
        
        // Calculate expected collateral based on strategy
        (uint256 healthyRatio, ,) = poolStrategy.getLPLiquidityParams();
        uint256 expectedCollateral = (liquidityAmount * healthyRatio) / BPS;
        
        // Add liquidity to register LP
        vm.startPrank(newLP);
        liquidityManager.addLiquidity(liquidityAmount);
        vm.stopPrank();
        
        // Verify LP is now registered
        assertTrue(liquidityManager.isLP(newLP), "LP should be registered after adding liquidity");
        assertEq(liquidityManager.getLPCount(), 3, "LP count should increase to 3");
        
        // Verify LP has pending liquidity request
        IPoolLiquidityManager.LPRequest memory request = liquidityManager.getLPRequest(newLP);
        assertEq(uint(request.requestType), uint(IPoolLiquidityManager.RequestType.ADD_LIQUIDITY), "Request type should be ADD_LIQUIDITY");
        assertEq(request.requestAmount, liquidityAmount, "Request amount should match liquidity amount");
        
        // Verify collateral amount
        IPoolLiquidityManager.LPPosition memory position = liquidityManager.getLPPosition(newLP);
        assertEq(position.collateralAmount, expectedCollateral, "Collateral amount should match expected amount");
        
        // Complete a cycle to process the liquidity request
        completeCycleWithPriceChange(INITIAL_PRICE);

        vm.startPrank(newLP);
        cycleManager.rebalancePool(newLP, INITIAL_PRICE);
        vm.stopPrank();
        
        // Verify LP position after cycle
        position = liquidityManager.getLPPosition(newLP);
        assertEq(position.liquidityCommitment, liquidityAmount, "Liquidity commitment should match added amount");
        assertEq(position.collateralAmount, expectedCollateral, "Collateral should remain the same");
    }
    
    /**
     * @notice Test LP count tracking
     */
    function testLPCount() public {
        // Initialize additional LPs
        address newLP1 = makeAddr("newLP1");
        address newLP2 = makeAddr("newLP2");
        uint256 liquidityAmount = adjustAmountForDecimals(SMALL_LIQUIDITY, 6);
        
        // Fund new LPs
        reserveToken.mint(newLP1, liquidityAmount * 2);
        reserveToken.mint(newLP2, liquidityAmount * 2);
        
        // Approve tokens
        vm.startPrank(newLP1);
        reserveToken.approve(address(liquidityManager), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(newLP2);
        reserveToken.approve(address(liquidityManager), type(uint256).max);
        vm.stopPrank();
        
        // Initial LP count should be 2 (from setup)
        assertEq(liquidityManager.getLPCount(), 2, "Initial LP count should be 2");
        
        // Add first new LP
        vm.startPrank(newLP1);
        liquidityManager.addLiquidity(liquidityAmount);
        vm.stopPrank();
        
        assertEq(liquidityManager.getLPCount(), 3, "LP count should increase to 3");
        
        // Add second new LP
        vm.startPrank(newLP2);
        liquidityManager.addLiquidity(liquidityAmount);
        vm.stopPrank();
        
        assertEq(liquidityManager.getLPCount(), 4, "LP count should increase to 4");
        
        // Complete a cycle to process the liquidity requests
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // Verify LP count remains correct after cycle
        assertEq(liquidityManager.getLPCount(), 4, "LP count should remain 4 after cycle");
    }

    // ==================== LIQUIDITY ADDITION TESTS ====================

    /**
     * @notice Test liquidity addition functionality
     */
    function testAddLiquidity() public {
        uint256 liquidityAmount = adjustAmountForDecimals(MEDIUM_LIQUIDITY, 6);
        
        uint256 initialBalance = reserveToken.balanceOf(liquidityProvider1);
        uint256 initialTotalCommitted = liquidityManager.totalLPLiquidityCommited();
        uint256 initialCycleAmount = liquidityManager.cycleTotalAddLiquidityAmount();
        
        // Add liquidity
        vm.startPrank(liquidityProvider1);
        liquidityManager.addLiquidity(liquidityAmount);
        vm.stopPrank();
        
        // Verify request state
        IPoolLiquidityManager.LPRequest memory request = liquidityManager.getLPRequest(liquidityProvider1);
        
        // Get collateral requirement
        (uint256 healthyRatio, ,) = poolStrategy.getLPLiquidityParams();
        uint256 expectedCollateral = (liquidityAmount * healthyRatio) / BPS;
        
        // Assert request data
        assertEq(uint(request.requestType), uint(IPoolLiquidityManager.RequestType.ADD_LIQUIDITY), "Request type should be ADD_LIQUIDITY");
        assertEq(request.requestAmount, liquidityAmount, "Request amount should match liquidity amount");
        assertEq(request.requestCycle, cycleManager.cycleIndex(), "Request cycle should match current cycle");
        
        // Assert collateral is added correctly
        IPoolLiquidityManager.LPPosition memory position = liquidityManager.getLPPosition(liquidityProvider1);
        assertTrue(position.collateralAmount >= expectedCollateral, "Collateral should increase by expected amount");
        
        // Assert balances
        assertEq(reserveToken.balanceOf(liquidityProvider1), initialBalance - expectedCollateral, "LP balance should decrease by collateral amount");
        
        // Assert cycle total amounts
        assertEq(liquidityManager.cycleTotalAddLiquidityAmount(), initialCycleAmount + liquidityAmount, "Cycle total add liquidity should increase");
        
        // Total committed doesn't change until end of cycle
        assertEq(liquidityManager.totalLPLiquidityCommited(), initialTotalCommitted, "Total committed should not change yet");
        
        // Complete a cycle to process the liquidity request
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // Verify position after cycle
        position = liquidityManager.getLPPosition(liquidityProvider1);
        assertTrue(position.liquidityCommitment > 0, "Liquidity commitment should be non-zero after cycle");
        
        // Verify total LP liquidity increased
        assertTrue(liquidityManager.totalLPLiquidityCommited() > initialTotalCommitted, "Total committed should increase after cycle");
    }
    
    /**
     * @notice Test adding liquidity when a request is already pending
     */
    function testAddLiquidityWithPendingRequest() public {
        uint256 liquidityAmount = adjustAmountForDecimals(SMALL_LIQUIDITY, 6);
        
        // First liquidity addition
        vm.startPrank(liquidityProvider1);
        liquidityManager.addLiquidity(liquidityAmount);
        
        // Second liquidity addition should fail
        vm.expectRevert(IPoolLiquidityManager.RequestPending.selector);
        liquidityManager.addLiquidity(liquidityAmount);
        vm.stopPrank();
    }
    
    /**
     * @notice Test adding liquidity with zero amount
     */
    function testAddLiquidityZeroAmount() public {
        vm.startPrank(liquidityProvider1);
        vm.expectRevert(IPoolLiquidityManager.InvalidAmount.selector);
        liquidityManager.addLiquidity(0);
        vm.stopPrank();
    }

    // ==================== LIQUIDITY REDUCTION TESTS ====================

    /**
     * @notice Test basic liquidity reduction functionality
     */
    function testReduceLiquidity() public {
        // First ensure the LP has significant liquidity commitment
        IPoolLiquidityManager.LPPosition memory initialPosition = liquidityManager.getLPPosition(liquidityProvider1);
        uint256 initialLiquidityCommitment = initialPosition.liquidityCommitment;
        require(initialLiquidityCommitment > 0, "LP should have liquidity commitment");
        
        uint256 reductionAmount = initialLiquidityCommitment / 2;
        uint256 initialCycleReduction = liquidityManager.cycleTotalReduceLiquidityAmount();
        
        // Request liquidity reduction
        vm.startPrank(liquidityProvider1);
        liquidityManager.reduceLiquidity(reductionAmount);
        vm.stopPrank();
        
        // Verify request state
        IPoolLiquidityManager.LPRequest memory request = liquidityManager.getLPRequest(liquidityProvider1);
        
        // Assert request data
        assertEq(uint(request.requestType), uint(IPoolLiquidityManager.RequestType.REDUCE_LIQUIDITY), "Request type should be REDUCE_LIQUIDITY");
        assertEq(request.requestAmount, reductionAmount, "Request amount should match reduction amount");
        assertEq(request.requestCycle, cycleManager.cycleIndex(), "Request cycle should match current cycle");
        
        // Verify cycle reduction amount increased
        assertEq(liquidityManager.cycleTotalReduceLiquidityAmount(), initialCycleReduction + reductionAmount, "Cycle total reduction should increase");
        
        // Complete a cycle to process the liquidity request
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // Verify liquidity commitment decreased
        IPoolLiquidityManager.LPPosition memory finalPosition = liquidityManager.getLPPosition(liquidityProvider1);
        assertEq(finalPosition.liquidityCommitment, initialLiquidityCommitment - reductionAmount, "Liquidity commitment should decrease by reduction amount");
    }
    
    /**
     * @notice Test reducing more liquidity than LP has committed
     */
    function testReduceLiquidityExcessive() public {
        IPoolLiquidityManager.LPPosition memory position = liquidityManager.getLPPosition(liquidityProvider1);
        uint256 excessiveAmount = position.liquidityCommitment + 1;
        
        vm.startPrank(liquidityProvider1);
        vm.expectRevert(IPoolLiquidityManager.InvalidAmount.selector);
        liquidityManager.reduceLiquidity(excessiveAmount);
        vm.stopPrank();
    }
    
    /**
     * @notice Test reducing liquidity when a request is already pending
     */
    function testReduceLiquidityWithPendingRequest() public {
        IPoolLiquidityManager.LPPosition memory position = liquidityManager.getLPPosition(liquidityProvider1);
        uint256 reductionAmount = position.liquidityCommitment / 2;
        
        // First reduction request
        vm.startPrank(liquidityProvider1);
        liquidityManager.reduceLiquidity(reductionAmount);
        
        // Second reduction request should fail
        vm.expectRevert(IPoolLiquidityManager.RequestPending.selector);
        liquidityManager.reduceLiquidity(reductionAmount);
        vm.stopPrank();
    }
    
    /**
     * @notice Test reducing liquidity with zero amount
     */
    function testReduceLiquidityZeroAmount() public {
        vm.startPrank(liquidityProvider1);
        vm.expectRevert(IPoolLiquidityManager.InvalidAmount.selector);
        liquidityManager.reduceLiquidity(0);
        vm.stopPrank();
    }

    // ==================== COLLATERAL MANAGEMENT TESTS ====================

    /**
     * @notice Test adding collateral to LP position
     */
    function testAddCollateral() public {
        uint256 collateralAmount = adjustAmountForDecimals(SMALL_LIQUIDITY, 6);
        
        IPoolLiquidityManager.LPPosition memory initialPosition = liquidityManager.getLPPosition(liquidityProvider1);
        uint256 initialCollateral = initialPosition.collateralAmount;
        uint256 initialBalance = reserveToken.balanceOf(liquidityProvider1);
        uint256 initialTotalCollateral = liquidityManager.totalLPCollateral();
        
        // Add collateral
        vm.startPrank(liquidityProvider1);
        liquidityManager.addCollateral(liquidityProvider1, collateralAmount);
        vm.stopPrank();
        
        // Verify collateral increased
        IPoolLiquidityManager.LPPosition memory finalPosition = liquidityManager.getLPPosition(liquidityProvider1);
        assertEq(finalPosition.collateralAmount, initialCollateral + collateralAmount, "Collateral should increase by added amount");
        
        // Verify balance decreased
        assertEq(reserveToken.balanceOf(liquidityProvider1), initialBalance - collateralAmount, "Balance should decrease by collateral amount");
        
        // Verify total collateral increased
        assertEq(liquidityManager.totalLPCollateral(), initialTotalCollateral + collateralAmount, "Total collateral should increase");
        
        // Verify event emitted
        // Note: In a real test would verify event emission with expectEmit
    }
    
    /**
     * @notice Test adding collateral to a non-LP address
     */
    function testAddCollateralToNonLP() public {
        address nonLP = makeAddr("nonLP");
        uint256 collateralAmount = adjustAmountForDecimals(SMALL_LIQUIDITY, 6);
        
        reserveToken.mint(nonLP, collateralAmount * 2);
        
        vm.startPrank(nonLP);
        reserveToken.approve(address(liquidityManager), type(uint256).max);
        
        // Adding collateral to a non-LP should still work (it's a way to add initial collateral)
        liquidityManager.addCollateral(nonLP, collateralAmount);
        vm.stopPrank();
        
        // Check collateral was added but user is not registered as LP
        IPoolLiquidityManager.LPPosition memory position = liquidityManager.getLPPosition(nonLP);
        assertEq(position.collateralAmount, collateralAmount, "Collateral should be added even for non-LP");
        assertFalse(liquidityManager.isLP(nonLP), "Address should not be registered as LP");
    }
    
    /**
     * @notice Test reducing collateral from LP position
     */
    function testReduceCollateral() public {
        // First add extra collateral to ensure there's excess
        uint256 additionalCollateral = adjustAmountForDecimals(MEDIUM_LIQUIDITY, 6);
        
        vm.startPrank(liquidityProvider1);
        liquidityManager.addCollateral(liquidityProvider1, additionalCollateral);
        
        // Get position after adding collateral
        IPoolLiquidityManager.LPPosition memory initialPosition = liquidityManager.getLPPosition(liquidityProvider1);
        uint256 initialCollateral = initialPosition.collateralAmount;
        uint256 initialBalance = reserveToken.balanceOf(liquidityProvider1);
        
        // Calculate required collateral
        uint256 requiredCollateral = poolStrategy.calculateLPRequiredCollateral(address(liquidityManager), liquidityProvider1);
        uint256 excessCollateral = initialCollateral - requiredCollateral;
        
        // Should have excess collateral
        assertTrue(excessCollateral > 0, "Should have excess collateral");
        
        // Reduce some of the excess collateral
        uint256 reductionAmount = excessCollateral / 2;
        liquidityManager.reduceCollateral(reductionAmount);
        vm.stopPrank();
        
        // Verify collateral decreased
        IPoolLiquidityManager.LPPosition memory finalPosition = liquidityManager.getLPPosition(liquidityProvider1);
        assertEq(finalPosition.collateralAmount, initialCollateral - reductionAmount, "Collateral should decrease by reduction amount");
        
        // Verify balance increased
        assertTrue(reserveToken.balanceOf(liquidityProvider1) > initialBalance, "Balance should increase after reducing collateral");
        
        // Note: actual amount returned may include yield so we don't check exact amount
    }
    
    /**
     * @notice Test reducing more collateral than allowed (below required)
     */
    function testReduceCollateralExcessive() public {
        IPoolLiquidityManager.LPPosition memory position = liquidityManager.getLPPosition(liquidityProvider1);
        uint256 initialCollateral = position.collateralAmount;

        vm.startPrank(liquidityProvider1);
        vm.expectRevert(IPoolLiquidityManager.InvalidWithdrawalAmount.selector);
        liquidityManager.reduceCollateral(initialCollateral + 10);
        vm.stopPrank();
        
        // First add extra collateral to ensure there's excess
        uint256 additionalCollateral = adjustAmountForDecimals(MEDIUM_LIQUIDITY, 6);
        vm.startPrank(liquidityProvider1);
        liquidityManager.addCollateral(liquidityProvider1, additionalCollateral);
        initialCollateral += additionalCollateral;
        vm.stopPrank();

        // Calculate required collateral
        uint256 requiredCollateral = poolStrategy.calculateLPRequiredCollateral(address(liquidityManager), liquidityProvider1);
        // Try to reduce to below required
        uint256 excessiveReduction = initialCollateral - requiredCollateral + 1;
        
        vm.startPrank(liquidityProvider1);
        vm.expectRevert(IPoolLiquidityManager.InsufficientCollateral.selector);
        liquidityManager.reduceCollateral(excessiveReduction);
        vm.stopPrank();
    }
    
    /**
     * @notice Test reducing more collateral than LP has
     */
    function testReduceCollateralMoreThanBalance() public {
        IPoolLiquidityManager.LPPosition memory position = liquidityManager.getLPPosition(liquidityProvider1);
        uint256 excessiveAmount = position.collateralAmount + 1;
        
        vm.startPrank(liquidityProvider1);
        vm.expectRevert(IPoolLiquidityManager.InvalidWithdrawalAmount.selector);
        liquidityManager.reduceCollateral(excessiveAmount);
        vm.stopPrank();
    }

    // ==================== INTEREST CLAIM TESTS ====================
    
    /**
     * @notice Test claiming interest
     * @dev This test simulates interest accrual by having the AssetPool add interest to the LP
     */
    function testClaimInterest() public {
        // Use asset pool to add interest to LP position
        uint256 interestAmount = adjustAmountForDecimals(SMALL_LIQUIDITY, 6);
        
        // Initial state
        IPoolLiquidityManager.LPPosition memory initialPosition = liquidityManager.getLPPosition(liquidityProvider1);
        uint256 initialBalance = reserveToken.balanceOf(liquidityProvider1);
        
        // Add interest to LP position (only asset pool can call this)
        vm.startPrank(address(assetPool));
        liquidityManager.addToInterest(liquidityProvider1, interestAmount);
        vm.stopPrank();
        
        // Verify interest was added to position
        IPoolLiquidityManager.LPPosition memory positionWithInterest = liquidityManager.getLPPosition(liquidityProvider1);
        assertEq(positionWithInterest.interestAccrued, initialPosition.interestAccrued + interestAmount, 
            "Interest accrued should increase by added amount");
        
        // Claim interest
        vm.startPrank(liquidityProvider1);
        liquidityManager.claimInterest();
        vm.stopPrank();
        
        // Verify interest was claimed
        IPoolLiquidityManager.LPPosition memory finalPosition = liquidityManager.getLPPosition(liquidityProvider1);
        assertEq(finalPosition.interestAccrued, 0, "Interest accrued should be zero after claiming");
        
        // Verify balance increased
        assertTrue(reserveToken.balanceOf(liquidityProvider1) > initialBalance, "Balance should increase after claiming interest");
        
        // Note: actual amount returned may include yield so we don't check exact amount
    }
    
    /**
     * @notice Test claiming interest when no interest is accrued
     */
    function testClaimInterestNoInterest() public {
        // Ensure LP has no interest accrued
        IPoolLiquidityManager.LPPosition memory position = liquidityManager.getLPPosition(liquidityProvider1);
        if (position.interestAccrued > 0) {
            // If there is interest, claim it first
            vm.startPrank(liquidityProvider1);
            liquidityManager.claimInterest();
            vm.stopPrank();
        }
        
        // Verify no interest accrued
        position = liquidityManager.getLPPosition(liquidityProvider1);
        assertEq(position.interestAccrued, 0, "Should have no interest accrued");
        
        // Attempt to claim interest again
        vm.startPrank(liquidityProvider1);
        vm.expectRevert(IPoolLiquidityManager.NoInterestAccrued.selector);
        liquidityManager.claimInterest();
        vm.stopPrank();
    }
    
    /**
     * @notice Helper to check if a pool is active
     * @return True if pool is in active state
     */
    function _isPoolActive() internal view returns (bool) {
        return cycleManager.cycleState() == IPoolCycleManager.CycleState.POOL_ACTIVE;
    }
}