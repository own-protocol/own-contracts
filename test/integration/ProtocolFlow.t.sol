// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "../utils/ProtocolTestUtils.sol";
import "../mocks/MockPoolStrategy.sol";

/**
 * @title ProtocolFlowTest
 * @notice Comprehensive integration tests for the Own Protocol
 * @dev Tests multiple scenarios including price changes and different reserve token decimals
 */
contract ProtocolFlowTest is ProtocolTestUtils {
    // Base amounts (will be adjusted based on token decimals)
    uint256 constant INITIAL_PRICE = 100 * 1e18; // $100.00 per asset (always 18 decimals)
    uint256 constant USER_INITIAL_BALANCE = 100_000; 
    uint256 constant LP_INITIAL_BALANCE = 1_000_000;
    uint256 constant LP_LIQUIDITY_AMOUNT = 500_000;
    uint256 constant USER_DEPOSIT_AMOUNT = 10_000;
    uint256 constant COLLATERAL_RATIO = 20;

    // Updated prices for testing
    uint256 constant PRICE_INCREASE = 120 * 1e18; // $130.00 per asset
    uint256 constant PRICE_DECREASE = 80 * 1e18; // $80.00 per asset
    
    function setUp() public {
        // Test accounts are set up in the deployProtocol function
    }
    
    /**
     * @notice Tests the basic protocol flow with USDC(6 decimal) as reserve token
     * @dev Tests full cycle: deposit → rebalance → claim → redeem → rebalance → claim
     */
    function testBasicProtocolFlowWithUSDC() public {
        bool success = setupProtocol(
            "xTSLA",                // Asset symbol
            6,                      // Reserve token decimals
            INITIAL_PRICE,          // Initial price
            USER_INITIAL_BALANCE,   // User amount (base units)
            LP_INITIAL_BALANCE,     // LP amount (base units)
            LP_LIQUIDITY_AMOUNT     // LP liquidity (base units)
        );
        
        require(success, "Protocol setup with 6 decimals failed");
        
        // --- USER DEPOSITS ---
        
        // User1 deposits
        depositTokens(user1, USER_DEPOSIT_AMOUNT);
        
        // Complete cycle with steady price
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // User1 claims assets
        claimAssets(user1);
        
        // Calculate expected asset amount
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6); // Adjust for 6 decimals
        uint256 expectedUser1Assets = getExpectedAssetAmount(depositAmount, INITIAL_PRICE);
        
        // Verify asset tokens for user1
        assertEq(assetToken.balanceOf(user1), expectedUser1Assets, "User1 asset balance incorrect after initial mint");
        
        // --- USER REDEMPTIONS ---
        
        // Record user balance before redemption
        uint256 user1TokensBefore = assetToken.balanceOf(user1);
        uint256 user1ReserveBefore = reserveToken.balanceOf(user1);
        
        // User1 redeems half of their tokens
        redeemTokens(user1, user1TokensBefore / 2);
        
        // User2 deposits
        depositTokens(user2, USER_DEPOSIT_AMOUNT);
        
        // Complete another cycle with steady price
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // Users claim their tokens
        claimAssets(user2);
        claimReserves(user1);
        
        // Verify user2's assets
        depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6); // Adjust for 6 decimals
        uint256 expectedUser2Assets = getExpectedAssetAmount(depositAmount, INITIAL_PRICE);
        assertEq(assetToken.balanceOf(user2), expectedUser2Assets, "User2 asset balance incorrect");
        
        // Verify user1's remaining assets and redeemed reserves
        assertEq(assetToken.balanceOf(user1), user1TokensBefore / 2, "User1 remaining asset balance incorrect");
        
        // User1 should have received reserve tokens back
        uint256 redeemedAmount = reserveToken.balanceOf(user1) - user1ReserveBefore;
        assertGt(redeemedAmount, 0, "User1 should have received reserves back");
        
        // Verify expected redemption amount approximately matches actual amount
        uint256 expectedRedeemAmount = getExpectedReserveAmount(user1TokensBefore / 2, INITIAL_PRICE);
        expectedRedeemAmount = expectedRedeemAmount + expectedRedeemAmount / 5; // Adjust for 20% collateral ratio
        // There will be a small difference because of interest deduction
        assertApproxEqRel(redeemedAmount, expectedRedeemAmount, 0.03e18,"Redeemed amount should match expected");
    }
    
