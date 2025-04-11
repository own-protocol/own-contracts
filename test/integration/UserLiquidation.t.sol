// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "../utils/ProtocolTestUtils.sol";

/**
 * @title UserLiquidationTest
 * @notice Tests for the user liquidation functionality
 * @dev Tests conditions that make a position liquidatable, reward calculation, claim process, and edge cases
 */
contract UserLiquidationTest is ProtocolTestUtils {
    // Base amounts (will be adjusted based on token decimals)
    uint256 constant INITIAL_PRICE = 100 * 1e18; // $100.00 per asset (always 18 decimals)
    uint256 constant USER_INITIAL_BALANCE = 100_000; 
    uint256 constant LP_INITIAL_BALANCE = 1_000_000;
    uint256 constant LP_LIQUIDITY_AMOUNT = 500_000;
    uint256 constant USER_DEPOSIT_AMOUNT = 10_000;
    uint256 constant COLLATERAL_RATIO = 20; // 20% collateral

    // Test parameters
    uint256 constant LIQUIDATION_THRESHOLD = 1250; // 12.5% from strategy

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
     * @notice Test that a user position is not liquidatable initially
     */
    function testInitialPositionNotLiquidatable() public {
        // User1 deposits
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Complete cycle
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // User1 claims assets
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Check health status - should be healthy (3)
        uint8 health = poolStrategy.getUserCollateralHealth(address(assetPool), user1);
        assertEq(health, 3, "User position should be healthy initially");
        
        // Verify not liquidatable
        assertFalse(isUserLiquidatable(user1), "User should not be liquidatable initially");
    }

    /**
     * @notice Test position becomes liquidatable when price increases significantly
     */
    function testPositionLiquidatableWithPriceIncrease() public {
        // User1 deposits
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Complete cycle with initial price
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // User1 claims assets
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Still healthy after first cycle
        uint8 initialHealth = poolStrategy.getUserCollateralHealth(address(assetPool), user1);
        assertEq(initialHealth, 3, "User position should be healthy after first cycle");
        
        // Increase price by 45% for multiple cycles until liquidatable
        uint256 currentPrice = INITIAL_PRICE;
        uint8 health;
        
        do {
            // Increase price by 45% (maximum without triggering split detection)
            currentPrice = (currentPrice * 145) / 100;
            completeCycleWithPriceChange(currentPrice);
            
            health = poolStrategy.getUserCollateralHealth(address(assetPool), user1);
            
            // Exit loop if liquidatable or after too many attempts
            if (health == 1) break;
        } while (health > 1);
        
        // Now position should be liquidatable
        assertEq(health, 1, "User position should be liquidatable after price increases");
        assertTrue(isUserLiquidatable(user1), "User should be liquidatable");
    }

    /**
     * @notice Test position becomes liquidatable with interest accrual
     * @dev This simulates many cycles passing to accumulate significant interest
     */
    function testPositionLiquidatableWithInterestAccrual() public {
        // User1 deposits
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Complete cycle with initial price
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // User1 claims assets
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Maintain price but advance time significantly to accrue interest
        uint8 health;
        uint256 cycle = 0;
        
        do {
            // Advance time significantly to accrue more interest
            vm.warp(block.timestamp + 365 days);
            
            // Complete cycle with same price
            completeCycleWithPriceChange(INITIAL_PRICE);
            
            health = poolStrategy.getUserCollateralHealth(address(assetPool), user1);
            cycle++;
            
            // Exit loop if liquidatable or after too many attempts
            if (health == 1 || cycle > 10) break;
        } while (health > 1);
        
        // Verify liquidatable by interest accrual
        assertEq(health, 1, "User position should be liquidatable after interest accrual");
        assertTrue(isUserLiquidatable(user1), "User should be liquidatable");
    }

    /**
     * @notice Test basic liquidation process
     */
    function testBasicLiquidation() public {
        // Setup: User1 deposits, price increases until liquidatable
        _setupLiquidatablePosition(user1);
        
        // Verify user1 is liquidatable
        assertTrue(isUserLiquidatable(user1), "User1 should be liquidatable");
        
        // Get user1's current asset balance
        (uint256 assetAmount, , ) = assetPool.userPositions(user1);
        require(assetAmount > 0, "User1 should have assets");
        
        // Calculate liquidation amount (30% of position)
        uint256 liquidationAmount = (assetAmount * 30) / 100;
        
        // Fund liquidator (user2) with asset tokens by setting up a deposit and claim
        _setupUserWithAssetTokens(user2, liquidationAmount);
        
        // Liquidator (user2) requests liquidation
        uint256 initialUser2Balance = reserveToken.balanceOf(user2);
        
        vm.startPrank(user2);
        assetToken.approve(address(assetPool), liquidationAmount);
        assetPool.liquidationRequest(user1, liquidationAmount);
        vm.stopPrank();
        
        // Verify liquidation request state
        (IAssetPool.RequestType reqType, uint256 reqAmount, , uint256 reqCycle) = assetPool.userRequests(user1);
        assertEq(uint(reqType), uint(IAssetPool.RequestType.LIQUIDATE), "Request type should be LIQUIDATE");
        assertEq(reqAmount, liquidationAmount, "Request amount should match liquidation amount");
        assertEq(reqCycle, cycleManager.cycleIndex(), "Request cycle should match current cycle");
        
        // Verify liquidation initiator
        address liquidator = assetPool.getUserLiquidationIntiator(user1);
        assertEq(liquidator, user2, "Liquidator should be user2");
        
        // Complete a cycle to process the liquidation
        completeCycleWithPriceChange(assetOracle.assetPrice());
        
        // Liquidator claims reserves
        vm.prank(user2);
        assetPool.claimReserve(user1);
        
        // Verify liquidator received funds
        uint256 finalUser2Balance = reserveToken.balanceOf(user2);
        assertGt(finalUser2Balance, initialUser2Balance, "Liquidator should receive reserve tokens");
        
        // Verify user position is updated
        (uint256 finalAssetAmount, , ) = assetPool.userPositions(user1);
        assertEq(finalAssetAmount, assetAmount - liquidationAmount, "User asset amount should be reduced by liquidation amount");
    }

    /**
     * @notice Test partial liquidation (less than 30%)
     */
    function testPartialLiquidation() public {
        // Setup: User1 deposits, price increases until liquidatable
        _setupLiquidatablePosition(user1);
        
        // Verify user1 is liquidatable
        assertTrue(isUserLiquidatable(user1), "User1 should be liquidatable");
        
        // Get user1's current asset balance
        (uint256 assetAmount, , ) = assetPool.userPositions(user1);
        require(assetAmount > 0, "User1 should have assets");
        
        // Calculate liquidation amount (15% of position - half of maximum)
        uint256 liquidationAmount = (assetAmount * 15) / 100;
        
        // Fund liquidator (user2) with asset tokens by setting up a deposit and claim
        _setupUserWithAssetTokens(user2, liquidationAmount);
        
        // Liquidator (user2) requests partial liquidation
        vm.startPrank(user2);
        assetToken.approve(address(assetPool), liquidationAmount);
        assetPool.liquidationRequest(user1, liquidationAmount);
        vm.stopPrank();
        
        // Complete a cycle to process the liquidation
        completeCycleWithPriceChange(assetOracle.assetPrice());
        
        // Liquidator claims reserves
        vm.prank(user2);
        assetPool.claimReserve(user1);
        
        // Verify user position is partially liquidated
        (uint256 finalAssetAmount, , ) = assetPool.userPositions(user1);
        assertEq(finalAssetAmount, assetAmount - liquidationAmount, "User asset amount should be reduced by partial liquidation amount");
        
        // After partial liquidation, user might still be liquidatable
        // This depends on how much the health improved after partial liquidation
    }

    /**
     * @notice Test liquidation reward calculation
     */
    function testLiquidationReward() public {
        // Setup: User1 deposits, price increases until liquidatable
        _setupLiquidatablePosition(user1);
        
        // Get user1's current asset balance and valuation
        (uint256 assetAmount, , uint256 collateralAmount) = assetPool.userPositions(user1);
        uint256 liquidationAmount = (assetAmount * 30) / 100;
        
        // Fund liquidator (user2) with asset tokens by minting them
        _setupUserWithAssetTokens(user2, liquidationAmount);

        // Liquidator requests liquidation
        uint256 initialUser2Balance = reserveToken.balanceOf(user2);
        
        vm.startPrank(user2);
        assetToken.approve(address(assetPool), liquidationAmount);
        assetPool.liquidationRequest(user1, liquidationAmount);
        vm.stopPrank();
        
        // Complete a cycle to process the liquidation
        completeCycleWithPriceChange(assetOracle.assetPrice());
        
        // Liquidator claims reserves
        vm.prank(user2);
        assetPool.claimReserve(user1);
        
        // Calculate expected reward based on the liquidation amount
        uint256 expectedReward = (collateralAmount * liquidationAmount) / assetAmount;
        uint256 assetValue = (liquidationAmount * assetOracle.assetPrice()) / (1e18 * assetPool.getReserveToAssetDecimalFactor());
        uint256 expectedTotal = assetValue + expectedReward;
        
        // Verify liquidator received expected amount
        uint256 actualReceived = reserveToken.balanceOf(user2) - initialUser2Balance;
        
        // Allow for some variation due to interest calculations
        assertApproxEqRel(actualReceived, expectedTotal, 0.02e18, "Liquidator should receive expected redemption value plus reward");
    }

    /**
     * @notice Test replacing a liquidation request with a larger one
     */
    function testReplaceLiquidationWithLarger() public {
        // Setup: User1 deposits, price increases until liquidatable
        _setupLiquidatablePosition(user1);
        
        // Get user1's current asset balance
        (uint256 assetAmount, , ) = assetPool.userPositions(user1);
        
        // Calculate initial liquidation amount (10% of position)
        uint256 smallLiquidationAmount = (assetAmount * 10) / 100;
        
        // Calculate larger liquidation amount (20% of position)
        uint256 largeLiquidationAmount = (assetAmount * 20) / 100;
        
        // Fund liquidators with asset tokens
        _setupUserWithAssetTokens(user2, smallLiquidationAmount);
        _setupUserWithAssetTokens(user3, largeLiquidationAmount);
        
        // First liquidator (user2) requests liquidation
        vm.startPrank(user2);
        assetToken.approve(address(assetPool), smallLiquidationAmount);
        assetPool.liquidationRequest(user1, smallLiquidationAmount);
        vm.stopPrank();
        
        // Verify liquidation request state
        address initialLiquidator = assetPool.getUserLiquidationIntiator(user1);
        assertEq(initialLiquidator, user2, "Initial liquidator should be user2");
        
        // Second liquidator (user3) requests larger liquidation
        vm.startPrank(user3);
        assetToken.approve(address(assetPool), largeLiquidationAmount);
        assetPool.liquidationRequest(user1, largeLiquidationAmount);
        vm.stopPrank();
        
        // Verify liquidation request was replaced
        (IAssetPool.RequestType reqType, uint256 reqAmount, , ) = assetPool.userRequests(user1);
        assertEq(uint(reqType), uint(IAssetPool.RequestType.LIQUIDATE), "Request type should still be LIQUIDATE");
        assertEq(reqAmount, largeLiquidationAmount, "Request amount should be updated to larger amount");
        
        address finalLiquidator = assetPool.getUserLiquidationIntiator(user1);
        assertEq(finalLiquidator, user3, "New liquidator should be user3");
        
        // Complete a cycle to process the liquidation
        completeCycleWithPriceChange(assetOracle.assetPrice());
        
        // New liquidator claims reserves
        vm.prank(user3);
        assetPool.claimReserve(user1);
        
        // Verify user position was liquidated by the larger amount
        (uint256 finalAssetAmount, , ) = assetPool.userPositions(user1);
        assertEq(finalAssetAmount, assetAmount - largeLiquidationAmount, "User asset amount should be reduced by larger liquidation amount");
    }

    /**
     * @notice Test cannot replace with smaller liquidation amount
     */
    function testCannotReplaceWithSmallerLiquidation() public {
        // Setup: User1 deposits, price increases until liquidatable
        _setupLiquidatablePosition(user1);
        
        // Get user1's current asset balance
        (uint256 assetAmount, , ) = assetPool.userPositions(user1);
        
        // Calculate initial liquidation amount (20% of position)
        uint256 largeLiquidationAmount = (assetAmount * 20) / 100;
        
        // Calculate smaller liquidation amount (10% of position)
        uint256 smallLiquidationAmount = (assetAmount * 10) / 100;
        
        // Fund liquidators with asset tokens
        _setupUserWithAssetTokens(user2, largeLiquidationAmount);
        _setupUserWithAssetTokens(user3, smallLiquidationAmount);
        
        // First liquidator (user2) requests liquidation with larger amount
        vm.startPrank(user2);
        assetToken.approve(address(assetPool), largeLiquidationAmount);
        assetPool.liquidationRequest(user1, largeLiquidationAmount);
        vm.stopPrank();
        
        // Second liquidator (user3) attempts to replace with smaller amount
        vm.startPrank(user3);
        assetToken.approve(address(assetPool), smallLiquidationAmount);
        vm.expectRevert(IAssetPool.BetterLiquidationRequestExists.selector);
        assetPool.liquidationRequest(user1, smallLiquidationAmount);
        vm.stopPrank();
        
        // Verify original liquidation request is unchanged
        (IAssetPool.RequestType reqType, uint256 reqAmount, , ) = assetPool.userRequests(user1);
        assertEq(uint(reqType), uint(IAssetPool.RequestType.LIQUIDATE), "Request type should still be LIQUIDATE");
        assertEq(reqAmount, largeLiquidationAmount, "Request amount should still be the larger amount");
        
        address finalLiquidator = assetPool.getUserLiquidationIntiator(user1);
        assertEq(finalLiquidator, user2, "Liquidator should still be user2");
    }

    /**
     * @notice Test liquidation exceeding 30% limit
     */
    function testLiquidationExceeding30Percent() public {
        // Setup: User1 deposits, price increases until liquidatable
        _setupLiquidatablePosition(user1);
        
        // Get user1's current asset balance
        (uint256 assetAmount, , ) = assetPool.userPositions(user1);
        
        // Calculate liquidation amount (31% of position - exceeds limit)
        uint256 excessLiquidationAmount = (assetAmount * 31) / 100;
        
        // Fund liquidator with asset tokens
        _setupUserWithAssetTokens(user2, excessLiquidationAmount);
        
        // Attempt liquidation with amount > 30%
        vm.startPrank(user2);
        assetToken.approve(address(assetPool), excessLiquidationAmount);
        vm.expectRevert(abi.encodeWithSelector(IAssetPool.ExcessiveLiquidationAmount.selector, excessLiquidationAmount, (assetAmount * 30) / 100));
        assetPool.liquidationRequest(user1, excessLiquidationAmount);
        vm.stopPrank();
    }

    /**
     * @notice Test liquidation of non-liquidatable position
     */
    function testLiquidationOfHealthyPosition() public {
        // User1 deposits with healthy collateral
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Complete cycle with initial price
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // User1 claims assets
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Verify user1 is not liquidatable
        assertFalse(isUserLiquidatable(user1), "User1 should not be liquidatable");
        
        // Get user1's current asset balance
        (uint256 assetAmount, , ) = assetPool.userPositions(user1);
        
        // Calculate liquidation amount (30% of position)
        uint256 liquidationAmount = (assetAmount * 30) / 100;
        
        // Fund liquidator with asset tokens
        _setupUserWithAssetTokens(user2, liquidationAmount);
        
        // Attempt liquidation of healthy position
        vm.startPrank(user2);
        assetToken.approve(address(assetPool), liquidationAmount);
        vm.expectRevert(IAssetPool.PositionNotLiquidatable.selector);
        assetPool.liquidationRequest(user1, liquidationAmount);
        vm.stopPrank();
    }

    /**
     * @notice Test cancelling liquidation by adding collateral
     */
    function testCancelLiquidationByAddingCollateral() public {
        // Setup: User1 deposits, price increases until liquidatable
        _setupLiquidatablePosition(user1);
        
        // Get user1's current asset balance
        (uint256 assetAmount, , ) = assetPool.userPositions(user1);
        
        // Calculate liquidation amount (30% of position)
        uint256 liquidationAmount = (assetAmount * 30) / 100;
        
        // Fund liquidator (user2) with asset tokens by minting them
        _setupUserWithAssetTokens(user2, liquidationAmount);
        
        // Liquidator requests liquidation
        vm.startPrank(user2);
        assetToken.approve(address(assetPool), liquidationAmount);
        assetPool.liquidationRequest(user1, liquidationAmount);
        vm.stopPrank();
        
        // Verify liquidation request is active
        (IAssetPool.RequestType reqType, , , ) = assetPool.userRequests(user1);
        assertEq(uint(reqType), uint(IAssetPool.RequestType.LIQUIDATE), "Request type should be LIQUIDATE");
        
        // User1 adds sufficient collateral to restore health
        uint256 additionalCollateral = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        
        vm.startPrank(user1);
        assetPool.addCollateral(user1, additionalCollateral);
        vm.stopPrank();
        
        // Verify liquidation request is cancelled
        (reqType, , , ) = assetPool.userRequests(user1);
        assertEq(uint(reqType), uint(IAssetPool.RequestType.NONE), "Liquidation request should be cancelled");
        
        // Verify position is now healthy
        uint8 health = poolStrategy.getUserCollateralHealth(address(assetPool), user1);
        assertEq(health, 3, "User position should be healthy after adding collateral");
    }

    /**
     * @notice Test liquidator cannot liquidate their own position
     */
    function testCannotLiquidateOwnPosition() public {
        // Setup: User1 deposits, price increases until liquidatable
        _setupLiquidatablePosition(user1);
        
        // Get user1's current asset balance
        (uint256 assetAmount, , ) = assetPool.userPositions(user1);
        
        // Calculate liquidation amount (30% of position)
        uint256 liquidationAmount = (assetAmount * 30) / 100;
        
        // Fund the same user with asset tokens by using depositRequest and claimAsset
        // We'll actually use a transfer from user2 since user1's position is already set up
        _setupUserWithAssetTokens(user2, liquidationAmount);
        
        vm.prank(user2);
        assetToken.transfer(user1, liquidationAmount);
        
        // Attempt to liquidate own position
        vm.startPrank(user1);
        assetToken.approve(address(assetPool), liquidationAmount);
        vm.expectRevert(IAssetPool.InvalidLiquidationRequest.selector);
        assetPool.liquidationRequest(user1, liquidationAmount);
        vm.stopPrank();
    }

    // ==================== HELPER FUNCTIONS ====================
    
    /**
     * @notice Setup a user with the required asset tokens through protocol mechanisms
     * @param _user User address to provide with asset tokens
     * @param _assetAmount Amount of asset tokens needed
     */
    function _setupUserWithAssetTokens(address _user, uint256 _assetAmount) internal {
        // Calculate how many reserve tokens needed based on current price
        uint256 currentPrice = assetOracle.assetPrice();
        uint256 reserveAmount = _convertAssetToReserve(_assetAmount, currentPrice);
        
        // Add a buffer to ensure enough tokens after price consideration
        reserveAmount = (reserveAmount * 120) / 100; // 20% buffer
        
        // Make sure user has enough reserve tokens
        uint256 userBalance = reserveToken.balanceOf(_user);
        if (userBalance < reserveAmount) {
            reserveToken.mint(_user, reserveAmount);
        }
        
        // Calculate collateral needed (20% of deposit)
        uint256 collateralAmount = (reserveAmount * COLLATERAL_RATIO) / 100;
        
        // User makes deposit request
        vm.startPrank(_user);
        assetPool.depositRequest(reserveAmount, collateralAmount);
        vm.stopPrank();
        
        // Complete cycle to process deposit
        completeCycleWithPriceChange(currentPrice);
        
        // User claims assets
        vm.prank(_user);
        assetPool.claimAsset(_user);
        
        // Verify user received at least the requested asset amount
        uint256 userAssetBalance = assetToken.balanceOf(_user);
        require(userAssetBalance >= _assetAmount, "Failed to setup user with enough asset tokens");
    }
    
    /**
     * @notice Setup a liquidatable position for a user by gradually increasing price
     * @param _user User address to setup a liquidatable position for
     */
    function _setupLiquidatablePosition(address _user) internal {
        // User deposits
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(_user);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Complete cycle with initial price
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // User claims assets
        vm.prank(_user);
        assetPool.claimAsset(_user);
        
        // Increase price by 45% gradually until liquidatable
        uint256 currentPrice = INITIAL_PRICE;
        uint8 health;
        
        do {
            // Increase price by 45% (maximum without triggering split detection)
            currentPrice = (currentPrice * 145) / 100;
            completeCycleWithPriceChange(currentPrice);
            
            health = poolStrategy.getUserCollateralHealth(address(assetPool), _user);
            
            // Exit loop if liquidatable or after too many attempts
            if (health == 1) break;
        } while (health > 1);
        
        // Verify the position is liquidatable
        assertTrue(health == 1, "Failed to setup liquidatable position");
    }

    /**
     * @notice Convert asset amount to reserve amount at a given price
     * @param _assetAmount Amount of asset tokens
     * @param _price Price of asset in reserve
     * @return Reserve token amount
     */
    function _convertAssetToReserve(uint256 _assetAmount, uint256 _price) internal view returns (uint256) {
        uint256 decimalFactor = assetPool.getReserveToAssetDecimalFactor();
        return (_assetAmount * _price) / (1e18 * decimalFactor);
    }
}