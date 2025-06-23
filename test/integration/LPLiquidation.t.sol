// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "../utils/ProtocolTestUtils.sol";

/**
 * @title LPLiquidationTest
 * @notice Unit tests for the LP liquidation functionality in the protocol
 * @dev Tests various liquidation scenarios, requests, executions, and edge cases
 */
contract LPLiquidationTest is ProtocolTestUtils {
    // Base amounts (will be adjusted based on token decimals)
    uint256 constant INITIAL_PRICE = 100 * 1e18; // $100.00 per asset (always 18 decimals)
    uint256 constant INCREASED_PRICE = 130 * 1e18; // $130.00 (30% increase)
    uint256 constant INCREASED_PRICE_2 = 145 * 1e18; // $145.00 (> 10% increase)
    uint256 constant USER_INITIAL_BALANCE = 1_000_000;
    uint256 constant LP_INITIAL_BALANCE = 1_000_000;
    uint256 constant LP_LIQUIDITY_AMOUNT = 500_000;
    uint256 constant USER_DEPOSIT_AMOUNT = 600_000;
    
    // LP test amounts
    uint256 constant LP_HEALTHY_COLLATERAL_RATIO = 3000; // 30% for LPs
    uint256 constant LP_LIQUIDATION_THRESHOLD = 2500; // 25% for LPs
    
    // Test accounts
    address public liquidator;
    address public liquidator2;

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
        
        // Set up additional test accounts
        liquidator = makeAddr("liquidator");
        liquidator2 = makeAddr("liquidator2");
        
        // Create substantial user deposits to generate asset value
        vm.startPrank(user1);
        assetPool.depositRequest(
            adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6),
            adjustAmountForDecimals(USER_DEPOSIT_AMOUNT * 20 / 100, 6) // 20% collateral
        );
        vm.stopPrank();
        
        // Complete one cycle to process deposits and mint assets
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // Claim assets
        vm.prank(user1);
        assetPool.claimAsset(user1);
    }

    // ==================== LIQUIDATION SETUP TESTS ====================

    /**
     * @notice Test setup for a liquidatable LP
     * @dev This function simulates a scenario where an LP becomes liquidatable
     */
    function testSetupLiquidatableLP() public {
        // Get LP's initial position
        uint8 initialHealth = poolStrategy.getLPLiquidityHealth(address(liquidityManager), liquidityProvider1);
        
        // Verify LP is initially healthy
        assertEq(initialHealth, 3, "LP should start with healthy collateral ratio");
        
        // Start the rebalance process with increased price
        vm.startPrank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INCREASED_PRICE);
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to onchain rebalancing phase
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        assetOracle.setMarketOpen(false);
        updateOraclePrice(INCREASED_PRICE);
        cycleManager.initiateOnchainRebalance();
        vm.stopPrank();
        
        // Complete rebalance for liquidityProvider2 (who is healthy)
        vm.startPrank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, INCREASED_PRICE);
        vm.stopPrank();
        
        // Use rebalanceLP for them instead (settlement)
        vm.warp(block.timestamp + REBALANCE_LENGTH + 100);
        vm.startPrank(owner);
        cycleManager.rebalanceLP(liquidityProvider1);
        vm.stopPrank();
        
        // Check if LP is now liquidatable
        uint8 finalHealth = poolStrategy.getLPLiquidityHealth(address(liquidityManager), liquidityProvider1);
        assertTrue(finalHealth == 1, "LP should be liquidatable after price increase");
    }

    // ==================== LIQUIDATION REQUEST TESTS ====================

    /**
     * @notice Test basic LP liquidation request
     */
    function testLiquidationRequest() public {
        // Setup liquidatable LP
        testSetupLiquidatableLP();
        
        // Get LP's commitment to determine liquidation amount
        IPoolLiquidityManager.LPPosition memory position = liquidityManager.getLPPosition(liquidityProvider1);
        uint256 lpCommitment = position.liquidityCommitment;
        uint256 liquidationAmount = lpCommitment * 30 / 100; // 30% of position
        
        // Submit liquidation request
        vm.startPrank(liquidator);
        liquidityManager.liquidateLP(liquidityProvider1, liquidationAmount);
        vm.stopPrank();
        
        // Verify liquidation request state
        IPoolLiquidityManager.LPRequest memory request = liquidityManager.getLPRequest(liquidityProvider1);
        
        // Assert request data
        assertEq(uint(request.requestType), uint(IPoolLiquidityManager.RequestType.LIQUIDATE), "Request type should be LIQUIDATE");
        assertEq(request.requestAmount, liquidationAmount, "Request amount should match liquidation amount");
        assertEq(request.requestCycle, cycleManager.cycleIndex(), "Request cycle should match current cycle");
        
        // Assert liquidator is recorded
        address liquidationInitiator = liquidityManager.liquidationInitiators(liquidityProvider1);
        assertEq(liquidationInitiator, liquidator, "Liquidation initiator should be recorded");   
    }

    /**
     * @notice Test attempting to liquidate a healthy position
     */
    function testLiquidateHealthyLP() public {
        // Get LP's asset share to determine liquidation amount
        uint256 lpAssetShare = liquidityManager.getLPAssetShare(liquidityProvider2);
        uint256 liquidationAmount = lpAssetShare * 30 / 100; // 30% of LP's position
                
        // Verify LP2 is healthy
        uint8 health = poolStrategy.getLPLiquidityHealth(address(liquidityManager), liquidityProvider2);
        assertEq(health, 3, "LP2 should be healthy");
        
        // Attempt to liquidate healthy position should fail
        vm.startPrank(liquidator);
        vm.expectRevert(IPoolLiquidityManager.NotEligibleForLiquidation.selector);
        liquidityManager.liquidateLP(liquidityProvider2, liquidationAmount);
        vm.stopPrank();
    }

    /**
     * @notice Test liquidation with excessive amount (> 30% of position)
     */
    function testLiquidateExcessiveAmount() public {
        // Setup liquidatable LP
        testSetupLiquidatableLP();
        
        // Get LP's asset share to determine liquidation amount
        uint256 lpAssetShare = liquidityManager.getLPAssetShare(liquidityProvider1);
        uint256 excessiveAmount = lpAssetShare * 80 / 100; // 80% of LP's position (> 30% limit)
        
        // Attempt to liquidate with excessive amount should fail
        vm.startPrank(liquidator);
        vm.expectRevert(IPoolLiquidityManager.InvalidAmount.selector);
        liquidityManager.liquidateLP(liquidityProvider1, excessiveAmount);
        vm.stopPrank();
    }

    /**
     * @notice Test attempting to submit a second liquidation request for the same LP
     * @dev Only a single liquidation request can be active at one time for an LP
     */
    function testMultipleLiquidationRequests() public {
        // Setup liquidatable LP
        testSetupLiquidatableLP();
        
        // Get LP's commitment to determine liquidation amount
        IPoolLiquidityManager.LPPosition memory position = liquidityManager.getLPPosition(liquidityProvider1);
        uint256 lpCommitment = position.liquidityCommitment;
        uint256 firstLiquidationAmount = lpCommitment * 30 / 100; // 30% of position

        vm.startPrank(liquidator);
        liquidityManager.liquidateLP(liquidityProvider1, firstLiquidationAmount);
        vm.stopPrank();
        
        // Verify first liquidation request
        address firstInitiator = liquidityManager.liquidationInitiators(liquidityProvider1);
        assertEq(firstInitiator, liquidator, "First liquidator should be recorded");
        
        // Second liquidator attempts to liquidate the same LP
        uint256 secondAmount = lpCommitment * 15 / 100;
        
        // Should revert because there's already an active liquidation request
        vm.startPrank(liquidator2);
        vm.expectRevert(IPoolLiquidityManager.RequestPending.selector);
        liquidityManager.liquidateLP(liquidityProvider1, secondAmount);
        vm.stopPrank();
        
        // Verify first liquidator still recorded
        address currentInitiator = liquidityManager.liquidationInitiators(liquidityProvider1);
        assertEq(currentInitiator, liquidator, "First liquidator should still be recorded");
        
        // Get updated request to verify amount
        IPoolLiquidityManager.LPRequest memory request = liquidityManager.getLPRequest(liquidityProvider1);
        assertEq(request.requestAmount, firstLiquidationAmount, "Request amount should still match first liquidator's amount");
    }

    // ==================== LIQUIDATION EXECUTION TESTS ====================

    /**
     * @notice Test full liquidation execution with cycle completion
     * @dev Accounts for LPs with unhealthy collateral not being able to rebalance themselves
     */
    function testLiquidationExecution() public {
        // Setup liquidatable LP
        testSetupLiquidatableLP();
        
        // Get LP's commitment to determine liquidation amount
        IPoolLiquidityManager.LPPosition memory position = liquidityManager.getLPPosition(liquidityProvider1);
        uint256 lpCommitment = position.liquidityCommitment;
        uint256 liquidationAmount = lpCommitment * 30 / 100; // 30% of position
        
        // Get LP's initial position
        IPoolLiquidityManager.LPPosition memory initialPosition = liquidityManager.getLPPosition(liquidityProvider1);
        
        // Submit liquidation request
        vm.startPrank(liquidator);
        liquidityManager.liquidateLP(liquidityProvider1, liquidationAmount);
        vm.stopPrank();
        
        // Record liquidator's balance before execution
        uint256 liquidatorBalanceBefore = reserveToken.balanceOf(liquidator);
        
        // Start rebalance cycle with current price (no further increase needed)
        vm.startPrank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INCREASED_PRICE);
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to onchain rebalancing phase
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        assetOracle.setMarketOpen(false);
        updateOraclePrice(INCREASED_PRICE);
        cycleManager.initiateOnchainRebalance();
        vm.stopPrank();
        
        // Rebalance the healthy LP normally
        vm.startPrank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, INCREASED_PRICE);
        vm.stopPrank();
        
        // For liquidityProvider1, use rebalanceLP since they can't rebalance themselves
        vm.warp(block.timestamp + REBALANCE_LENGTH + 100);
        vm.startPrank(owner);
        cycleManager.rebalanceLP(liquidityProvider1);
        vm.stopPrank();
        
        // Verify LP's position after liquidation
        IPoolLiquidityManager.LPPosition memory finalPosition = liquidityManager.getLPPosition(liquidityProvider1);
        
        // Verify liquidity commitment is reduced
        assertEq(finalPosition.liquidityCommitment, initialPosition.liquidityCommitment - liquidationAmount, 
            "Liquidity commitment should be reduced by liquidation amount");
        
        // Verify liquidation reward was paid
        uint256 liquidatorBalanceAfter = reserveToken.balanceOf(liquidator);
        assertTrue(liquidatorBalanceAfter > liquidatorBalanceBefore, "Liquidator should receive reward");
        
        // Verify request was cleared
        IPoolLiquidityManager.LPRequest memory request = liquidityManager.getLPRequest(liquidityProvider1);
        assertEq(uint(request.requestType), uint(IPoolLiquidityManager.RequestType.NONE), "Request should be cleared after execution");
    }


    // ==================== CANCELLATION TESTS ====================

    /**
     * @notice Test cancellation of liquidation if LP adds sufficient collateral
     */
    function testLiquidationCancellation() public {
        // Setup liquidatable LP
        testSetupLiquidatableLP();
        
        IPoolLiquidityManager.LPPosition memory position = liquidityManager.getLPPosition(liquidityProvider1);
        uint256 lpCommitment = position.liquidityCommitment;
        uint256 liquidationAmount = lpCommitment * 30 / 100; // 30% of position
        
        // Submit liquidation request
        vm.startPrank(liquidator);
        liquidityManager.liquidateLP(liquidityProvider1, liquidationAmount);
        vm.stopPrank();
        
        // LP adds more collateral to become healthy again
        uint256 lpAssetValue = liquidityManager.getLPAssetHoldingValue(liquidityProvider1);
        uint256 additionalCollateral = (lpAssetValue * LP_HEALTHY_COLLATERAL_RATIO) / BPS;
        
        vm.startPrank(owner);
        reserveToken.mint(liquidityProvider1, additionalCollateral * 2); // Give LP enough tokens
        vm.stopPrank();
        
        vm.startPrank(liquidityProvider1);
        reserveToken.approve(address(liquidityManager), additionalCollateral * 2);
        liquidityManager.addCollateral(liquidityProvider1, additionalCollateral);
        vm.stopPrank();
        
        // Check health after adding collateral
        uint8 healthAfterCollateral = poolStrategy.getLPLiquidityHealth(address(liquidityManager), liquidityProvider1);
        assertEq(healthAfterCollateral, 3, "LP should be healthy after adding collateral");
        
        // Verify liquidation request was cancelled
        IPoolLiquidityManager.LPRequest memory request = liquidityManager.getLPRequest(liquidityProvider1);
        assertEq(uint(request.requestType), uint(IPoolLiquidityManager.RequestType.NONE), "Request should be cancelled");
         
        // Verify liquidation initiator was cleared
        address liquidationInitiator = liquidityManager.liquidationInitiators(liquidityProvider1);
        assertEq(liquidationInitiator, address(0), "Liquidation initiator should be cleared");
    }

    // ==================== EDGE CASE TESTS ====================

    /**
     * @notice Test liquidation when a different request type is pending
     */
    function testAddingRequestWhenLiquidatable() public {
        // Setup liquidatable LP
        testSetupLiquidatableLP();
        
        // Create a regular liquidity request for the LP
        uint256 liquidityAddAmount = 100000 * 10**6; // 100,000 units
        
        vm.startPrank(owner);
        reserveToken.mint(liquidityProvider1, liquidityAddAmount * 3);
        vm.stopPrank();
        
        vm.startPrank(liquidityProvider1);
        reserveToken.approve(address(liquidityManager), liquidityAddAmount);
        // Attempt to add liquidity while liquidatable
        vm.expectRevert();
        liquidityManager.addLiquidity(liquidityAddAmount);
        vm.stopPrank();

        // Add collateral
        vm.startPrank(liquidityProvider1);
        liquidityManager.addCollateral(liquidityProvider1, liquidityAddAmount);
        vm.stopPrank();

        // Verify LP is no longer liquidatable
        uint8 healthAfterCollateral = poolStrategy.getLPLiquidityHealth(address(liquidityManager), liquidityProvider1);
        assertEq(healthAfterCollateral, 3, "LP should be healthy after adding collateral");

        // Attempt to add liquidity again
        vm.startPrank(liquidityProvider1);
        reserveToken.approve(address(liquidityManager), liquidityAddAmount);
        liquidityManager.addLiquidity(liquidityAddAmount);
        vm.stopPrank();

        // Verify LP's request after adding liquidity
        IPoolLiquidityManager.LPRequest memory request = liquidityManager.getLPRequest(liquidityProvider1);
        assertEq(uint(request.requestType), uint(IPoolLiquidityManager.RequestType.ADD_LIQUIDITY), "Request type should be ADD_LIQUIDITY");
        assertEq(request.requestAmount, liquidityAddAmount, "Request amount should match added liquidity amount");
        assertEq(request.requestCycle, cycleManager.cycleIndex(), "Request cycle should match current cycle");
    }

    /**
     * @notice Test liquidation during different cycle states
     */
    function testLiquidationDuringRebalancing() public {
        // Setup liquidatable LP
        testSetupLiquidatableLP();
        
        IPoolLiquidityManager.LPPosition memory position = liquidityManager.getLPPosition(liquidityProvider1);
        uint256 lpCommitment = position.liquidityCommitment;
        uint256 liquidationAmount = lpCommitment * 30 / 100; // 30% of position
        
        // Start offchain rebalancing
        vm.startPrank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INCREASED_PRICE);
        cycleManager.initiateOffchainRebalance();
        vm.stopPrank();
        
        // Attempt to liquidate during offchain rebalancing
        vm.startPrank(liquidator);
        vm.expectRevert(IPoolLiquidityManager.InvalidCycleState.selector);
        liquidityManager.liquidateLP(liquidityProvider1, liquidationAmount);
        vm.stopPrank();
        
        // Advance to onchain rebalancing
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        vm.startPrank(owner);
        assetOracle.setMarketOpen(false);
        updateOraclePrice(INCREASED_PRICE);
        cycleManager.initiateOnchainRebalance();
        vm.stopPrank();
        
        // Attempt to liquidate during onchain rebalancing
        vm.startPrank(liquidator);
        vm.expectRevert(IPoolLiquidityManager.InvalidCycleState.selector);
        liquidityManager.liquidateLP(liquidityProvider1, liquidationAmount);
        vm.stopPrank();
    }

    /**
     * @notice Test liquidation with zero amount
     */
    function testLiquidationZeroAmount() public {
        // Setup liquidatable LP
        testSetupLiquidatableLP();
        
        // Attempt to liquidate with zero amount
        vm.startPrank(liquidator);
        vm.expectRevert(IPoolLiquidityManager.InvalidAmount.selector);
        liquidityManager.liquidateLP(liquidityProvider1, 0);
        vm.stopPrank();
    }

    /**
     * @notice Test liquidation with amount greater than LP's position
     */
    function testLiquidationAmountGreaterThanPosition() public {
        // Setup liquidatable LP
        testSetupLiquidatableLP();
        
        // Get LP's asset share
        uint256 lpAssetShare = liquidityManager.getLPAssetShare(liquidityProvider1);
        uint256 excessiveAmount = lpAssetShare * 2; // Double the position size
        
        // Attempt to liquidate with excessive amount
        vm.startPrank(liquidator);
        vm.expectRevert(IPoolLiquidityManager.InvalidAmount.selector);
        liquidityManager.liquidateLP(liquidityProvider1, excessiveAmount);
        vm.stopPrank();
    }

    /**
     * @notice Test self-liquidation (LP trying to liquidate themselves)
     */
    function testSelfLiquidation() public {
        // Setup liquidatable LP
        testSetupLiquidatableLP();
        
        // Get LP's asset share
        uint256 lpAssetShare = liquidityManager.getLPAssetShare(liquidityProvider1);
        uint256 liquidationAmount = lpAssetShare * 20 / 100;
        
        // LP attempts to liquidate themselves
        vm.startPrank(liquidityProvider1);
        vm.expectRevert(IPoolLiquidityManager.InvalidLiquidation.selector);
        liquidityManager.liquidateLP(liquidityProvider1, liquidationAmount);
        vm.stopPrank();
    }
}