//     /**
//      * @notice Tests the protocol flow with price increase
//      * @dev Tests how users and LPs are affected by price appreciation
//      */
//     function testProtocolFlow_PriceIncrease() public {
//         // Setup protocol with 6 decimal reserve token
//         bool success = setupProtocol(
//             "xTSLA",                // Asset symbol
//             6,                      // Reserve token decimals
//             INITIAL_PRICE,          // Initial price
//             USER_INITIAL_BALANCE,   // User amount (base units)
//             LP_INITIAL_BALANCE,     // LP amount (base units)
//             LP_LIQUIDITY_AMOUNT     // LP liquidity (base units)
//         );
        
//         require(success, "Protocol setup with 6 decimals failed");
        
//         // User1 and User2 deposit
//         depositTokens(user1, USER_DEPOSIT_AMOUNT);
//         depositTokens(user2, USER_DEPOSIT_AMOUNT * 2); // User2 deposits more
        
//         // Complete cycle with initial price
//         completeCycleWithPriceChange(INITIAL_PRICE);
        
//         // Users claim assets
//         claimAssets(user1);
//         claimAssets(user2);
        
//         // Record balances after first cycle
//         uint256 user1TokensAfterFirstCycle = assetToken.balanceOf(user1);
        
//         // Complete cycle with 50% price increase
//         completeCycleWithPriceChange(PRICE_INCREASE);
        
//         // User1 redeems all their tokens after price increase
//         redeemTokens(user1, user1TokensAfterFirstCycle);
        
//         // Complete another cycle at the higher price
//         completeCycleWithPriceChange(PRICE_INCREASE);
        
//         // User1 claims reserves
//         claimReserves(user1);
        
//         // Calculate expected redemption amount with the higher price
//         uint256 expectedRedeemAmount = getExpectedReserveAmount(user1TokensAfterFirstCycle, PRICE_INCREASE);
        
//         // Verify user1's redemption amount after price increase
//         uint256 actualRedeemAmount = reserveToken.balanceOf(user1);
        
//         // User should have received more reserves back due to price increase
//         uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
//         assertGt(actualRedeemAmount, depositAmount, "User1 should receive more reserves after price increase");
//         assertEq(actualRedeemAmount, expectedRedeemAmount, "Redeemed amount should match expected at higher price");
        
//         // Check that LP positions have been properly adjusted
//         IPoolLiquidityManager.LPPosition memory position = liquidityManager.getLPPosition(liquidityProvider1);
//         assertGt(position.liquidityCommitment, 0, "LP1 should have non-zero liquidity commitment after price increase");
//     }
    
//     /**
//      * @notice Tests the protocol flow with price decrease
//      * @dev Tests how users and LPs are affected by price depreciation
//      */
//     function testProtocolFlow_PriceDecrease() public {
//         // Setup protocol with 6 decimal reserve token
//         bool success = setupProtocol(
//             "xTSLA",                // Asset symbol
//             6,                      // Reserve token decimals
//             INITIAL_PRICE,          // Initial price
//             USER_INITIAL_BALANCE,   // User amount (base units)
//             LP_INITIAL_BALANCE,     // LP amount (base units)
//             LP_LIQUIDITY_AMOUNT     // LP liquidity (base units)
//         );
        
//         require(success, "Protocol setup with 6 decimals failed");
        
//         // User1 and User2 deposit
//         depositTokens(user1, USER_DEPOSIT_AMOUNT);
//         depositTokens(user2, USER_DEPOSIT_AMOUNT * 2); // User2 deposits more
        
