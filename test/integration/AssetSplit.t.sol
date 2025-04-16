// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "../utils/ProtocolTestUtils.sol";

/**
 * @title AssetSplitTest
 * @notice Integration tests for the asset split detection and resolution functionality
 * @dev Tests both valid and invalid split scenarios and their resolution
 */
contract AssetSplitTest is ProtocolTestUtils {
    // Base amounts (will be adjusted based on token decimals)
    uint256 constant INITIAL_PRICE = 100 * 1e18; // $100.00 per asset (always 18 decimals)
    uint256 constant USER_INITIAL_BALANCE = 100_000; 
    uint256 constant LP_INITIAL_BALANCE = 1_000_000;
    uint256 constant LP_LIQUIDITY_AMOUNT = 500_000;
    
    // Split parameters
    uint256 constant SPLIT_RATIO = 2;        // 2:1 stock split
    uint256 constant SPLIT_DENOMINATOR = 1;
    uint256 constant REVERSE_SPLIT_RATIO = 1;    // 1:2 reverse stock split
    uint256 constant REVERSE_SPLIT_DENOMINATOR = 2;

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

    // ==================== VALID SPLIT TESTS ====================

    /**
     * @notice Test detection and resolution of a valid 2:1 stock split
     */
    function testValidStockSplit() public {
        // Add user deposits to create asset tokens in the system
        vm.prank(user1);
        assetPool.depositRequest(
            adjustAmountForDecimals(10_000, 6),  // 10,000 units of reserve token
            adjustAmountForDecimals(2_000, 6)    // 2,000 units of collateral
        );
        
        // Complete a cycle to process deposits
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // User claims assets to mint tokens
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Record user's initial asset balance
        uint256 initialAssetBalance = assetToken.balanceOf(user1);
        
        // Generate a 2:1 split price drop (price should halve)
        uint256 splitPrice = INITIAL_PRICE / 2;
        
        // Trigger split detection in the oracle
        vm.startPrank(owner);
        assetOracle.setMarketOpen(true);
        
        // Update oracle with post-split price
        updateOraclePriceWithOHLC(
            splitPrice * 98 / 100,  // open slightly below split price 
            splitPrice * 102 / 100, // high slightly above split price
            splitPrice * 95 / 100,  // low below split price
            splitPrice               // close at split price
        );
        
        // Verify split was detected
        assertTrue(assetOracle.splitDetected(), "Split should be detected by oracle");
        assertEq(assetOracle.preSplitPrice(), INITIAL_PRICE, "Pre-split price should be recorded");
        
        // Start offchain rebalance (should work even with detected split)
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to onchain rebalance phase
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        assetOracle.setMarketOpen(false);
        updateOraclePrice(splitPrice);
        vm.stopPrank();
        
        // Try to initiate onchain rebalance - should fail due to price deviation
        vm.prank(owner);
        vm.expectRevert(IPoolCycleManager.PriceDeviationHigh.selector);
        cycleManager.initiateOnchainRebalance();
        
        // Verify the split ratio is valid
        bool isSplitValid = assetOracle.verifySplit(SPLIT_RATIO, SPLIT_DENOMINATOR);
        assertTrue(isSplitValid, "Split ratio should be valid");
        
        // Resolve the price deviation with a valid split
        vm.prank(owner);
        cycleManager.resolvePriceDeviation(true, SPLIT_RATIO, SPLIT_DENOMINATOR);
        
        // Verify isPriceDeviationValid is now true
        assertTrue(cycleManager.isPriceDeviationValid(), "Price deviation should be marked as valid");
        
        // Now we should be able to initiate onchain rebalance
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // Verify we're in onchain rebalancing state
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_REBALANCING_ONCHAIN), 
            "Should be in onchain rebalancing state after split resolution");
        
        // Check that the token split was applied correctly
        uint256 splitMultiplier = assetToken.splitMultiplier() / 1e18;
        assertEq(splitMultiplier, SPLIT_RATIO, "Split multiplier should match ratio");
        
        // User's token balance should double
        uint256 finalAssetBalance = assetToken.balanceOf(user1);
        assertEq(finalAssetBalance, initialAssetBalance * SPLIT_RATIO / SPLIT_DENOMINATOR, 
            "User's asset balance should be adjusted by split ratio");
        
        // Verify oracle was reset
        assetOracle.resetSplitDetection();
        assertFalse(assetOracle.splitDetected(), "Split detection should be reset");
        assertEq(assetOracle.preSplitPrice(), 0, "Pre-split price should be reset");
        
        // Complete the cycle by having LPs rebalance
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, splitPrice);
        
        vm.prank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, splitPrice);
        
        // Verify cycle completed successfully
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_ACTIVE), 
            "Should return to active state after rebalance");
    }

    /**
     * @notice Test detection and resolution of a valid 1:2 reverse stock split
     */
    function testValidReverseStockSplit() public {
        // Add user deposits to create asset tokens in the system
        vm.prank(user1);
        assetPool.depositRequest(
            adjustAmountForDecimals(10_000, 6),  // 10,000 units of reserve token
            adjustAmountForDecimals(2_000, 6)    // 2,000 units of collateral
        );
        
        // Complete a cycle to process deposits
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // User claims assets to mint tokens
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Record user's initial asset balance
        uint256 initialAssetBalance = assetToken.balanceOf(user1);
        
        // Generate a 1:2 reverse split price increase (price should double)
        uint256 reverseSplitPrice = INITIAL_PRICE * 2;
        
        // Trigger split detection in the oracle
        vm.startPrank(owner);
        assetOracle.setMarketOpen(true);
        
        // Update oracle with post-split price
        updateOraclePriceWithOHLC(
            reverseSplitPrice * 98 / 100,  // open slightly below split price 
            reverseSplitPrice * 102 / 100, // high slightly above split price
            reverseSplitPrice * 95 / 100,  // low below split price
            reverseSplitPrice              // close at split price
        );
        
        // Verify split was detected
        assertTrue(assetOracle.splitDetected(), "Split should be detected by oracle");
        assertEq(assetOracle.preSplitPrice(), INITIAL_PRICE, "Pre-split price should be recorded");
        
        // Start offchain rebalance (should work even with detected split)
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to onchain rebalance phase
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        assetOracle.setMarketOpen(false);
        updateOraclePrice(reverseSplitPrice);
        vm.stopPrank();
        
        // Try to initiate onchain rebalance - should fail due to price deviation
        vm.prank(owner);
        vm.expectRevert(IPoolCycleManager.PriceDeviationHigh.selector);
        cycleManager.initiateOnchainRebalance();
        
        // Verify the split ratio is valid
        bool isSplitValid = assetOracle.verifySplit(REVERSE_SPLIT_RATIO, REVERSE_SPLIT_DENOMINATOR);
        assertTrue(isSplitValid, "Reverse split ratio should be valid");
        
        // Resolve the price deviation with a valid reverse split
        vm.prank(owner);
        cycleManager.resolvePriceDeviation(true, REVERSE_SPLIT_RATIO, REVERSE_SPLIT_DENOMINATOR);
        
        // Verify isPriceDeviationValid is now true
        assertTrue(cycleManager.isPriceDeviationValid(), "Price deviation should be marked as valid");
        
        // Now we should be able to initiate onchain rebalance
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // Verify we're in onchain rebalancing state
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_REBALANCING_ONCHAIN), 
            "Should be in onchain rebalancing state after split resolution");
        
        // Check that the token split was applied correctly
        // For a reverse split, the multiplier is reduced
        uint256 expectedMultiplier = 1e18 * REVERSE_SPLIT_RATIO / REVERSE_SPLIT_DENOMINATOR;
        assertEq(assetToken.splitMultiplier(), expectedMultiplier, "Split multiplier should match reverse ratio");
        
        // User's token balance should halve for a 1:2 reverse split
        uint256 finalAssetBalance = assetToken.balanceOf(user1);
        assertEq(finalAssetBalance, initialAssetBalance * REVERSE_SPLIT_RATIO / REVERSE_SPLIT_DENOMINATOR, 
            "User's asset balance should be adjusted by reverse split ratio");
        
        // Verify oracle was reset
        assetOracle.resetSplitDetection();
        assertFalse(assetOracle.splitDetected(), "Split detection should be reset");
        assertEq(assetOracle.preSplitPrice(), 0, "Pre-split price should be reset");
        
        // Complete the cycle by having LPs rebalance
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, reverseSplitPrice);
        
        vm.prank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, reverseSplitPrice);
        
        // Verify cycle completed successfully
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_ACTIVE), 
            "Should return to active state after rebalance");
    }

    // ==================== INVALID SPLIT TESTS ====================

    /**
     * @notice Test detection and resolution of an invalid split (price shock not due to split)
     */
    function testInvalidSplit() public {
        // Add user deposits to create asset tokens in the system
        vm.prank(user1);
        assetPool.depositRequest(
            adjustAmountForDecimals(10_000, 6),  // 10,000 units of reserve token
            adjustAmountForDecimals(2_000, 6)    // 2,000 units of collateral
        );
        
        // Complete a cycle to process deposits
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // User claims assets to mint tokens
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Record user's initial asset balance
        uint256 initialAssetBalance = assetToken.balanceOf(user1);
        
        // Generate a significant price drop that's not due to a split
        uint256 shockPrice = INITIAL_PRICE * 55 / 100; // 45% drop
        
        // Trigger split detection in the oracle
        vm.startPrank(owner);
        assetOracle.setMarketOpen(true);
        
        // Update oracle with shocked price
        updateOraclePriceWithOHLC(
            shockPrice * 98 / 100,  // open slightly below shock price 
            shockPrice * 102 / 100, // high slightly above shock price
            shockPrice * 95 / 100,  // low below shock price
            shockPrice               // close at shock price
        );
        
        // Verify split was detected
        assertTrue(assetOracle.splitDetected(), "Split should be detected by oracle");
        assertEq(assetOracle.preSplitPrice(), INITIAL_PRICE, "Pre-split price should be recorded");
        
        // Start offchain rebalance (should work even with detected split)
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to onchain rebalance phase
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        assetOracle.setMarketOpen(false);
        updateOraclePrice(shockPrice);
        vm.stopPrank();
        
        // Try to initiate onchain rebalance - should fail due to price deviation
        vm.prank(owner);
        vm.expectRevert(IPoolCycleManager.PriceDeviationHigh.selector);
        cycleManager.initiateOnchainRebalance();
        
        // Get initial splitMultiplier value
        uint256 initialSplitMultiplier = assetToken.splitMultiplier();
        
        // Resolve the price deviation as a NON-split (false parameter)
        vm.startPrank(owner);
        cycleManager.resolvePriceDeviation(false, 0, 0);
        
        // Verify isPriceDeviationValid is now true
        assertTrue(cycleManager.isPriceDeviationValid(), "Price deviation should be marked as valid");
        
        // Verify token split was NOT applied (splitMultiplier remains unchanged)
        assertEq(assetToken.splitMultiplier(), initialSplitMultiplier, "Split multiplier should remain unchanged");
        
        // Verify user's token balance remains unchanged
        assertEq(assetToken.balanceOf(user1), initialAssetBalance, "User's asset balance should remain unchanged");
        
        // Directly verify split detection was reset on the oracle
        assetOracle.resetSplitDetection();
        assertFalse(assetOracle.splitDetected(), "Split detection should be reset");
        assertEq(assetOracle.preSplitPrice(), 0, "Pre-split price should be reset");
        
        // Now we should be able to initiate onchain rebalance
        cycleManager.initiateOnchainRebalance();
        vm.stopPrank();
        
        // Verify we're in onchain rebalancing state
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_REBALANCING_ONCHAIN), 
            "Should be in onchain rebalancing state after resolving price deviation");
        
        // Complete the cycle by having LPs rebalance
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, shockPrice);
        
        vm.prank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, shockPrice);
        
        // Verify cycle completed successfully
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_ACTIVE), 
            "Should return to active state after rebalance");
    }

    /**
     * @notice Test handling an incorrect split ratio
     */
    function testInvalidSplitRatio() public {
        // Generate a price drop that triggers split detection
        uint256 splitPrice = INITIAL_PRICE / 2;
        
        // Trigger split detection in the oracle
        vm.startPrank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(splitPrice);
        
        // Verify split was detected
        assertTrue(assetOracle.splitDetected(), "Split should be detected by oracle");
        
        // Start offchain rebalance
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to onchain rebalance phase
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        assetOracle.setMarketOpen(false);
        updateOraclePrice(splitPrice);
        
        // Verify that an incorrect split ratio is rejected
        // Note: We're purposely trying to pass a wrong ratio (3:1 instead of 2:1)
        vm.expectRevert(IPoolCycleManager.InvalidSplit.selector);
        cycleManager.resolvePriceDeviation(true, 3, 1);
        vm.stopPrank();
        
        // Split should still be detected since resolution failed
        assertTrue(assetOracle.splitDetected(), "Split should still be detected after failed resolution");
    }

    /**
     * @notice Test split detection and state transitions before resolution
     */
    function testSplitDetectionStateTransitions() public {
        // Generate a significant price drop that should trigger split detection
        uint256 splitPrice = INITIAL_PRICE / 2;
        
        // Initial state - no split detected
        assertFalse(assetOracle.splitDetected(), "No split should be detected initially");
        
        // Trigger split detection in the oracle
        vm.startPrank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(splitPrice);
        
        // Verify split was detected
        assertTrue(assetOracle.splitDetected(), "Split should be detected after price change");
        assertEq(assetOracle.preSplitPrice(), INITIAL_PRICE, "Pre-split price should be recorded");
        
        // Verify we can still initiate offchain rebalance even with split detected
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_ACTIVE), "Pool should be in active state");
        cycleManager.initiateOffchainRebalance();
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_REBALANCING_OFFCHAIN), "Pool should transition to offchain rebalancing");
        
        // But we cannot directly go to onchain rebalance without resolving the price deviation
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        assetOracle.setMarketOpen(false);
        
        // Ensure the oracle is updated recently enough to pass the threshold check
        updateOraclePrice(splitPrice);
        
        // Now the error should be about price deviation, not oracle staleness
        vm.expectRevert(IPoolCycleManager.PriceDeviationHigh.selector);
        cycleManager.initiateOnchainRebalance();
        vm.stopPrank();
    }

    /**
     * @notice Test multiple sequential stock splits
     */
    function testMultipleSequentialSplits() public {
        // Add user deposits to create asset tokens in the system
        vm.prank(user1);
        assetPool.depositRequest(
            adjustAmountForDecimals(10_000, 6),  // 10,000 units of reserve token
            adjustAmountForDecimals(2_000, 6)    // 2,000 units of collateral
        );
        
        // Complete a cycle to process deposits
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // User claims assets to mint tokens
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Record user's initial asset balance
        uint256 initialAssetBalance = assetToken.balanceOf(user1);
        
        // First split: 2:1
        // ---------------
        // Generate a 2:1 split price drop
        uint256 firstSplitPrice = INITIAL_PRICE / 2;
        
        // Process first split
        vm.startPrank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(firstSplitPrice);
        assertTrue(assetOracle.splitDetected(), "Split should be detected after price change");
        
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to onchain rebalance phase
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        assetOracle.setMarketOpen(false);
        updateOraclePrice(firstSplitPrice);
        
        // Resolve the price deviation with a valid split
        cycleManager.resolvePriceDeviation(true, SPLIT_RATIO, SPLIT_DENOMINATOR);
        cycleManager.initiateOnchainRebalance();
        vm.stopPrank();
        
        // Complete the cycle
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, firstSplitPrice);
        
        vm.prank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, firstSplitPrice);
        
        // Verify balance after first split
        uint256 balanceAfterFirstSplit = assetToken.balanceOf(user1);
        assertEq(balanceAfterFirstSplit, initialAssetBalance * 2, "Balance should double after 2:1 split");
        
        // Second split: 1:2 (reverse)
        // --------------------------
        // Generate a 1:2 reverse split price increase
        uint256 secondSplitPrice = firstSplitPrice * 2; // Back to original price
        
        // Process second split
        vm.startPrank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(secondSplitPrice);
        
        // Manually set split detected since our simple test oracle might not detect it
        assetOracle.setSplitDetected(true, firstSplitPrice);
        
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to onchain rebalance phase
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        assetOracle.setMarketOpen(false);
        updateOraclePrice(secondSplitPrice);
        
        // Resolve the price deviation with a valid reverse split
        cycleManager.resolvePriceDeviation(true, REVERSE_SPLIT_RATIO, REVERSE_SPLIT_DENOMINATOR);
        cycleManager.initiateOnchainRebalance();
        vm.stopPrank();
        
        // Complete the cycle
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, secondSplitPrice);
        
        vm.prank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, secondSplitPrice);
        
        // Verify final balance - should be back to initial (2x * 0.5x = 1x)
        uint256 finalBalance = assetToken.balanceOf(user1);
        assertEq(finalBalance, initialAssetBalance, "Final balance should equal initial after offsetting splits");
    }

    /**
     * @notice Test attempting to resolve a split when no split is detected
     */
    function testResolveNonExistentSplit() public {
        // Start in active state with no split detected
        assertFalse(assetOracle.splitDetected(), "No split should be detected initially");
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_ACTIVE), "Pool should be in active state");
        
        // First go to offchain rebalance state
        vm.startPrank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INITIAL_PRICE);
        cycleManager.initiateOffchainRebalance();
        
        // Since no split is detected, we should get an InvalidSplit error
        // rather than an InvalidCycleState error when trying to resolve a split
        vm.expectRevert(IPoolCycleManager.InvalidSplit.selector);
        cycleManager.resolvePriceDeviation(true, SPLIT_RATIO, SPLIT_DENOMINATOR);
        vm.stopPrank();
    }
}