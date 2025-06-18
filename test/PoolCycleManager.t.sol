// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "./utils/ProtocolTestUtils.sol";

/**
 * @title PoolCycleManagerTest
 * @notice Unit tests for the PoolCycleManager contract focusing on cycle transitions and rebalancing
 */
contract PoolCycleManagerTest is ProtocolTestUtils {
    // Base amounts (will be adjusted based on token decimals)
    uint256 constant INITIAL_PRICE = 100 * 1e18; // $100.00 per asset (always 18 decimals)
    uint256 constant USER_INITIAL_BALANCE = 100_000; 
    uint256 constant LP_INITIAL_BALANCE = 1_000_000;
    uint256 constant LP_LIQUIDITY_AMOUNT = 500_000;
    uint256 constant USER_DEPOSIT_AMOUNT = 10_000;
    uint256 constant COLLATERAL_RATIO = 20;
    
    // Price scenarios for testing
    uint256 constant PRICE_INCREASE = 110 * 1e18; // $110.00 per asset
    uint256 constant PRICE_DECREASE = 90 * 1e18; // $90.00 per asset
    
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
    
    // ==================== CYCLE STATE TESTS ====================
    
    /**
     * @notice Test initial cycle state
     */
    function testInitialCycleState() view public {
        // Verify initial cycle state
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_ACTIVE), "Initial cycle state should be ACTIVE");
        assertEq(cycleManager.cycleIndex(), 3, "Initial cycle index should be 3"); // Its 3 because we have 2 cycles already completed
        assertGt(cycleManager.lastCycleActionDateTime(), 0, "Last cycle action timestamp should be set");
        assertEq(cycleManager.rebalancedLPs(), 0, "No LPs should be rebalanced initially");
    }
    
    /**
     * @notice Test initiating offchain rebalance
     */
    function testInitiateOffchainRebalance() public {
        // Ensure market is open for offchain rebalance
        vm.prank(owner);
        assetOracle.setMarketOpen(true);
        
        // Record initial cycle data
        uint256 initialCycleIndex = cycleManager.cycleIndex();
                
        // Update oracle with fresh price
        vm.warp(block.timestamp + 1 hours);
        updateOraclePrice(INITIAL_PRICE);
        
        // Call the initiateOffchainRebalance function
        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        
        // Verify state changes
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_REBALANCING_OFFCHAIN), "Cycle state should be OFFCHAIN_REBALANCING");
        assertEq(cycleManager.cycleIndex(), initialCycleIndex, "Cycle index should not change");
    }
    
    /**
     * @notice Test initiating offchain rebalance fails when market is closed
     */
    function testInitiateOffchainRebalance_MarketClosed() public {
        // Ensure market is closed
        vm.prank(owner);
        assetOracle.setMarketOpen(false);
        
        // Update oracle with fresh price
        updateOraclePrice(INITIAL_PRICE);
        
        // Expect revert when trying to initiate offchain rebalance with closed market
        vm.prank(owner);
        vm.expectRevert(IPoolCycleManager.MarketClosed.selector);
        cycleManager.initiateOffchainRebalance();
    }
    
    /**
     * @notice Test initiating offchain rebalance fails when oracle price is stale
     */
    function testInitiateOffchainRebalance_StaleOracle() public {
        // Ensure market is open
        vm.prank(owner);
        assetOracle.setMarketOpen(true);
        
        // Set oracle parameters to make it stale
        (, uint256 oracleThreshold,) = poolStrategy.getCycleParams();
        
        // Advance time past the oracle update threshold
        vm.warp(block.timestamp + oracleThreshold + 1);
        
        // Expect revert when trying to initiate offchain rebalance with stale oracle
        vm.prank(owner);
        vm.expectRevert(IPoolCycleManager.OracleNotUpdated.selector);
        cycleManager.initiateOffchainRebalance();
    }
    
    /**
     * @notice Test initiating onchain rebalance
     */
    function testInitiateOnchainRebalance() public {
        // First initiate offchain rebalance
        vm.prank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to simulate offchain rebalance period
        vm.warp(block.timestamp + 1 hours);
        
        // Ensure market is closed for onchain rebalance
        vm.prank(owner);
        assetOracle.setMarketOpen(false);
        
        // Update oracle with OHLC data for high/low calculation
        updateOraclePriceWithOHLC(
            INITIAL_PRICE * 98 / 100, // open
            INITIAL_PRICE * 105 / 100, // high
            INITIAL_PRICE * 95 / 100, // low
            INITIAL_PRICE // close
        );
        
        // Record cycle data before onchain rebalance
        uint256 initialCycleIndex = cycleManager.cycleIndex();
        uint256 initialLastAction = cycleManager.lastCycleActionDateTime();
        uint256 lpCount = liquidityManager.getLPCount();
        
        // Call the initiateOnchainRebalance function
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // Verify state changes
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_REBALANCING_ONCHAIN), "Cycle state should be ONCHAIN_REBALANCING");
        assertEq(cycleManager.cycleIndex(), initialCycleIndex, "Cycle index should not change");
        assertGt(cycleManager.lastCycleActionDateTime(), initialLastAction, "Last cycle action timestamp should be updated");
        assertEq(cycleManager.cycleLPCount(), lpCount, "Cycle LP count should match total LPs");
        
        // Verify high/low prices were set
        assertGt(cycleManager.cyclePriceHigh(), 0, "Cycle high price should be set");
        assertGt(cycleManager.cyclePriceLow(), 0, "Cycle low price should be set");
        assertGt(cycleManager.cyclePriceHigh(), cycleManager.cyclePriceLow(), "High price should be greater than low price");
    }
    
    /**
     * @notice Test initiating onchain rebalance fails when not in offchain rebalance state
     */
    function testInitiateOnchainRebalance_InvalidState() public {
        // Ensure market is closed
        vm.prank(owner);
        assetOracle.setMarketOpen(false);
        
        // Update oracle with fresh price
        updateOraclePrice(INITIAL_PRICE);
        
        // Expect revert when trying to initiate onchain rebalance from active state
        vm.prank(owner);
        vm.expectRevert(IPoolCycleManager.InvalidCycleState.selector);
        cycleManager.initiateOnchainRebalance();
    }
    
    /**
     * @notice Test initiating onchain rebalance fails when market is open
     */
    function testInitiateOnchainRebalance_MarketOpen() public {
        // First initiate offchain rebalance
        vm.prank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to simulate offchain rebalance period
        vm.warp(block.timestamp + 1 hours);
        
        // Ensure market is still open (which should fail for onchain rebalance)
        vm.prank(owner);
        assetOracle.setMarketOpen(true);
        
        // Update oracle with fresh price
        updateOraclePrice(INITIAL_PRICE);
        
        // Expect revert when trying to initiate onchain rebalance with open market
        vm.prank(owner);
        vm.expectRevert(IPoolCycleManager.MarketOpen.selector);
        cycleManager.initiateOnchainRebalance();
    }
    
    // ==================== LP REBALANCE TESTS ====================
    
    /**
     * @notice Test LP rebalancing flow with stable price
     */
    function testLPRebalance_StablePrice() public {
        // Start offchain rebalance
        vm.prank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INITIAL_PRICE);

        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to simulate offchain rebalance period
        vm.warp(block.timestamp + 1 hours);
        
        // Start onchain rebalance
        vm.prank(owner);
        assetOracle.setMarketOpen(false);
        updateOraclePriceWithOHLC(
            INITIAL_PRICE * 98 / 100, 
            INITIAL_PRICE * 105 / 100, 
            INITIAL_PRICE * 95 / 100, 
            INITIAL_PRICE
        );
        
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // Record data before LP rebalance
        uint256 initialCycleIndex = cycleManager.cycleIndex();
        uint256 initialRebalancedLPs = cycleManager.rebalancedLPs();
        uint256 initialLastRebalanced = cycleManager.lastRebalancedCycle(liquidityProvider1);
        
        // LP1 calculates rebalance amount and rebalances
        vm.startPrank(liquidityProvider1);
        (uint256 rebalanceAmount, bool isDeposit) = cycleManager.calculateLPRebalanceAmount(liquidityProvider1, INITIAL_PRICE);
        cycleManager.rebalancePool(liquidityProvider1, INITIAL_PRICE);
        vm.stopPrank();
        
        // Verify LP1 state changes
        assertEq(cycleManager.lastRebalancedCycle(liquidityProvider1), initialCycleIndex, "Last rebalanced cycle should be updated");
        assertGt(cycleManager.lastRebalancedCycle(liquidityProvider1), initialLastRebalanced, "Last rebalanced cycle should increase");
        assertEq(cycleManager.rebalancedLPs(), initialRebalancedLPs + 1, "Rebalanced LP count should increment");
        
        // LP2 rebalances
        vm.startPrank(liquidityProvider2);
        (rebalanceAmount, isDeposit) = cycleManager.calculateLPRebalanceAmount(liquidityProvider2, INITIAL_PRICE);
        cycleManager.rebalancePool(liquidityProvider2, INITIAL_PRICE);
        vm.stopPrank();

        uint256 currentCycle = cycleManager.cycleIndex();
        // Verify cycle has moved to next state after all LPs rebalanced
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_ACTIVE), "Cycle state should return to ACTIVE");
        assertEq(currentCycle, initialCycleIndex + 1, "Cycle index should increment");
        assertEq(cycleManager.rebalancedLPs(), 0, "Rebalanced LP count should reset");
        
        // Verify rebalance price was set
        assertGt(cycleManager.cycleRebalancePrice(initialCycleIndex), 0, "Rebalance price should be set for previous cycle");
    }
    
    /**
     * @notice Test LP rebalancing with price increase
     */
    function testLPRebalance_PriceIncrease() public {
        // Put some user deposits to create non-zero asset supply
        vm.prank(user1);
        assetPool.depositRequest(
            adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6), 
            adjustAmountForDecimals(USER_DEPOSIT_AMOUNT * COLLATERAL_RATIO / 100, 6)
        );
        
        uint256 initialCycle = cycleManager.cycleIndex();

        // Start offchain rebalance
        vm.prank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to simulate offchain rebalance period
        vm.warp(block.timestamp + 1 hours);
        
        // Start onchain rebalance with higher price
        vm.prank(owner);
        assetOracle.setMarketOpen(false);
        updateOraclePriceWithOHLC(
            INITIAL_PRICE * 105 / 100, 
            PRICE_INCREASE * 110 / 100, 
            INITIAL_PRICE, 
            PRICE_INCREASE
        );
        
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // LP1 calculates rebalance amount
        vm.startPrank(liquidityProvider1);
        (uint256 rebalanceAmount, bool isDeposit) = cycleManager.calculateLPRebalanceAmount(liquidityProvider1, PRICE_INCREASE);
        
        // With price increase, LP should need to deposit (positive rebalance amount)
        if (rebalanceAmount > 0 && isDeposit) {
            // Approve spending if LP needs to deposit
            reserveToken.approve(address(cycleManager), rebalanceAmount);
        }
        
        // LP1 rebalances
        cycleManager.rebalancePool(liquidityProvider1, PRICE_INCREASE);
        vm.stopPrank();
        
        // LP2 rebalances
        vm.startPrank(liquidityProvider2);
        (rebalanceAmount, isDeposit) = cycleManager.calculateLPRebalanceAmount(liquidityProvider2, PRICE_INCREASE);
        
        if (rebalanceAmount > 0 && isDeposit) {
            // Approve spending if LP needs to deposit
            reserveToken.approve(address(cycleManager), rebalanceAmount);
        }
        
        cycleManager.rebalancePool(liquidityProvider2, PRICE_INCREASE);
        vm.stopPrank();
        
        // Verify final state
        uint256 currentCycle = cycleManager.cycleIndex();
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_ACTIVE), "Cycle state should return to ACTIVE");
        assertEq(currentCycle, initialCycle + 1, "Cycle index should increment");
        assertEq(cycleManager.rebalancedLPs(), 0, "Rebalanced LP count should reset");
        
        // Verify rebalance price is recorded correctly
        assertEq(cycleManager.cycleRebalancePrice(currentCycle - 1), PRICE_INCREASE, "Rebalance price should match");
    }
    
    /**
     * @notice Test LP rebalancing with price decrease
     */
    function testLPRebalance_PriceDecrease() public {
        // Put some user deposits to create non-zero asset supply
        vm.prank(user1);
        assetPool.depositRequest(
            adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6), 
            adjustAmountForDecimals(USER_DEPOSIT_AMOUNT * COLLATERAL_RATIO / 100, 6)
        );

        uint256 initialCycle = cycleManager.cycleIndex();
        
        // Complete one cycle to mint assets
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Start offchain rebalance
        vm.prank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to simulate offchain rebalance period
        vm.warp(block.timestamp + 1 hours);
        
        // Start onchain rebalance with lower price
        vm.prank(owner);
        assetOracle.setMarketOpen(false);
        updateOraclePriceWithOHLC(
            INITIAL_PRICE * 95 / 100, 
            INITIAL_PRICE, 
            PRICE_DECREASE * 90 / 100, 
            PRICE_DECREASE
        );
        
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // Record initial LP reserve balances
        uint256 lp1InitialBalance = reserveToken.balanceOf(liquidityProvider1);
        uint256 lp2InitialBalance = reserveToken.balanceOf(liquidityProvider2);
        
        // LP1 calculates rebalance amount
        vm.startPrank(liquidityProvider1);
        (uint256 rebalanceAmount, bool isDeposit) = cycleManager.calculateLPRebalanceAmount(liquidityProvider1, PRICE_DECREASE);
        
        // With price decrease, LP should receive funds (negative rebalance amount)
        assertFalse(isDeposit, "LP should receive funds with price decrease");
        
        // LP1 rebalances
        cycleManager.rebalancePool(liquidityProvider1, PRICE_DECREASE);
        vm.stopPrank();
        
        // Verify LP1 received funds
        if (rebalanceAmount > 0 && !isDeposit) {
            assertGt(reserveToken.balanceOf(liquidityProvider1), lp1InitialBalance, "LP1 should receive funds with price decrease");
        }
        
        // LP2 rebalances
        vm.startPrank(liquidityProvider2);
        (rebalanceAmount, isDeposit) = cycleManager.calculateLPRebalanceAmount(liquidityProvider2, PRICE_DECREASE);
        cycleManager.rebalancePool(liquidityProvider2, PRICE_DECREASE);
        vm.stopPrank();
        
        // Verify LP2 received funds
        if (rebalanceAmount > 0 && !isDeposit) {
            assertGt(reserveToken.balanceOf(liquidityProvider2), lp2InitialBalance, "LP2 should receive funds with price decrease");
        }
        
        // Verify final state
        uint256 currentCycle = cycleManager.cycleIndex();
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_ACTIVE), "Cycle state should return to ACTIVE");
        assertEq(currentCycle, initialCycle + 2, "Cycle index should increment");
        
        // Verify rebalance price is recorded correctly
        assertEq(cycleManager.cycleRebalancePrice(currentCycle - 1), PRICE_DECREASE, "Rebalance price should match");
    }
    
    /**
     * @notice Test LP rebalance with invalid price (outside high/low range)
     */
    function testLPRebalance_InvalidPrice() public {
        // Start offchain rebalance
        vm.prank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to simulate offchain rebalance period
        vm.warp(block.timestamp + 1 hours);
        
        // Start onchain rebalance with price range
        vm.prank(owner);
        assetOracle.setMarketOpen(false);
        updateOraclePriceWithOHLC(
            INITIAL_PRICE * 98 / 100, 
            INITIAL_PRICE * 105 / 100, 
            INITIAL_PRICE * 95 / 100, 
            INITIAL_PRICE
        );
        
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // Try to rebalance with price too high (above high limit)
        uint256 invalidHighPrice = INITIAL_PRICE * 106 / 100;
        vm.prank(liquidityProvider1);
        vm.expectRevert(IPoolCycleManager.InvalidRebalancePrice.selector);
        cycleManager.rebalancePool(liquidityProvider1, invalidHighPrice);
        
        // Try to rebalance with price too low (below low limit)
        uint256 invalidLowPrice = INITIAL_PRICE * 94 / 100;
        vm.prank(liquidityProvider1);
        vm.expectRevert(IPoolCycleManager.InvalidRebalancePrice.selector);
        cycleManager.rebalancePool(liquidityProvider1, invalidLowPrice);
        
        // Rebalance with valid price should succeed
        uint256 validPrice = INITIAL_PRICE * 100 / 100;
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, validPrice);
        
        // Verify rebalance was recorded
        assertEq(cycleManager.lastRebalancedCycle(liquidityProvider1), cycleManager.cycleIndex(), "LP1 should be recorded as rebalanced");
    }
    
    /**
     * @notice Test LP cannot rebalance twice in same cycle
     */
    function testLPRebalance_AlreadyRebalanced() public {
        // Start offchain rebalance
        vm.prank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to simulate offchain rebalance period
        vm.warp(block.timestamp + 1 hours);
        
        // Start onchain rebalance with price range
        vm.prank(owner);
        assetOracle.setMarketOpen(false);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // LP1 rebalances
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, INITIAL_PRICE);
        
        // LP1 tries to rebalance again in same cycle
        vm.prank(liquidityProvider1);
        vm.expectRevert(IPoolCycleManager.AlreadyRebalanced.selector);
        cycleManager.rebalancePool(liquidityProvider1, INITIAL_PRICE);
    }
    
    /**
     * @notice Test non-LP cannot rebalance
     */
    function testLPRebalance_NotLP() public {
        // Start offchain rebalance
        vm.prank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to simulate offchain rebalance period
        vm.warp(block.timestamp + 1 hours);
        
        // Start onchain rebalance
        vm.prank(owner);
        assetOracle.setMarketOpen(false);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // Non-LP tries to rebalance
        vm.prank(user1);
        vm.expectRevert(IPoolCycleManager.NotLP.selector);
        cycleManager.rebalancePool(user1, INITIAL_PRICE);
    }
    
    /**
     * @notice Test LP cannot rebalance for another LP
     */
    function testLPRebalance_Unauthorized() public {
        // Start offchain rebalance
        vm.prank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to simulate offchain rebalance period
        vm.warp(block.timestamp + 1 hours);
        
        // Start onchain rebalance
        vm.prank(owner);
        assetOracle.setMarketOpen(false);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // LP1 tries to rebalance for LP2
        vm.prank(liquidityProvider1);
        vm.expectRevert(IPoolCycleManager.UnauthorizedCaller.selector);
        cycleManager.rebalancePool(liquidityProvider2, INITIAL_PRICE);
    }
    
    // ==================== REBALANCE CALCULATION TESTS ====================
    
    /**
     * @notice Test calculation of LP rebalance amount
     */
    function testCalculateLPRebalanceAmount() public {
        // Put some user deposits to create non-zero asset supply
        vm.prank(user1);
        assetPool.depositRequest(
            adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6), 
            adjustAmountForDecimals(USER_DEPOSIT_AMOUNT * COLLATERAL_RATIO / 100, 6)
        );
        
        // Complete one cycle to mint assets
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Initialize onchain rebalance with price changes
        vm.prank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(PRICE_INCREASE);
        
        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to simulate offchain rebalance period
        vm.warp(block.timestamp + 1 hours);
        
        // Start onchain rebalance with higher price
        vm.prank(owner);
        assetOracle.setMarketOpen(false);
        updateOraclePriceWithOHLC(
            INITIAL_PRICE * 105 / 100, 
            PRICE_INCREASE * 110 / 100, 
            INITIAL_PRICE, 
            PRICE_INCREASE
        );
        
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // Calculate rebalance amounts
        (uint256 lp1Amount, bool lp1IsDeposit) = cycleManager.calculateLPRebalanceAmount(liquidityProvider1, PRICE_INCREASE);
        (uint256 lp2Amount, bool lp2IsDeposit) = cycleManager.calculateLPRebalanceAmount(liquidityProvider2, PRICE_INCREASE);
        
        // With price increase, LPs should need to deposit (positive rebalance)
        assertTrue(lp1IsDeposit, "LP1 should need to deposit with price increase");
        assertTrue(lp2IsDeposit, "LP2 should need to deposit with price increase");
        assertGt(lp1Amount, 0, "LP1 rebalance amount should be positive");
        assertGt(lp2Amount, 0, "LP2 rebalance amount should be positive");
        
        // Verify that with price decrease, calculation shows LP receiving funds
        (uint256 decreaseAmount, bool decreaseIsDeposit) = cycleManager.calculateLPRebalanceAmount(liquidityProvider1, PRICE_DECREASE);
        assertFalse(decreaseIsDeposit, "LP should receive funds with price decrease");
        assertGt(decreaseAmount, 0, "Decrease rebalance amount should be positive");
    }
    
    // ==================== SETTLEMENT TESTS ====================
    
    /**
     * @notice Test settlement when rebalance window expires
     */
    function testRebalanceLP_RebalanceExpired() public {
        // Put some user deposits to create non-zero asset supply
        vm.prank(user1);
        assetPool.depositRequest(
            adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6), 
            adjustAmountForDecimals(USER_DEPOSIT_AMOUNT * COLLATERAL_RATIO / 100, 6)
        );
        
        // Complete one cycle to mint assets
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Start offchain and onchain rebalance
        vm.prank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        
        vm.warp(block.timestamp + 1 hours);
        
        vm.prank(owner);
        assetOracle.setMarketOpen(false);
        updateOraclePriceWithOHLC(
            INITIAL_PRICE * 98 / 100, 
            INITIAL_PRICE * 105 / 100, 
            INITIAL_PRICE * 95 / 100, 
            INITIAL_PRICE
        );
        
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // Get rebalance parameters
        (uint256 rebalanceLength, , ) = poolStrategy.getCycleParams();
        
        // LP1 rebalances normally
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, INITIAL_PRICE);
        
        // LP2 doesn't rebalance yet
        
        // Advance time past rebalance window but before halt threshold
        vm.warp(block.timestamp + rebalanceLength - 10);
        
        // Settlement should fail before rebalance window expires
        vm.prank(liquidityProvider1);
        vm.expectRevert(IPoolCycleManager.OnChainRebalancingInProgress.selector);
        cycleManager.rebalanceLP(liquidityProvider2);
        
        // Advance time past rebalance window
        vm.warp(block.timestamp + 100);
        
        // Record LP2's position before settlement
        uint256 lastRebalancedCycleBefore = cycleManager.lastRebalancedCycle(liquidityProvider2);
        
        // Anyone can call rebalanceLP to settle LP2
        vm.prank(liquidityProvider1);
        cycleManager.rebalanceLP(liquidityProvider2);
        
        // Verify LP2 was settled
        uint256 lastRebalancedCycleAfter = cycleManager.lastRebalancedCycle(liquidityProvider2);
        
        // LP2 should be marked as rebalanced
        assertGt(lastRebalancedCycleAfter, lastRebalancedCycleBefore, "LP2 should be marked as rebalanced");
        
        // Verify cycle state after all LPs are rebalanced
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_ACTIVE), "Cycle state should be ACTIVE after all LPs settled");
        assertEq(cycleManager.rebalancedLPs(), 0, "No LPs should be pending rebalance");
    }
    
    /**
     * @notice Test force rebalance when halt threshold is reached
     */
    function testForceRebalanceLP_HaltThresholdReached() public {
        // Put some user deposits to create non-zero asset supply
        vm.prank(user1);
        assetPool.depositRequest(
            adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6), 
            adjustAmountForDecimals(USER_DEPOSIT_AMOUNT * COLLATERAL_RATIO / 100, 6)
        );
        
        // Complete one cycle to mint assets
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Start offchain and onchain rebalance
        vm.prank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        
        vm.warp(block.timestamp + 1 hours);
        
        vm.prank(owner);
        assetOracle.setMarketOpen(false);
        updateOraclePriceWithOHLC(
            INITIAL_PRICE * 98 / 100, 
            INITIAL_PRICE * 105 / 100, 
            INITIAL_PRICE * 95 / 100, 
            INITIAL_PRICE
        );
        
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // Get rebalance parameters
        (uint256 rebalanceLength, , uint256 haltThreshold) = poolStrategy.getCycleParams();
        
        // LP1 rebalances normally
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, INITIAL_PRICE);
        
        // LP2 doesn't rebalance
        
        // Try to force rebalance before halt threshold - should fail
        vm.warp(block.timestamp + rebalanceLength + 1);
        
        vm.prank(liquidityProvider1);
        vm.expectRevert(IPoolCycleManager.InvalidCycleState.selector);
        cycleManager.forceRebalanceLP(liquidityProvider2);
        
        // Advance time past halt threshold
        vm.warp(block.timestamp + haltThreshold);
        
        // Record LP2's position before force rebalance
        uint256 lastRebalancedCycleBefore = cycleManager.lastRebalancedCycle(liquidityProvider2);
        
        // Anyone can call forceRebalanceLP
        vm.prank(liquidityProvider1);
        cycleManager.forceRebalanceLP(liquidityProvider2);
        
        // Verify LP2 was force rebalanced
        uint256 lastRebalancedCycleAfter = cycleManager.lastRebalancedCycle(liquidityProvider2);
        
        // LP2 should be marked as rebalanced
        assertGt(lastRebalancedCycleAfter, lastRebalancedCycleBefore, "LP2 should be marked as rebalanced");
        
        // Verify cycle state after all LPs are rebalanced
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_HALTED), "Cycle state should be HALTED after force rebalance");
        assertEq(cycleManager.rebalancedLPs(), 0, "No LPs should be pending rebalance");
    }
    
    /**
     * @notice Test interest accrual during rebalancing
     */
    function testInterestAccrual() public {
        // Put some user deposits to create non-zero asset supply
        vm.prank(user1);
        assetPool.depositRequest(
            adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6), 
            adjustAmountForDecimals(USER_DEPOSIT_AMOUNT * COLLATERAL_RATIO / 100, 6)
        );
        
        // Complete one cycle to mint assets
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimAsset(user1);
                
        // Advance time
        vm.warp(block.timestamp + 30 days);
        
        // Start offchain rebalance which should accrue interest
        vm.prank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        
        // Start onchain rebalance which should accrue interest again
        vm.warp(block.timestamp + 1 hours);
        vm.prank(owner);
        assetOracle.setMarketOpen(false);
        updateOraclePrice(INITIAL_PRICE);
        
        // Record initial interest data
        uint256 initialCycleInterest =cycleManager.cumulativeInterestIndex(cycleManager.cycleIndex());
        uint256 initialInterestAmount =cycleManager.cycleInterestAmount();
        uint256 initialAccrualTime =cycleManager.lastInterestAccrualTimestamp();
        
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // Verify interest was accrued
        uint256 newCycleInterest = cycleManager.cumulativeInterestIndex(cycleManager.cycleIndex());
        uint256 newInterestAmount = cycleManager.cycleInterestAmount();
        uint256 newAccrualTime = cycleManager.lastInterestAccrualTimestamp();
        
        assertGt(newCycleInterest, initialCycleInterest, "Cycle interest should increase again");
        assertGt(newInterestAmount, initialInterestAmount, "Cycle interest amount should increase again");
        assertGt(newAccrualTime, initialAccrualTime, "Interest accrual timestamp should be updated again");
    }
    
    /**
     * @notice Test pool info view function
     */
    function testGetPoolInfo() public {
        // Get pool info
        (
            IPoolCycleManager.CycleState _cycleState,
            uint256 _cycleIndex,
            ,
            uint256 _lastCycleActionDateTime,
            ,
            ,
            uint256 _totalDepositRequests,
        ) = cycleManager.getPoolInfo();
        
        // Verify values
        assertEq(uint(_cycleState), uint(cycleManager.cycleState()), "Cycle state should match");
        assertEq(_cycleIndex, cycleManager.cycleIndex(), "Cycle index should match");
        assertEq(_lastCycleActionDateTime, cycleManager.lastCycleActionDateTime(), "Last cycle action time should match");
        
        // Add some deposits to verify they show up in pool info
        vm.prank(user1);
        assetPool.depositRequest(
            adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6), 
            adjustAmountForDecimals(USER_DEPOSIT_AMOUNT * COLLATERAL_RATIO / 100, 6)
        );
        
        (
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 newTotalDepositRequests,
        ) = cycleManager.getPoolInfo();
        
        assertGt(newTotalDepositRequests, _totalDepositRequests, "Total deposit requests should increase");
    }
    
    // ==================== POOL STATE INVARIANT TESTS ====================
    
    /**
     * @notice Test cycle transitions maintain correct state
     */
    function testCycleStateTransitions() public {
        // Initial state should be ACTIVE
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_ACTIVE), "Initial state should be ACTIVE");
        
        // ACTIVE -> OFFCHAIN_REBALANCING
        vm.prank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_REBALANCING_OFFCHAIN), "State should be OFFCHAIN_REBALANCING");
        
        // OFFCHAIN_REBALANCING -> ONCHAIN_REBALANCING
        vm.warp(block.timestamp + 1 hours);
        vm.prank(owner);
        assetOracle.setMarketOpen(false);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_REBALANCING_ONCHAIN), "State should be ONCHAIN_REBALANCING");
        
        // ONCHAIN_REBALANCING -> ACTIVE (after all LPs rebalance)
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, INITIAL_PRICE);
        
        vm.prank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, INITIAL_PRICE);
        
        assertEq(uint(cycleManager.cycleState()), uint(IPoolCycleManager.CycleState.POOL_ACTIVE), "State should return to ACTIVE");
        
        // Verify we can't skip states
        // ACTIVE -> ONCHAIN_REBALANCING (should fail)
        vm.prank(owner);
        assetOracle.setMarketOpen(false);
        updateOraclePrice(INITIAL_PRICE);
        
        vm.prank(owner);
        vm.expectRevert(IPoolCycleManager.InvalidCycleState.selector);
        cycleManager.initiateOnchainRebalance();
    }
    
    /**
     * @notice Test cycle index increments correctly
     */
    function testCycleIndexIncrement() public {
        uint256 initialCycleIndex = cycleManager.cycleIndex();
        
        // Complete a full cycle
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
        
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, INITIAL_PRICE);
        
        // Cycle index should not change yet
        assertEq(cycleManager.cycleIndex(), initialCycleIndex, "Cycle index should not change during rebalance");
        
        // Complete rebalance
        vm.prank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, INITIAL_PRICE);
        
        // Cycle index should increment
        assertEq(cycleManager.cycleIndex(), initialCycleIndex + 1, "Cycle index should increment after rebalance");
        
        // Complete another cycle
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
        
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, INITIAL_PRICE);
        
        vm.prank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, INITIAL_PRICE);
        
        // Cycle index should increment again
        assertEq(cycleManager.cycleIndex(), initialCycleIndex + 2, "Cycle index should increment twice after two cycles");
    }
    
}