//         // Complete cycle with initial price
//         completeCycleWithPriceChange(INITIAL_PRICE);
        
//         // Users claim assets
//         claimAssets(user1);
//         claimAssets(user2);
        
//         // Record balances after first cycle
//         uint256 user1TokensAfterFirstCycle = assetToken.balanceOf(user1);
        
//         // Complete cycle with 20% price decrease
//         completeCycleWithPriceChange(PRICE_DECREASE);
        
//         // User1 redeems all their tokens after price decrease
//         redeemTokens(user1, user1TokensAfterFirstCycle);
        
//         // Complete another cycle at the lower price
//         completeCycleWithPriceChange(PRICE_DECREASE);
        
//         // User1 claims reserves
//         claimReserves(user1);
        
//         // Calculate expected redemption amount with the lower price
//         uint256 expectedRedeemAmount = getExpectedReserveAmount(user1TokensAfterFirstCycle, PRICE_DECREASE);
        
//         // Verify user1's redemption amount after price decrease
//         uint256 actualRedeemAmount = reserveToken.balanceOf(user1);
        
//         // User should have received fewer reserves back due to price decrease
//         uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
//         assertLt(actualRedeemAmount, depositAmount, "User1 should receive fewer reserves after price decrease");
//         assertEq(actualRedeemAmount, expectedRedeemAmount, "Redeemed amount should match expected at lower price");
        
//         // Check that LP positions have been properly adjusted
//         IPoolLiquidityManager.LPPosition memory position = liquidityManager.getLPPosition(liquidityProvider1);
//         assertGt(position.liquidityCommitment, 0, "LP1 should have non-zero liquidity commitment after price decrease");
//     }
    
//     /**
//      * @notice Tests the protocol flow with DAI (18 decimals) as reserve token
//      * @dev Tests the same flow but with a different token precision
//      */
//     function testProtocolFlowWithDAI() public {
//         // Setup protocol with 18 decimal reserve token
//         bool success = setupProtocol(
//             "xTSLA",                // Asset symbol
//             18,                     // Reserve token decimals
//             INITIAL_PRICE,          // Initial price
//             USER_INITIAL_BALANCE,   // User amount (base units)
//             LP_INITIAL_BALANCE,     // LP amount (base units)
//             LP_LIQUIDITY_AMOUNT     // LP liquidity (base units)
//         );
        
//         require(success, "Protocol setup with 18 decimals failed");
        
//         // User1 deposits
//         depositTokens(user1, USER_DEPOSIT_AMOUNT);
        
//         // Complete cycle with initial price
//         completeCycleWithPriceChange(INITIAL_PRICE);
        
//         // User1 claims assets
//         claimAssets(user1);
        
//         // Verify asset tokens for user1
//         uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 18);
//         uint256 expectedUser1Assets = getExpectedAssetAmount(depositAmount, INITIAL_PRICE);
//         assertEq(assetToken.balanceOf(user1), expectedUser1Assets, "User1 asset balance incorrect with 18 decimal token");
        
//         // Record user balance before redemption
//         uint256 user1TokensBefore = assetToken.balanceOf(user1);
//         uint256 user1ReserveBefore = reserveToken.balanceOf(user1);
        
//         // User1 redeems half of their tokens
//         redeemTokens(user1, user1TokensBefore / 2);
        
//         // Complete another cycle with price increase
//         completeCycleWithPriceChange(PRICE_INCREASE);
        
//         // User1 claims reserves
//         claimReserves(user1);
        
//         // Calculate expected redemption amount with the higher price
//         uint256 expectedRedeemAmount = getExpectedReserveAmount(user1TokensBefore / 2, PRICE_INCREASE);
        
//         // Verify user1's redemption amount
//         uint256 redeemedAmount = reserveToken.balanceOf(user1) - user1ReserveBefore;
//         assertGt(redeemedAmount, 0, "User1 should have received reserves back");
//         assertEq(redeemedAmount, expectedRedeemAmount, "Redeemed amount should match expected with 18 decimal token");
//     }
    
