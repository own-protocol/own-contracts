// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "../utils/ProtocolTestUtils.sol";
import "../mocks/MockYieldToken.sol";

/**
 * @title ReserveTokenYield
 * @notice Tests for reserve yield functionality in the protocol
 * @dev Tests yield accrual and distribution during various operations
 */
contract ReserveTokenYield is ProtocolTestUtils {
    // Constants for testing
    uint256 constant INITIAL_PRICE = 100 * 1e18; // $100 per asset
    uint256 constant USER_INITIAL_BALANCE = 100_000;
    uint256 constant LP_INITIAL_BALANCE = 1_000_000;
    uint256 constant LP_LIQUIDITY_AMOUNT = 500_000;
    uint256 constant USER_DEPOSIT_AMOUNT = 10_000;
    uint256 constant COLLATERAL_RATIO = 20; // 20%
    
    // Yield-related constants
    uint256 constant YIELD_RATE_PER_DAY = 50; // 0.5% per day
    uint256 constant YIELD_TEST_PERIOD = 30 days;
    
    // Mock yield token to replace reserve token
    MockYieldToken public yieldToken;
    
    function setUp() public {
        // Deploy protocol with mock yield token
        _deployProtocolWithYieldToken();
        
        // Enable yield bearing in the strategy
        vm.startPrank(owner);
        poolStrategy.setIsYieldBearing();
        vm.stopPrank();
    }
    
    /**
     * @notice Deploy protocol with our custom yield token
     */
    function _deployProtocolWithYieldToken() internal {
        // Create test accounts
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        liquidityProvider1 = makeAddr("lp1");
        liquidityProvider2 = makeAddr("lp2");
        
        // Deploy mock contracts
        yieldToken = new MockYieldToken("Yield USD Coin", "yUSDC", 6, YIELD_RATE_PER_DAY);
        
        // Deploy oracle
        assetOracle = new MockAssetOracle(
            "xTSLA",
            DEFAULT_SOURCE_HASH
        );
        
        // Deploy strategy
        poolStrategy = new DefaultPoolStrategy();

        // Deploy implementation contracts
        AssetPool assetPoolImpl = new AssetPool();
        PoolCycleManager cycleManagerImpl = new PoolCycleManager();
        PoolLiquidityManager liquidityManagerImpl = new PoolLiquidityManager();
        
        // Clone implementations
        address assetPoolClone = Clones.clone(address(assetPoolImpl));
        address cycleManagerClone = Clones.clone(address(cycleManagerImpl));
        address liquidityManagerClone = Clones.clone(address(liquidityManagerImpl));
        
        // Cast to contracts
        assetPool = AssetPool(payable(assetPoolClone));
        cycleManager = PoolCycleManager(cycleManagerClone);
        liquidityManager = PoolLiquidityManager(payable(liquidityManagerClone));
        
        // Initialize AssetPool with yield token as reserve token
        assetPool.initialize(
            address(yieldToken),
            "xTSLA",
            address(assetOracle),
            address(assetPool),
            address(cycleManager),
            address(liquidityManager),
            address(poolStrategy)
        );
        
        // Get asset token address created by AssetPool
        address assetTokenAddress = address(assetPool.assetToken());
        assetToken = xToken(assetTokenAddress);
        
        // Initialize CycleManager
        cycleManager.initialize(
            address(yieldToken),
            assetTokenAddress,
            address(assetOracle),
            address(assetPool),
            address(cycleManager),
            address(liquidityManager),
            address(poolStrategy),
            owner
        );
        
        // Initialize LiquidityManager
        liquidityManager.initialize(
            address(yieldToken),
            assetTokenAddress,
            address(assetOracle),
            address(assetPool),
            address(cycleManager),
            address(liquidityManager),
            address(poolStrategy)
        );

        // Set strategy parameters
        poolStrategy.setCycleParams(rebalancePeriod, oracleUpdateThreshold, haltThreshold);
        poolStrategy.setInterestRateParams(baseRate, rate1, maxRate, utilTier1, utilTier2);
        poolStrategy.setLPLiquidityParams(lpHealthyRatio, lpLiquidationThreshold, lpLiquidationReward);
        poolStrategy.setProtocolFeeParams(protocolFee, feeRecipient);
        poolStrategy.setUserCollateralParams(userhealthyRatio, userLiquidationThreshold);
        
        _fundAccountsWithYieldToken();
        
        // Setup initial price
        updateOraclePrice(INITIAL_PRICE);
        
        // Setup liquidity providers
        _setupLiquidityProviders();
    }
    
    /**
     * @notice Fund accounts with yield tokens
     */
    function _fundAccountsWithYieldToken() internal {
        uint256 userAmount = adjustAmountForDecimals(USER_INITIAL_BALANCE, 6);
        uint256 lpAmount = adjustAmountForDecimals(LP_INITIAL_BALANCE, 6);
        
        yieldToken.mint(user1, userAmount);
        yieldToken.mint(user2, userAmount);
        yieldToken.mint(user3, userAmount);
        yieldToken.mint(liquidityProvider1, lpAmount);
        yieldToken.mint(liquidityProvider2, lpAmount);
        
        // Approve spending for accounts
        vm.startPrank(user1);
        yieldToken.approve(address(assetPool), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        yieldToken.approve(address(assetPool), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user3);
        yieldToken.approve(address(assetPool), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(liquidityProvider1);
        yieldToken.approve(address(liquidityManager), type(uint256).max);
        yieldToken.approve(address(cycleManager), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(liquidityProvider2);
        yieldToken.approve(address(liquidityManager), type(uint256).max);
        yieldToken.approve(address(cycleManager), type(uint256).max);
        vm.stopPrank();
    }
    
    /**
     * @notice Setup liquidity providers
     */
    function _setupLiquidityProviders() internal {
        uint256 liquidityAmount = adjustAmountForDecimals(LP_LIQUIDITY_AMOUNT, 6);
        
        // First add liquidity to the pool
        vm.startPrank(liquidityProvider1);
        liquidityManager.addLiquidity(liquidityAmount / 2);
        vm.stopPrank();
        
        vm.startPrank(liquidityProvider2);
        liquidityManager.addLiquidity(liquidityAmount / 2);
        vm.stopPrank();
        
        // Complete initial setup to activate the pool
        vm.startPrank(owner);
        // Market should be open for offchain rebalance
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INITIAL_PRICE);
        cycleManager.initiateOffchainRebalance();
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        
        // Market should be closed for onchain rebalance
        assetOracle.setMarketOpen(false);
        updateOraclePrice(INITIAL_PRICE);
        cycleManager.initiateOnchainRebalance();
        vm.stopPrank();
        
        // LPs rebalance their positions
        vm.startPrank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, INITIAL_PRICE);
        vm.stopPrank();
        
        vm.startPrank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, INITIAL_PRICE);
        vm.stopPrank();
        
        // Set market back to open for normal operations
        vm.startPrank(owner);
        assetOracle.setMarketOpen(true);
        vm.stopPrank();
    }
    
    /**
     * @notice Test deposit and claim with yield accrual
     */
    function testDepositAndClaimWithYield() public {
        // User1 deposits tokens
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        uint256 totalAmount = depositAmount + collateralAmount;
        
        uint256 initialUserBalance = yieldToken.balanceOf(user1);
    
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Verify user balance decreased by exact amount
        assertEq(
            yieldToken.balanceOf(user1),
            initialUserBalance - totalAmount,
            "User balance should decrease by exact deposit + collateral amount"
        );
        
        // Complete cycle
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // User claims asset tokens
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Record initial asset amount
        uint256 assetAmount = assetToken.balanceOf(user1);
        assertGt(assetAmount, 0, "User should have received asset tokens");
        
        // Advance time for yield to accrue
        vm.warp(block.timestamp + YIELD_TEST_PERIOD);
        
        // User redeems half of assets
        uint256 redeemAmount = assetAmount / 2;
        
        vm.startPrank(user1);
        assetToken.approve(address(assetPool), redeemAmount);
        assetPool.redemptionRequest(redeemAmount);
        vm.stopPrank();
        
        // Complete another cycle
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // Record balance before claiming reserves
        uint256 balanceBeforeClaim = yieldToken.balanceOf(user1);
        
        // User claims reserve tokens
        vm.prank(user1);
        assetPool.claimReserve(user1);
        
        // Calculate expected base amount without yield
        uint256 expectedBaseAmount = (totalAmount / 2); // Half of total deposit + collateral
        
        // Verify user received at least the base amount plus some yield
        uint256 receivedAmount = yieldToken.balanceOf(user1) - balanceBeforeClaim;
        assertGt(receivedAmount, expectedBaseAmount, "User should receive base amount plus yield");
    }
    
    /**
     * @notice Test full redemption with yield accrual
     */
    function testFullRedemptionWithYield() public {
        // User1 deposits tokens
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        uint256 totalAmount = depositAmount + collateralAmount;
                
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Complete cycle
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // User claims asset tokens
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        uint256 assetAmount = assetToken.balanceOf(user1);
        
        // Advance time for yield to accrue
        vm.warp(block.timestamp + YIELD_TEST_PERIOD);
        
        // User redeems all assets
        vm.startPrank(user1);
        assetToken.approve(address(assetPool), assetAmount);
        assetPool.redemptionRequest(assetAmount);
        vm.stopPrank();
        
        // Complete another cycle
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // Record balance before claiming reserves
        uint256 balanceBeforeClaim = yieldToken.balanceOf(user1);
        
        // User claims reserve tokens
        vm.prank(user1);
        assetPool.claimReserve(user1);
        
        // Verify user received at least the original amount plus some yield
        uint256 receivedAmount = yieldToken.balanceOf(user1) - balanceBeforeClaim;
        assertGt(receivedAmount, totalAmount, "User should receive original amount plus yield");
        
        // Verify user position is completely cleared
        (uint256 userAssetAmount, uint256 userDepositAmount, uint256 userCollateralAmount) = assetPool.userPositions(user1);
        assertEq(userAssetAmount, 0, "User asset position should be zero");
        assertEq(userDepositAmount, 0, "User deposit position should be zero");
        assertEq(userCollateralAmount, 0, "User collateral position should be zero");
    }
    
    /**
     * @notice Test adding collateral with yield accrual
     */
    function testAddCollateralWithYield() public {
        // User1 deposits tokens
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Complete cycle
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // User claims asset tokens
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Advance time for yield to accrue
        vm.warp(block.timestamp + YIELD_TEST_PERIOD);
        
        // Add additional collateral
        uint256 additionalCollateral = adjustAmountForDecimals(5_000, 6);
        uint256 balanceBeforeAddCollateral = yieldToken.balanceOf(user1);
        
        vm.startPrank(user1);
        assetPool.addCollateral(user1, additionalCollateral);
        vm.stopPrank();
        
        assertEq(
            yieldToken.balanceOf(user1),
            balanceBeforeAddCollateral - additionalCollateral,
            "User balance should decrease by exact collateral amount"
        );
        
        // Get user's collateral after adding
        (,,uint256 userCollateralAfter) = assetPool.userPositions(user1);
        assertEq(userCollateralAfter, collateralAmount + additionalCollateral, "User collateral should increase by added amount");
    }
    
    /**
     * @notice Test reducing collateral with yield accrual
     */
    function testReduceCollateralWithYield() public {
        // User1 deposits tokens with extra collateral
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 minCollateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        uint256 extraCollateralAmount = minCollateralAmount * 2;  // Double the minimum
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, extraCollateralAmount);
        vm.stopPrank();
        
        // Complete cycle
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // User claims asset tokens
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Advance time for yield to accrue
        vm.warp(block.timestamp + YIELD_TEST_PERIOD);
        
        // Calculate excess collateral that can be withdrawn
        uint256 excessCollateral = extraCollateralAmount - minCollateralAmount;
        uint256 balanceBeforeReduce = yieldToken.balanceOf(user1);
        
        // Reduce collateral
        vm.startPrank(user1);
        assetPool.reduceCollateral(excessCollateral);
        vm.stopPrank();
        
        // Check received amount includes yield
        uint256 receivedAmount = yieldToken.balanceOf(user1) - balanceBeforeReduce;
        assertGt(receivedAmount, excessCollateral, "User should receive excess collateral plus yield");
        
        // Verify user's remaining collateral
        (,,uint256 userCollateralAfter) = assetPool.userPositions(user1);
        assertEq(userCollateralAfter, minCollateralAmount, "User should have minimum collateral remaining");
    }
    
    /**
     * @notice Test exit LP inactive by reducing liquidity with yield accrued
     */
    function testExitLPWithYield() public {
        // Get LP's current position
        IPoolLiquidityManager.LPPosition memory initialPosition = liquidityManager.getLPPosition(liquidityProvider1);
        uint256 initialCollateral = initialPosition.collateralAmount;
        uint256 initialLiquidity = initialPosition.liquidityCommitment;
        
        // Advance time for yield to accrue
        vm.warp(block.timestamp + YIELD_TEST_PERIOD);
        
        // Complete a cycle to process the new LP
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // Reduce all liquidity for LP1
        vm.startPrank(liquidityProvider1);
        liquidityManager.reduceLiquidity(initialLiquidity);
        vm.stopPrank();

        uint256 balanceBeforeExit = yieldToken.balanceOf(liquidityProvider1);
    
        // Complete cycle to process the request
        completeCycleWithPriceChange(INITIAL_PRICE);
    
        // LP should be inactive now
        bool isLPActive = liquidityManager.isLPActive(liquidityProvider1);
        assertFalse(isLPActive, "LP should be inactive after reducing liquidity to zero");

        vm.startPrank(liquidityProvider1);
        liquidityManager.exitPool();
        vm.stopPrank();

        // Verify LP received collateral plus yield
        uint256 receivedAmount = yieldToken.balanceOf(liquidityProvider1) - balanceBeforeExit;
        assertGt(receivedAmount, initialCollateral, "LP should receive collateral plus yield");
    }
}