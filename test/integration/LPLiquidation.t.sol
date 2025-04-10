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
    uint256 constant INCREASED_PRICE_1 = 130 * 1e18; // $130.00 (30% increase)
    uint256 constant INCREASED_PRICE_2 = 175 * 1e18; // $175.00 (> 30% increase)
    uint256 constant USER_INITIAL_BALANCE = 100_000;
    uint256 constant LP_INITIAL_BALANCE = 1_000_000;
    uint256 constant LP_LIQUIDITY_AMOUNT = 500_000;
    uint256 constant USER_DEPOSIT_AMOUNT = 50_000;
    
    // LP test amounts
    uint256 constant LP_HEALTHY_COLLATERAL_RATIO = 30; // 30% for LPs
    uint256 constant LP_LIQUIDATION_THRESHOLD = 20; // 20% for LPs
    
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
        
        // Fund liquidators
        reserveToken.mint(liquidator, adjustAmountForDecimals(100_000, 6));
        reserveToken.mint(liquidator2, adjustAmountForDecimals(100_000, 6));
        
        // Approve token spending
        vm.startPrank(liquidator);
        reserveToken.approve(address(liquidityManager), type(uint256).max);
        assetToken.approve(address(assetPool), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(liquidator2);
        reserveToken.approve(address(liquidityManager), type(uint256).max);
        assetToken.approve(address(assetPool), type(uint256).max);
        vm.stopPrank();
        
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
     * @notice Test that we can remove excess collateral to make an LP liquidatable
     */
    function testSetupLiquidatableLP() public {
        // Get LP's initial position
        IPoolLiquidityManager.LPPosition memory initialPosition = liquidityManager.getLPPosition(liquidityProvider1);
        uint8 initialHealth = poolStrategy.getLPLiquidityHealth(address(liquidityManager), liquidityProvider1);
        
        // Verify LP is initially healthy
        assertEq(initialHealth, 3, "LP should start with healthy collateral ratio");
        
        // Calculate required collateral for healthy ratio
        uint256 lpAssetValue = liquidityManager.getLPAssetHoldingValue(liquidityProvider1);
        uint256 requiredCollateral = (lpAssetValue * LP_HEALTHY_COLLATERAL_RATIO) / BPS;
        uint256 excessCollateral = initialPosition.collateralAmount - requiredCollateral;
        
        // LP should have excess collateral initially
        assertGt(excessCollateral, 0, "LP should have excess collateral");
        
        // Remove most of the excess collateral to bring LP close to threshold
        uint256 collateralToRemove = excessCollateral * 95 / 100; // Remove 95% of excess
        
        vm.startPrank(liquidityProvider1);
        liquidityManager.reduceCollateral(collateralToRemove);
        vm.stopPrank();
        
        // Check LP's position after removal
        IPoolLiquidityManager.LPPosition memory updatedPosition = liquidityManager.getLPPosition(liquidityProvider1);
        uint8 updatedHealth = poolStrategy.getLPLiquidityHealth(address(liquidityManager), liquidityProvider1);
        
        // LP should still be healthy (level 3) or in warning (level 2)
        assertTrue(updatedHealth >= 2, "LP should not be liquidatable yet");
        assertLt(updatedPosition.collateralAmount, initialPosition.collateralAmount, "Collateral should be reduced");
        
        // Now increase the price by 30% to push the LP below liquidation threshold
        completeCycleWithPriceChange(INCREASED_PRICE_1);
        // Increase the price again to ensure LP is liquidatable
        completeCycleWithPriceChange(INCREASED_PRICE_2);
        
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
        
        // Get LP's asset share to determine liquidation amount
        uint256 lpAssetShare = liquidityManager.getLPAssetShare(liquidityProvider1);
        uint256 liquidationAmount = lpAssetShare * 30 / 100; // 30% of LP's position
        
        // Mint asset tokens to liquidator for the request
        vm.startPrank(owner);
        assetToken.mint(liquidator, liquidationAmount);
        vm.stopPrank();
        
        // Record liquidator's initial balance
        uint256 liquidatorInitialBalance = assetToken.balanceOf(liquidator);
        
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
        address liquidationInitiator = liquidityManager.getLPLiquidationIntiator(liquidityProvider1);
        assertEq(liquidationInitiator, liquidator, "Liquidation initiator should be recorded");
        
        // Assert asset tokens transferred from liquidator
        assertEq(assetToken.balanceOf(liquidator), liquidatorInitialBalance - liquidationAmount, "Liquidator should have transferred asset tokens");
    }

    /**
     * @notice Test attempting to liquidate a healthy position
     */
    function testLiquidateHealthyLP() public {
        // Get LP's asset share to determine liquidation amount
        uint256 lpAssetShare = liquidityManager.getLPAssetShare(liquidityProvider2);
        uint256 liquidationAmount = lpAssetShare * 30 / 100; // 30% of LP's position
        
        // Mint asset tokens to liquidator for the request
        vm.startPrank(owner);
        assetToken.mint(liquidator, liquidationAmount);
        vm.stopPrank();
        
        // Verify LP2 is healthy
        uint8 health = poolStrategy.getLPLiquidityHealth(address(liquidityManager), liquidityProvider2);
        assertEq(health, 3, "LP2 should be healthy");
        
        // Attempt to liquidate healthy position should fail
        vm.startPrank(liquidator);
        vm.expectRevert(IPoolLiquidityManager.NotEligibleForLiquidation.selector);
        liquidityManager.liquidateLP(liquidityProvider2, liquidationAmount);
        vm.stopPrank();
    }

    // ==================== LIQUIDATION EXECUTION TESTS ====================

    /**
     * @notice Test full liquidation execution with cycle completion
     */
    function testLiquidationExecution() public {
        // Setup liquidatable LP
        testSetupLiquidatableLP();
        
        // Get LP's asset share for liquidation amount
        uint256 lpAssetShare = liquidityManager.getLPAssetShare(liquidityProvider1);
        uint256 liquidationAmount = lpAssetShare * 25 / 100; // 25% of LP's position
        
        // Get LP's initial position
        IPoolLiquidityManager.LPPosition memory initialPosition = liquidityManager.getLPPosition(liquidityProvider1);
        
        // Mint asset tokens to liquidator for the request
        vm.startPrank(owner);
        assetToken.mint(liquidator, liquidationAmount);
        vm.stopPrank();
        
        // Submit liquidation request
        vm.startPrank(liquidator);
        liquidityManager.liquidateLP(liquidityProvider1, liquidationAmount);
        vm.stopPrank();
        
        // Record liquidator's balance before execution
        uint256 liquidatorBalanceBefore = reserveToken.balanceOf(liquidator);
        
        // Complete a cycle to process liquidation
        completeCycleWithPriceChange(INCREASED_PRICE_1);
        
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

    /**
     * @notice Test LP with insufficient collateral for reward
     */
    function testLiquidationInsufficientCollateralForReward() public {
        // Setup liquidatable LP
        testSetupLiquidatableLP();
        
        // Get LP's position
        IPoolLiquidityManager.LPPosition memory position = liquidityManager.getLPPosition(liquidityProvider1);
        
        // Remove almost all collateral to ensure insufficient collateral for reward
        uint256 collateralToRemove = position.collateralAmount * 90 / 100; // Remove 90%
        
        vm.startPrank(liquidityProvider1);
        // This might revert if it goes below required threshold
        try liquidityManager.reduceCollateral(collateralToRemove) {
            // Successfully removed collateral
        } catch {
            // If it reverted, try a smaller amount
            liquidityManager.reduceCollateral(position.collateralAmount * 70 / 100);
        }
        vm.stopPrank();
        
        // Get LP's updated asset share for liquidation
        uint256 lpAssetShare = liquidityManager.getLPAssetShare(liquidityProvider1);
        uint256 liquidationAmount = lpAssetShare * 20 / 100; // 20% of position
        
        // Mint asset tokens to liquidator
        vm.startPrank(owner);
        assetToken.mint(liquidator, liquidationAmount);
        vm.stopPrank();
        
        // Get LP's updated position before liquidation
        position = liquidityManager.getLPPosition(liquidityProvider1);
        uint256 initialCollateral = position.collateralAmount;
        
        // Submit liquidation request (may revert if not actually liquidatable)
        vm.startPrank(liquidator);
        try liquidityManager.liquidateLP(liquidityProvider1, liquidationAmount) {
            // Successfully submitted request
        } catch {
            // If it reverted, LP might not be liquidatable despite our setup
            // Verify LP health status
            uint8 health = poolStrategy.getLPLiquidityHealth(address(liquidityManager), liquidityProvider1);
            assertEq(health, 1, "LP should be liquidatable");
            vm.stopPrank();
            return; // End test if LP is not liquidatable
        }
        vm.stopPrank();
        
        // Complete cycle to process liquidation
        completeCycleWithPriceChange(INCREASED_PRICE_1);
        
        // Verify liquidation still processed but with reduced reward
        position = liquidityManager.getLPPosition(liquidityProvider1);
        assertTrue(position.collateralAmount <= initialCollateral, "Collateral should not increase");
    }

    // ==================== CANCELLATION TESTS ====================

    /**
     * @notice Test cancellation of liquidation if LP adds sufficient collateral
     */
    function testLiquidationCancellation() public {
        // Setup liquidatable LP
        testSetupLiquidatableLP();
        
        // Get LP's asset share for liquidation
        uint256 lpAssetShare = liquidityManager.getLPAssetShare(liquidityProvider1);
        uint256 liquidationAmount = lpAssetShare * 20 / 100; // 20% of position
        
        // Mint asset tokens to liquidator
        vm.startPrank(owner);
        assetToken.mint(liquidator, liquidationAmount);
        vm.stopPrank();
        
        // Submit liquidation request
        vm.startPrank(liquidator);
        liquidityManager.liquidateLP(liquidityProvider1, liquidationAmount);
        vm.stopPrank();
        
        // Record liquidator's asset balance after request (should have decreased)
        uint256 liquidatorBalanceAfterRequest = assetToken.balanceOf(liquidator);
        
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
        
        // Verify liquidation request was cancelled
        IPoolLiquidityManager.LPRequest memory request = liquidityManager.getLPRequest(liquidityProvider1);
        assertEq(uint(request.requestType), uint(IPoolLiquidityManager.RequestType.NONE), "Request should be cancelled");
        
        // Verify liquidator received their tokens back
        uint256 liquidatorFinalBalance = assetToken.balanceOf(liquidator);
        assertEq(liquidatorFinalBalance, liquidatorBalanceAfterRequest + liquidationAmount, "Liquidator should receive tokens back");
    }

    // ==================== EDGE CASE TESTS ====================

    /**
     * @notice Test liquidation when a different request type is pending
     */
    function testLiquidateWithPendingRequest() public {
        // Setup liquidatable LP
        testSetupLiquidatableLP();
        
        // Create a regular liquidity request for the LP
        uint256 liquidityAddAmount = 10000 * 10**6; // 10,000 units
        
        vm.startPrank(owner);
        reserveToken.mint(liquidityProvider1, liquidityAddAmount * 2);
        vm.stopPrank();
        
        vm.startPrank(liquidityProvider1);
        reserveToken.approve(address(liquidityManager), liquidityAddAmount * 2);
        liquidityManager.addLiquidity(liquidityAddAmount);
        vm.stopPrank();
        
        // Verify request is pending
        IPoolLiquidityManager.LPRequest memory request = liquidityManager.getLPRequest(liquidityProvider1);
        assertEq(uint(request.requestType), uint(IPoolLiquidityManager.RequestType.ADD_LIQUIDITY), "Request type should be ADD_LIQUIDITY");
        
        // Attempt to liquidate with pending request
        uint256 lpAssetShare = liquidityManager.getLPAssetShare(liquidityProvider1);
        uint256 liquidationAmount = lpAssetShare * 20 / 100;
        
        vm.startPrank(owner);
        assetToken.mint(liquidator, liquidationAmount);
        vm.stopPrank();
        
        // Should revert due to pending request
        vm.startPrank(liquidator);
        vm.expectRevert(IPoolLiquidityManager.RequestPending.selector);
        liquidityManager.liquidateLP(liquidityProvider1, liquidationAmount);
        vm.stopPrank();
    }

    /**
     * @notice Test liquidation during different cycle states
     */
    function testLiquidationDuringRebalancing() public {
        // Setup liquidatable LP
        testSetupLiquidatableLP();
        
        // Get LP's asset share for liquidation
        uint256 lpAssetShare = liquidityManager.getLPAssetShare(liquidityProvider1);
        uint256 liquidationAmount = lpAssetShare * 20 / 100; // 20% of position
        
        // Mint asset tokens to liquidator
        vm.startPrank(owner);
        assetToken.mint(liquidator, liquidationAmount);
        vm.stopPrank();
        
        // Start offchain rebalancing
        vm.startPrank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INCREASED_PRICE_1);
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
        updateOraclePrice(INCREASED_PRICE_1);
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
        
        // Mint asset tokens to liquidator
        vm.startPrank(owner);
        assetToken.mint(liquidator, excessiveAmount);
        vm.stopPrank();
        
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
        
        // Mint asset tokens to LP
        vm.startPrank(owner);
        assetToken.mint(liquidityProvider1, liquidationAmount);
        vm.stopPrank();
        
        // LP attempts to liquidate themselves
        vm.startPrank(liquidityProvider1);
        vm.expectRevert(IPoolLiquidityManager.InvalidLiquidation.selector);
        liquidityManager.liquidateLP(liquidityProvider1, liquidationAmount);
        vm.stopPrank();
    }
}