//     /**
//      * @notice Tests multiple cycles with different users entering and exiting
//      */
//     function testMultipleUserFlows() public {
//         // Setup protocol with 6 decimal reserve token
//         bool success = setupProtocol(
//             "xTSLA",                // Asset symbol
//             6,                      // Reserve token decimals
//             INITIAL_PRICE,          // Initial price
//             USER_INITIAL_BALANCE,   // User amount (base units)
//             LP_INITIAL_BALANCE,     // LP amount (base units)
//             LP_LIQUIDITY_AMOUNT     // LP liquidity (base units)
//         );
        
//         require(success, "Protocol setup with 6 decimals failed");
        
//         // --- CYCLE 1: User1 deposits ---
//         depositTokens(user1, USER_DEPOSIT_AMOUNT);
//         completeCycleWithPriceChange(INITIAL_PRICE);
//         claimAssets(user1);
        
//         // --- CYCLE 2: User2 deposits, User1 redeems half ---
//         depositTokens(user2, USER_DEPOSIT_AMOUNT * 2);
//         redeemTokens(user1, assetToken.balanceOf(user1) / 2);
//         completeCycleWithPriceChange(PRICE_INCREASE);
//         claimAssets(user2);
//         claimReserves(user1);
        
//         // --- CYCLE 3: User3 deposits, price decreases ---
//         depositTokens(user3, USER_DEPOSIT_AMOUNT * 3);
//         completeCycleWithPriceChange(PRICE_DECREASE);
//         claimAssets(user3);
        
//         // --- CYCLE 4: User2 redeems everything, User1 redeems remaining ---
//         redeemTokens(user2, assetToken.balanceOf(user2));
//         redeemTokens(user1, assetToken.balanceOf(user1));
//         completeCycleWithPriceChange(INITIAL_PRICE);
//         claimReserves(user1);
//         claimReserves(user2);
        
//         // Verify all users have appropriate balances
//         assertEq(assetToken.balanceOf(user1), 0, "User1 should have no asset tokens left");
//         assertEq(assetToken.balanceOf(user2), 0, "User2 should have no asset tokens left");
//         assertGt(assetToken.balanceOf(user3), 0, "User3 should have asset tokens left");
        
//         assertGt(reserveToken.balanceOf(user1), 0, "User1 should have reserve tokens");
//         assertGt(reserveToken.balanceOf(user2), 0, "User2 should have reserve tokens");
//         assertGt(reserveToken.balanceOf(user3), 0, "User3 should have reserve tokens");
//     }
    
    // ==================== HELPER FUNCTIONS ====================
    
    /**
     * @notice User deposits tokens into the protocol
     * @param _user User address
     * @param _baseAmount Base amount to deposit (will be adjusted for token decimals)
     */
    function depositTokens(address _user, uint256 _baseAmount) internal {
        // Get token decimals
        uint8 decimals = reserveToken.decimals();
        // Convert base amount to the right decimal precision
        uint256 amount = adjustAmountForDecimals(_baseAmount, decimals);
        uint256 collateralAmount = (amount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(_user);
        assetPool.depositRequest(amount, collateralAmount);
        vm.stopPrank();
    }
    
    /**
     * @notice User redeems asset tokens
     * @param _user User address
     * @param _amount Amount of asset tokens to redeem
     */
    function redeemTokens(address _user, uint256 _amount) internal {
        vm.startPrank(_user);
        assetToken.approve(address(assetPool), _amount);
        assetPool.redemptionRequest(_amount);
        vm.stopPrank();
    }
    
    /**
     * @notice User claims asset tokens after deposit
     * @param _user User address
     */
    function claimAssets(address _user) internal {
        vm.prank(_user);
        assetPool.claimAsset(_user);
    }
    
    /**
     * @notice User claims reserve tokens after redemption
     * @param _user User address
     */
    function claimReserves(address _user) internal {
        vm.prank(_user);
        assetPool.claimReserve(_user);
    }
}