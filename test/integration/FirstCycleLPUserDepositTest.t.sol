// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "../utils/ProtocolTestUtils.sol";

/**
 * @title FirstCycleLPUserDepositTest
 * @notice Integration test for LP liquidity addition and User deposits in the first cycle
 * @dev Tests the specific scenario where a User makes a deposit request in the same cycle
 *      when an LP adds liquidity for the first time, focusing on available liquidity calculations
 */
contract FirstCycleLPUserDepositTest is ProtocolTestUtils {
    // Test constants
    uint256 constant INITIAL_PRICE = 100 * 1e18; // $100.00 per asset
    uint256 constant USER_INITIAL_BALANCE = 100_000; 
    uint256 constant LP_INITIAL_BALANCE = 1_000_000;
    uint256 constant LP_LIQUIDITY_AMOUNT = 500_000;
    uint256 constant USER_DEPOSIT_AMOUNT = 50_000; // 50k deposit
    uint256 constant COLLATERAL_RATIO = 20; // 20% collateral

    // Test actors
    address public newLP;
    address public newUser;

    function setUp() public {
        // Create fresh test accounts
        newLP = makeAddr("newLP");
        newUser = makeAddr("newUser");
        
        // We'll set up the protocol manually to test the first cycle scenario
        deployProtocol("xTEST", "xTEST", 6);
        
        // Fund the new LP and user
        uint256 lpAmount = adjustAmountForDecimals(LP_INITIAL_BALANCE, 6);
        uint256 userAmount = adjustAmountForDecimals(USER_INITIAL_BALANCE, 6);
        
        reserveToken.mint(newLP, lpAmount);
        reserveToken.mint(newUser, userAmount);
        
        // Approve tokens
        vm.startPrank(newLP);
        reserveToken.approve(address(liquidityManager), type(uint256).max);
        reserveToken.approve(address(cycleManager), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(newUser);
        reserveToken.approve(address(assetPool), type(uint256).max);
        assetToken.approve(address(assetPool), type(uint256).max);
        vm.stopPrank();
        
        // Set initial oracle price
        updateOraclePrice(INITIAL_PRICE);
    }

    /**
     * @notice Test that a user can make a deposit request in the same cycle when an LP adds liquidity for the first time
     * @dev This tests the core question about available liquidity calculations in the first cycle
     */
    function testUserDepositInFirstCycleLPLiquidity() public {
        // Verify we're starting with no committed liquidity
        assertEq(liquidityManager.totalLPLiquidityCommited(), 0, "Should start with zero committed liquidity");
        assertEq(liquidityManager.getCycleTotalLiquidityCommited(), 0, "Should start with zero cycle liquidity");
        
        uint256 initialCycleIndex = cycleManager.cycleIndex();
        uint256 lpLiquidityAmount = adjustAmountForDecimals(LP_LIQUIDITY_AMOUNT, 6);
        uint256 userDepositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 userCollateralAmount = (userDepositAmount * COLLATERAL_RATIO) / 100;
        
        // Step 1: New LP adds liquidity (first time)
        vm.startPrank(newLP);
        liquidityManager.addLiquidity(lpLiquidityAmount);
        vm.stopPrank();
        
        // Verify LP is registered and has pending liquidity
        assertTrue(liquidityManager.isLP(newLP), "LP should be registered after adding liquidity");
        assertEq(liquidityManager.cycleTotalAddLiquidityAmount(), lpLiquidityAmount, "Cycle add liquidity should track pending LP addition");
        
        // Verify cycle total liquidity includes pending LP addition
        assertEq(liquidityManager.getCycleTotalLiquidityCommited(), lpLiquidityAmount, "Cycle total should include pending LP liquidity");
        
        // Step 2: Check available liquidity from strategy perspective
        uint256 availableLiquidity = poolStrategy.calculateCycleAvailableLiquidity(address(assetPool));
        assertEq(availableLiquidity, lpLiquidityAmount, "Available liquidity should equal pending LP addition");
        assertGe(availableLiquidity, userDepositAmount, "Available liquidity should be sufficient for user deposit");
        
        // Step 3: User makes deposit request in the same cycle
        vm.startPrank(newUser);
        assetPool.depositRequest(userDepositAmount, userCollateralAmount);
        vm.stopPrank();
        
        // Verify user request was accepted
        (IAssetPool.RequestType reqType, uint256 reqAmount, , uint256 reqCycle) = 
            assetPool.userRequests(newUser);

        (, , uint256 posCollateral) = assetPool.userPositions(newUser);
        
        assertEq(uint(reqType), uint(IAssetPool.RequestType.DEPOSIT), "User should have a pending deposit request");
        assertEq(reqAmount, userDepositAmount, "Request amount should match user deposit");
        assertEq(posCollateral, userCollateralAmount, "Request collateral should match user collateral");
        assertEq(reqCycle, initialCycleIndex, "Request should be in the same cycle as LP addition");
        
        // Verify cycle totals are updated correctly
        assertEq(assetPool.cycleTotalDeposits(), userDepositAmount, "Cycle deposits should track user request");
        
        // Step 4: Complete the cycle to process both requests
        _completeCycleProcessingBothRequests();
        
        // Step 5: Verify both LP and User requests were processed successfully
        _verifyPostCycleState(lpLiquidityAmount, userDepositAmount);
    }

    /**
     * @notice Test that an LP adds liquidity which also adds collateral to the pool
     * The LP should not be able to reduce collateral until the cycle is completed
     */
    function testLPAddLiquidityAddsCollateral() public {
        // Step 1: New LP adds liquidity (first time)
        vm.startPrank(newLP);
        liquidityManager.addLiquidity(LP_LIQUIDITY_AMOUNT);
        vm.stopPrank();

        // LP should not be able to reduce collateral until the cycle is completed
        uint256 initialCollateral = liquidityManager.getLPPosition(newLP).collateralAmount;
        vm.startPrank(newLP);
        vm.expectRevert(IPoolLiquidityManager.InvalidCycleState.selector);
        liquidityManager.reduceCollateral(initialCollateral);
        vm.stopPrank();
    }

    /**
     * @notice Test that an LP adds liquidity in first cycle and then cycle rebalances and moves to next cycle
     * The LP should not be able to reduce collateral after the cycle is completed because that would reduce the collateral health to 1
     */
    function testLPAddLiquidityInFirstCycleAndCycleRebalances() public {
        // Step 1: New LP adds liquidity (first time)
        vm.startPrank(newLP);
        liquidityManager.addLiquidity(LP_LIQUIDITY_AMOUNT);
        vm.stopPrank();

        // Complete the cycle to process the liquidity request
        _completeCycleProcessingBothRequests();

        // LP should not be able to reduce collateral after the cycle is completed because the collateral health is 1
        uint256 initialCollateral = liquidityManager.getLPPosition(newLP).collateralAmount;
        vm.startPrank(newLP);
        vm.expectRevert(IPoolLiquidityManager.InsufficientCollateral.selector);
        liquidityManager.reduceCollateral(initialCollateral);
        vm.stopPrank();
    }

    /**
     * @notice Test that an LP adds liquidity in first cycle and then cycle rebalances and moves to next cycle
     * LP adds liquidity in the next cycle and tries to reduce collateral which should revert because that would reduce the collateral health to 1
     */
    function testLPAddLiquidityInNextCycleAndCycleRebalances() public {
        // Step 1: New LP adds liquidity (first time)
        vm.startPrank(newLP);
        liquidityManager.addLiquidity(LP_LIQUIDITY_AMOUNT);
        vm.stopPrank();

        // Complete the cycle to process the liquidity request
        _completeCycleProcessingBothRequests();

        uint256 collateralC0 = liquidityManager.getLPPosition(newLP).collateralAmount;

        // Step 2: LP adds liquidity in the next cycle
        vm.startPrank(newLP);
        liquidityManager.addLiquidity(LP_LIQUIDITY_AMOUNT);
        vm.stopPrank();

        // Step 3: LP tries to reduce collateral which should revert because the collateral health is 1
        vm.startPrank(newLP);
        vm.expectRevert(IPoolLiquidityManager.InsufficientCollateral.selector);
        liquidityManager.reduceCollateral(collateralC0);
    }

    /**
     * @notice Test that an LP adds liquidity in first cycle and then cycle rebalances and moves to next cycle
     * LP adds liquidity in the next cycle + adds collateral to the pool
     * LP should be able to reduce the extra collateral because that would not reduce the collateral health to 1
     */
    function testLPAddLiquidityInNextCycleAndCycleRebalancesAndReduceExtraCollateral() public {
        uint256 EXTRA_COLLATERAL = 100_000;
        // Step 1: New LP adds liquidity (first time)
        vm.startPrank(newLP);
        liquidityManager.addLiquidity(LP_LIQUIDITY_AMOUNT);
        vm.stopPrank();

        // Complete the cycle to process the liquidity request
        _completeCycleProcessingBothRequests();

        uint256 lpCollateralBefore = liquidityManager.getLPPosition(newLP).collateralAmount;

        // LP should be able to reduce the extra collateral because that would not reduce the collateral health to 1
        vm.startPrank(newLP);
        liquidityManager.addCollateral(newLP, EXTRA_COLLATERAL);
        uint256 lpColAfterAddCollateral = liquidityManager.getLPPosition(newLP).collateralAmount;
        assertEq(lpColAfterAddCollateral, lpCollateralBefore + EXTRA_COLLATERAL, "LP collateral should be updated");
        liquidityManager.reduceCollateral(EXTRA_COLLATERAL);
        uint256 lpColAfterReduceCollateral = liquidityManager.getLPPosition(newLP).collateralAmount;
        assertEq(lpColAfterReduceCollateral, lpCollateralBefore, "LP collateral should be reduced");
        vm.stopPrank();

        // Verify the extra collateral is reduced
        assertEq(lpColAfterAddCollateral - lpColAfterReduceCollateral, EXTRA_COLLATERAL, "Extra collateral should be reduced");
        // Verify the total collateral is updated
        assertEq(liquidityManager.totalLPCollateral(), lpCollateralBefore, "Total collateral should be updated");
    }

    // ==================== HELPER FUNCTIONS ====================

    /**
     * @notice Complete cycle by processing both LP and user requests
     */
    function _completeCycleProcessingBothRequests() internal {
        // Initiate offchain rebalance
        vm.startPrank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INITIAL_PRICE);
        cycleManager.initiateOffchainRebalance();
        vm.stopPrank();

        // Close market to trigger onchain rebalance
        vm.startPrank(owner);
        assetOracle.setMarketOpen(false);
        updateOraclePrice(INITIAL_PRICE);
        cycleManager.initiateOnchainRebalance();
        vm.stopPrank();
         
        // Process LP rebalance
        vm.startPrank(newLP);
        cycleManager.rebalancePool(newLP, INITIAL_PRICE);
        vm.stopPrank();
        
        // Verify pool is back to active state
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_ACTIVE), 
                "Pool should be active after cycle completion");
    }

    /**
     * @notice Verify post-cycle state for both LP and user
     */
    function _verifyPostCycleState(uint256 expectedLPLiquidity, uint256 expectedUserDeposit) internal {
        // Verify LP state
        IPoolLiquidityManager.LPPosition memory lpPosition = liquidityManager.getLPPosition(newLP);
        assertEq(lpPosition.liquidityCommitment, expectedLPLiquidity, 
                "LP should have committed the liquidity after cycle");
        assertGt(lpPosition.collateralAmount, 0, "LP should have collateral");
        
        // Verify total committed liquidity is updated
        assertEq(liquidityManager.totalLPLiquidityCommited(), expectedLPLiquidity, 
                "Total committed should equal LP liquidity");
        
        // Verify cycle amounts are reset
        assertEq(liquidityManager.cycleTotalAddLiquidityAmount(), 0, 
                "Cycle add liquidity should be reset");
        assertEq(assetPool.cycleTotalDeposits(), 0, "Cycle deposits should be reset");
        
        // User should be able to claim assets
        vm.startPrank(newUser);
        assetPool.claimAsset(newUser);
        vm.stopPrank();
        
        // Verify user received asset tokens
        uint256 expectedAssetAmount = _convertReserveToAsset(expectedUserDeposit, INITIAL_PRICE);
        uint256 actualAssetAmount = assetToken.balanceOf(newUser);
        assertEq(actualAssetAmount, expectedAssetAmount, "User should receive correct amount of asset tokens");
        
        // Verify user position is updated
        (uint256 assetAmount, uint256 depositAmount, uint256 collateralAmount) = assetPool.userPositions(newUser);
        assertEq(assetAmount, expectedAssetAmount, "User position asset amount should be correct");
        assertEq(depositAmount, expectedUserDeposit, "User position deposit amount should be correct");
        assertEq(collateralAmount, (expectedUserDeposit * COLLATERAL_RATIO) / 100, 
                "User position collateral amount should be correct");
    }

    /**
     * @notice Helper to convert reserve amount to asset amount using price
     */
    function _convertReserveToAsset(uint256 reserveAmount, uint256 price) internal view returns (uint256) {
        return (reserveAmount * assetPool.reserveToAssetDecimalFactor() * 1e18) / price;
    }
}
