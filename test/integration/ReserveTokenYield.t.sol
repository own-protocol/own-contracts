// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "../utils/ProtocolTestUtils.sol";
import "../mocks/MockYieldToken.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "forge-std/console2.sol";

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
    uint256 constant PRECISION = 1e18; // Precision for calculations

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
        yieldToken = new MockYieldToken(
            "Yield USD Coin",
            "yUSDC",
            6,
            YIELD_RATE_PER_DAY
        );

        // Deploy oracle
        assetOracle = new MockAssetOracle("xTSLA", DEFAULT_SOURCE_HASH);

        // Deploy strategy
        poolStrategy = new DefaultPoolStrategy();

        // Deploy implementation contracts
        AssetPool assetPoolImpl = new AssetPool();
        PoolCycleManager cycleManagerImpl = new PoolCycleManager();
        PoolLiquidityManager liquidityManagerImpl = new PoolLiquidityManager();

        // Clone implementations
        address assetPoolClone = Clones.clone(address(assetPoolImpl));
        address cycleManagerClone = Clones.clone(address(cycleManagerImpl));
        address liquidityManagerClone = Clones.clone(
            address(liquidityManagerImpl)
        );

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
        poolStrategy.setCycleParams(rebalancePeriod, oracleUpdateThreshold);
        poolStrategy.setInterestRateParams(
            baseRate,
            rate1,
            maxRate,
            utilTier1,
            utilTier2
        );
        poolStrategy.setLPLiquidityParams(
            lpHealthyRatio,
            lpLiquidationThreshold,
            lpLiquidationReward,
            lpMinCommitment
        );
        poolStrategy.setProtocolFeeParams(protocolFee, feeRecipient);
        poolStrategy.setUserCollateralParams(
            userhealthyRatio,
            userLiquidationThreshold
        );
        poolStrategy.setHaltParams(
            haltThreshold,
            haltLiquidityPercent,
            haltFeePercent,
            haltRequestThreshold
        );

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
        uint256 liquidityAmount = adjustAmountForDecimals(
            LP_LIQUIDITY_AMOUNT,
            6
        );

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
        uint256 receivedAmount = yieldToken.balanceOf(user1) -
            balanceBeforeClaim;
        assertGt(
            receivedAmount,
            expectedBaseAmount,
            "User should receive base amount plus yield"
        );
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
        uint256 receivedAmount = yieldToken.balanceOf(user1) -
            balanceBeforeClaim;
        assertGt(
            receivedAmount,
            totalAmount,
            "User should receive original amount plus yield"
        );

        // Verify user position is completely cleared
        (
            uint256 userAssetAmount,
            uint256 userDepositAmount,
            uint256 userCollateralAmount
        ) = assetPool.userPositions(user1);
        assertEq(userAssetAmount, 0, "User asset position should be zero");
        assertEq(userDepositAmount, 0, "User deposit position should be zero");
        assertEq(
            userCollateralAmount,
            0,
            "User collateral position should be zero"
        );
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
        (, , uint256 userCollateralAfter) = assetPool.userPositions(user1);
        assertEq(
            userCollateralAfter,
            collateralAmount + additionalCollateral,
            "User collateral should increase by added amount"
        );
    }

    /**
     * @notice Test exit LP inactive by reducing liquidity with yield accrued
     */
    function testExitLPWithYield() public {
        // Get LP's current position
        IPoolLiquidityManager.LPPosition
            memory initialPosition = liquidityManager.getLPPosition(
                liquidityProvider1
            );
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
        assertFalse(
            isLPActive,
            "LP should be inactive after reducing liquidity to zero"
        );

        vm.startPrank(liquidityProvider1);
        liquidityManager.exitPool();
        vm.stopPrank();

        // Verify LP received collateral plus yield
        uint256 receivedAmount = yieldToken.balanceOf(liquidityProvider1) -
            balanceBeforeExit;
        assertGt(
            receivedAmount,
            initialCollateral,
            "LP should receive collateral plus yield"
        );
    }

    function testAccurateYieldIndexUpdatesSingleUser() public {
        // ---- 1️⃣ User1 deposits in Cycle 0 ----
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;

        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();

        completeCycleWithPriceChange(INITIAL_PRICE);

        vm.prank(user1);
        assetPool.claimAsset(user1);

        uint256 assetBalance = assetToken.balanceOf(user1);
        uint256 yieldIndexU1 = assetPool.userReserveYieldIndex(user1);

        // Cycle 1: Check initial yield
        _testCycleYield(
            assetBalance,
            INITIAL_PRICE,
            collateralAmount,
            0,
            yieldIndexU1
        );

        // Cycle 2: Price increases 10%
        uint256 assetPriceC1 = INITIAL_PRICE + (INITIAL_PRICE * 10) / 100;
        completeCycleWithPriceChange(assetPriceC1);
        uint256 expectedYield1 = _getExpectedYield(
            assetBalance,
            INITIAL_PRICE,
            collateralAmount,
            0
        );
        _testCycleYield(
            assetBalance,
            INITIAL_PRICE,
            collateralAmount,
            expectedYield1,
            yieldIndexU1
        );

        // Cycle 3: Continue with new price
        completeCycleWithPriceChange(assetPriceC1);
        uint256 expectedYield2 = _getExpectedYield(
            assetBalance,
            INITIAL_PRICE,
            collateralAmount,
            expectedYield1
        );
        _testCycleYield(
            assetBalance,
            assetPriceC1,
            collateralAmount,
            expectedYield2,
            yieldIndexU1
        );
    }

    /**
     * @notice Test accurate yield index updates for multiple users
     * @dev This test verifies that the yield index is updated accurately for multiple users
     * when they deposit and redeem assets.
     * user1 deposits in current cycle, user2 joins in next cycle at same price and the asset price increases
     */
    function testAccurateYieldIndexUpdatesMultipleUsers() public {
        // ============ Cycle 0 → 1 (User1 joins) ============
        uint256 depU1 = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 colU1 = (depU1 * COLLATERAL_RATIO) / 100;

        vm.startPrank(user1);
        assetPool.depositRequest(depU1, colU1);
        vm.stopPrank();

        completeCycleWithPriceChange(INITIAL_PRICE);

        vm.prank(user1);
        assetPool.claimAsset(user1);

        uint256 assetBalanceU1 = assetToken.balanceOf(user1);
        uint256 user1YieldIndex = assetPool.userReserveYieldIndex(user1);
        uint256 expectedYieldU1C1 = _getExpectedYield(
            assetBalanceU1,
            INITIAL_PRICE,
            colU1,
            0
        );

        _testUserYield(
            assetBalanceU1,
            user1YieldIndex,
            expectedYieldU1C1,
            "U1C1"
        );

        // ============ Cycle 1 → 2 (User2 joins) ============
        uint256 depU2 = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 colU2 = (depU2 * COLLATERAL_RATIO) / 100;

        vm.startPrank(user2);
        assetPool.depositRequest(depU2, colU2);
        vm.stopPrank();

        uint256 assetPriceC2 = INITIAL_PRICE + (INITIAL_PRICE * 10) / 100;
        completeCycleWithPriceChange(assetPriceC2);

        vm.prank(user2);
        assetPool.claimAsset(user2);

        // Test User1 yield in Cycle 2
        assetBalanceU1 = assetToken.balanceOf(user1);
        uint256 expectedYieldU1C2 = _getExpectedYield(
            assetBalanceU1,
            INITIAL_PRICE,
            colU1,
            expectedYieldU1C1
        );
        _testUserYield(
            assetBalanceU1,
            user1YieldIndex,
            expectedYieldU1C2,
            "U1C2"
        );

        // Test User2 yield in Cycle 2
        uint256 assetBalanceU2 = assetToken.balanceOf(user2);
        uint256 user2YieldIndex = assetPool.userReserveYieldIndex(user2);
        uint256 expectedYieldU2C2 = _getExpectedYield(
            assetBalanceU2,
            INITIAL_PRICE,
            colU2,
            0
        );
        _testUserYield(
            assetBalanceU2,
            user2YieldIndex,
            expectedYieldU2C2,
            "U2C2"
        );

        // next cycle, asset price remains the same
        completeCycleWithPriceChange(assetPriceC2);

        // Test User1 yield in Cycle 3
        assetBalanceU1 = assetToken.balanceOf(user1);
        uint256 expectedYieldU1C3 = _getExpectedYield(
            assetBalanceU1,
            assetPriceC2,
            colU1,
            expectedYieldU1C2
        );
        _testUserYield(
            assetBalanceU1,
            user1YieldIndex,
            expectedYieldU1C3,
            "U1C3"
        );

        // Test User2 yield in Cycle 3
        assetBalanceU2 = assetToken.balanceOf(user2);
        uint256 expectedYieldU2C3 = _getExpectedYield(
            assetBalanceU2,
            assetPriceC2,
            colU2,
            expectedYieldU2C2
        );
        _testUserYield(
            assetBalanceU2,
            user2YieldIndex,
            expectedYieldU2C3,
            "U2C3"
        );
    }

    /**
     * @notice Test accurate yield generated for multiple users
     * @dev This test verifies that the yield is generated accurately for multiple users
     * when they deposit and redeem assets.
     * user1 deposits in current cycle, asset price increases in next cycle, user 2 joins in this cycle
     * user1 redeems half of their assets in cycle 2
     */
    function testAccurateYieldGeneratedForMultipleUsers() public {
        // ============ Cycle 0 → 1 (User1 joins) ============
        uint256 depU1 = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 colU1 = (depU1 * COLLATERAL_RATIO) / 100;

        vm.startPrank(user1);
        assetPool.depositRequest(depU1, colU1);
        vm.stopPrank();

        completeCycleWithPriceChange(INITIAL_PRICE);

        vm.prank(user1);
        assetPool.claimAsset(user1);

        uint256 assetBalanceU1 = assetToken.balanceOf(user1);
        uint256 user1YieldIndex = assetPool.userReserveYieldIndex(user1);
        uint256 expectedYieldU1 = _getExpectedYield(
            assetBalanceU1,
            INITIAL_PRICE,
            colU1,
            0
        );
        _testUserYield(
            assetBalanceU1,
            user1YieldIndex,
            expectedYieldU1,
            "U1C1"
        );

        // ============ Cycle 1 → 2 (User2 joins, price +10%) ============
        uint256 depU2 = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 colU2 = (depU2 * COLLATERAL_RATIO) / 100;

        vm.startPrank(user2);
        assetPool.depositRequest(depU2, colU2);
        vm.stopPrank();

        uint256 assetPriceC2 = INITIAL_PRICE + (INITIAL_PRICE * 10) / 100;
        completeCycleWithPriceChange(assetPriceC2);

        vm.prank(user2);
        assetPool.claimAsset(user2);

        // User1's yield
        assetBalanceU1 = assetToken.balanceOf(user1);
        expectedYieldU1 = _getExpectedYield(
            assetBalanceU1,
            INITIAL_PRICE,
            colU1,
            expectedYieldU1
        );
        _testUserYield(
            assetBalanceU1,
            user1YieldIndex,
            expectedYieldU1,
            "U1C2"
        );

        // User2's yield
        uint256 assetBalanceU2 = assetToken.balanceOf(user2);
        uint256 user2YieldIndex = assetPool.userReserveYieldIndex(user2);
        uint256 expectedYieldU2 = _getExpectedYield(
            assetBalanceU2,
            INITIAL_PRICE,
            colU2,
            0
        );
        _testUserYield(
            assetBalanceU2,
            user2YieldIndex,
            expectedYieldU2,
            "U2C2"
        );

        // ============ Cycle 2 → 3 (Price -20%) ============
        uint256 assetPriceC3 = assetPriceC2 - (assetPriceC2 * 20) / 100;
        completeCycleWithPriceChange(assetPriceC3);

        // User1's yield
        assetBalanceU1 = assetToken.balanceOf(user1);
        expectedYieldU1 = _getExpectedYield(
            assetBalanceU1,
            assetPriceC2,
            colU1,
            expectedYieldU1
        );
        _testUserYield(
            assetBalanceU1,
            user1YieldIndex,
            expectedYieldU1,
            "U1C3"
        );

        // User2's yield
        assetBalanceU2 = assetToken.balanceOf(user2);
        expectedYieldU2 = _getExpectedYield(
            assetBalanceU2,
            assetPriceC2,
            colU2,
            expectedYieldU2
        );
        _testUserYield(
            assetBalanceU2,
            user2YieldIndex,
            expectedYieldU2,
            "U2C3"
        );

        // ============ Cycle 3 → 4 (User1 redeems) ============
        vm.startPrank(user1);
        assetToken.approve(address(assetPool), assetBalanceU1);
        assetPool.redemptionRequest(assetBalanceU1);
        vm.stopPrank();

        completeCycleWithPriceChange(assetPriceC3);

        vm.prank(user1);
        assetPool.claimReserve(user1);

        // User1's yield after redemption
        expectedYieldU1 = _getExpectedYield(
            assetBalanceU1,
            assetPriceC3,
            colU1,
            expectedYieldU1
        );
        _testUserYield(
            assetBalanceU1,
            user1YieldIndex,
            expectedYieldU1,
            "U1C4"
        );

        // User2's yield
        assetBalanceU2 = assetToken.balanceOf(user2);
        expectedYieldU2 = _getExpectedYield(
            assetBalanceU2,
            assetPriceC3,
            colU2,
            expectedYieldU2
        );
        _testUserYield(
            assetBalanceU2,
            user2YieldIndex,
            expectedYieldU2,
            "U2C4"
        );

        // ============ Cycle 4 → 5 (Price unchanged) ============
        completeCycleWithPriceChange(assetPriceC3);
        assetBalanceU1 = assetToken.balanceOf(user1);

        // User1's yield
        // Since user1 has claimed the reserves, they do not have any deposits (including collateral and yields) in the pool
        expectedYieldU1 = _getExpectedYield(assetBalanceU1, assetPriceC3, 0, 0);
        _testUserYield(
            assetBalanceU1,
            user1YieldIndex,
            expectedYieldU1,
            "U1C5"
        );

        // User2's yield
        assetBalanceU2 = assetToken.balanceOf(user2);
        expectedYieldU2 = _getExpectedYield(
            assetBalanceU2,
            assetPriceC3,
            colU2,
            expectedYieldU2
        );
        _testUserYield(
            assetBalanceU2,
            user2YieldIndex,
            expectedYieldU2,
            "U2C5"
        );
    }

    //
    // ─── Helper Functions ───────────────────────────────────────────
    //

    /**
     * @notice Test yield for a specific user at current cycle
     * @param assetBalance User's asset token balance
     * @param userYieldIndex User's stored yield index
     * @param expectedYield Expected yield amount
     * @param label Label for logging
     */
    function _testUserYield(
        uint256 assetBalance,
        uint256 userYieldIndex,
        uint256 expectedYield,
        string memory label
    ) public view {
        uint256 currentCycle = cycleManager.cycleIndex();
        uint256 globalYieldIndex = assetPool.reserveYieldIndex(currentCycle);

        uint256 actualYield = Math.mulDiv(
            assetBalance,
            globalYieldIndex - userYieldIndex,
            PRECISION
        );

        console2.log(string.concat("Expected yield ", label), expectedYield);
        console2.log(string.concat("Actual yield ", label), actualYield);
        _assertYieldWithinTolerance(expectedYield, actualYield);
    }

    /**
     * @notice Test yield for a specific cycle
     * @param assetBalance User's asset token balance
     * @param price Asset price for calculating asset value
     * @param collateralAmount User's collateral amount
     * @param previousExpectedYield Previously accumulated expected yield
     * @param userYieldIndex User's stored yield index
     */
    function _testCycleYield(
        uint256 assetBalance,
        uint256 price,
        uint256 collateralAmount,
        uint256 previousExpectedYield,
        uint256 userYieldIndex
    ) public view {
        uint256 currentCycle = cycleManager.cycleIndex();
        uint256 globalYieldIndex = assetPool.reserveYieldIndex(currentCycle);

        uint256 actualYield = Math.mulDiv(
            assetBalance,
            globalYieldIndex - userYieldIndex,
            PRECISION
        );

        uint256 expectedYield = _getExpectedYield(
            assetBalance,
            price,
            collateralAmount,
            previousExpectedYield
        );

        _assertYieldWithinTolerance(expectedYield, actualYield);
    }

    /**
     * @notice Calculate expected yield based on asset value and previous yield
     * @param assetBalance User's asset token balance (18 decimals)
     * @param price Asset price (18 decimals)
     * @param collateralAmount User's collateral (6 decimals)
     * @param previousYield Previously accumulated yield (6 decimals)
     * @return Expected yield in reserve decimals (6 decimals)
     */
    function _getExpectedYield(
        uint256 assetBalance,
        uint256 price,
        uint256 collateralAmount,
        uint256 previousYield
    ) internal view returns (uint256) {
        uint256 reserveToAssetDecimalFactor = assetPool
            .reserveToAssetDecimalFactor();
        uint256 assetValue = _calcAssetValue(
            assetBalance,
            price,
            reserveToAssetDecimalFactor
        );
        return
            previousYield +
            ((assetValue + collateralAmount + previousYield) *
                YIELD_RATE_PER_DAY) /
            BPS;
    }

    function _calcAssetValue(
        uint256 assetShares,
        uint256 price,
        uint256 reserveToAssetDecimalFactor
    ) internal pure returns (uint256) {
        // Converts asset shares (1e18) and price (1e18) to reserve decimals (1e6)
        return
            Math.mulDiv(
                assetShares,
                price,
                PRECISION * reserveToAssetDecimalFactor
            );
    }

    function _calcShare(
        uint256 userAssetValue,
        uint256 totalAssetValue
    ) internal pure returns (uint256) {
        // Returns user share as a fraction scaled to 1e18 (PRECISION)
        return
            totalAssetValue > 0
                ? Math.mulDiv(userAssetValue, PRECISION, totalAssetValue)
                : 0;
    }

    function _calcPercentDiff(
        uint256 expected,
        uint256 actual
    ) internal pure returns (uint256) {
        if (expected == 0) return 0;
        uint256 diff = expected > actual
            ? expected - actual
            : actual - expected;
        return (diff * 10000) / expected; // basis points (1% = 100)
    }

    function _assertYieldWithinTolerance(
        uint256 expected,
        uint256 actual
    ) internal pure {
        uint256 diffBp = _calcPercentDiff(expected, actual);
        // Allow 4% difference tolerance = 400 bps
        assertLt(diffBp, 400, "Percent difference < 4%");
    }
}
