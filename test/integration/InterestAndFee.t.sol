// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "../utils/ProtocolTestUtils.sol";

/**
 * @title InterestAndFeeTest
 * @notice Tests for protocol interest accrual and fee distribution
 * @dev Tests interest calculation, distribution, and fee deduction across various utilization levels
 */
contract InterestAndFeeTest is ProtocolTestUtils {
    // Base amounts (will be adjusted based on token decimals)
    uint256 constant INITIAL_PRICE = 100 * 1e18; // $100.00 per asset (always 18 decimals)
    uint256 constant USER_INITIAL_BALANCE = 1_500_000; 
    uint256 constant LP_INITIAL_BALANCE = 1_000_000;
    uint256 constant LP_LIQUIDITY_AMOUNT = 500_000;
    uint256 constant USER_DEPOSIT_AMOUNT = 10_000;
    uint256 constant COLLATERAL_RATIO = 20; // 20% collateral

    // Utilization targets for different interest rate scenarios
    uint256 constant LOW_UTILIZATION_TARGET = 50; // 50% utilization (< Tier1)
    uint256 constant MEDIUM_UTILIZATION_TARGET = 75; // 75% utilization (Tier1-Tier2)
    uint256 constant HIGH_UTILIZATION_TARGET = 90; // 90% utilization (> Tier2)

    // Constants
    uint256 constant PRECISION = 1e18; // Precision for calculations

    // Time periods
    uint256 constant INTEREST_ACCRUAL_PERIOD = 30 days;

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

    // ==================== INTEREST CALCULATION TESTS ====================

    /**
     * @notice Test interest debt calculation for a user in low utilization scenario
     */
    function testInterestDebtCalculation_LowUtilization() public {
        // Create low utilization scenario (~50%)
        _createUtilizationScenario(LOW_UTILIZATION_TARGET);
                
        // User1 deposits and claims assets
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Complete a cycle
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimAsset(user1);

        // Record post-claim state
        uint256 user1AssetAmount = assetToken.balanceOf(user1);
        uint256 postClaimCycleIndex = cycleManager.cycleIndex();
        
        // No interest debt yet as this is the first cycle after deposit
        uint256 initialDebt = assetPool.getInterestDebt(user1, postClaimCycleIndex);
        assertEq(initialDebt, 0, "No interest debt expected immediately after deposit");
        
        // Advance time to accrue interest
        vm.warp(block.timestamp + INTEREST_ACCRUAL_PERIOD);
        
        // Get current interest rate
        uint256 interestRate = poolStrategy.calculatePoolInterestRate(address(assetPool));
        
        // Expected annual interest rate in the low utilization scenario
        uint256 expectedLowInterestRate = poolStrategy.baseInterestRate();
        assertEq(interestRate, expectedLowInterestRate, "Interest rate should match base rate for low utilization");
        
        // Complete another cycle to accrue interest
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // Check interest debt after 1 month
        uint256 currentCycle = cycleManager.cycleIndex();
        uint256 interestDebt = assetPool.getInterestDebt(user1, currentCycle);

        // Calculate expected interest debt using cumulativeInterestIndex
        uint256 currentCumulativeInterestIndex = cycleManager.cumulativeInterestIndex(currentCycle);
        uint256 initialCumulativeInterestIndex = cycleManager.cumulativeInterestIndex(postClaimCycleIndex-1);
        
        // Calculate expected asset growth due to interest
        uint256 indexGrowth = currentCumulativeInterestIndex - initialCumulativeInterestIndex;
        uint256 expectedAdditionalAssets = Math.mulDiv(user1AssetAmount, indexGrowth, PRECISION);
        uint256 expectedInterestDebt = expectedAdditionalAssets / assetPool.reserveToAssetDecimalFactor();
        
        assertApproxEqRel(interestDebt, expectedInterestDebt, 0.0001e18, "Interest debt calculation incorrect for low utilization");
    }

    /**
     * @notice Test interest debt calculation for a user in medium utilization scenario
     */
    function testInterestDebtCalculation_MediumUtilization() public {
        // Create medium utilization scenario (~75%)
        _createUtilizationScenario(MEDIUM_UTILIZATION_TARGET);
        
        // User1 deposits and claims assets
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Complete a cycle
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Record post-claim state
        uint256 user1AssetAmount = assetToken.balanceOf(user1);
        uint256 postClaimCycleIndex = cycleManager.cycleIndex();
        
        // Advance time to accrue interest
        vm.warp(block.timestamp + INTEREST_ACCRUAL_PERIOD);
        
        // Get current interest rate
        uint256 interestRate = poolStrategy.calculatePoolInterestRate(address(assetPool));
        
        // Verify interest rate is in medium range (between base and maxRate)
        uint256 baseRate = poolStrategy.baseInterestRate();
        uint256 maxRate = poolStrategy.maxInterestRate();
        assertTrue(
            interestRate > baseRate && interestRate < maxRate,
            "Interest rate should be in medium range for medium utilization"
        );
        
        // Complete another cycle to accrue interest
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // Check interest debt after accrual period
        uint256 currentCycle = cycleManager.cycleIndex();
        uint256 interestDebt = assetPool.getInterestDebt(user1, currentCycle);

        // Calculate expected interest debt using cumulativeInterestIndex
        uint256 currentCumulativeInterestIndex = cycleManager.cumulativeInterestIndex(currentCycle);
        uint256 initialCumulativeInterestIndex = cycleManager.cumulativeInterestIndex(postClaimCycleIndex-1);
        
        // Calculate expected asset growth due to interest
        uint256 indexGrowth = currentCumulativeInterestIndex - initialCumulativeInterestIndex;
        uint256 expectedAdditionalAssets = Math.mulDiv(user1AssetAmount, indexGrowth, PRECISION);
        uint256 expectedInterestDebt = expectedAdditionalAssets / assetPool.reserveToAssetDecimalFactor();
        
        assertApproxEqRel(interestDebt, expectedInterestDebt, 0.0001e18, "Interest debt calculation incorrect for medium utilization");
    }

    /**
     * @notice Test interest debt calculation for a user in high utilization scenario
     */
    function testInterestDebtCalculation_HighUtilization() public {
        // Create high utilization scenario (~90%)
        _createUtilizationScenario(HIGH_UTILIZATION_TARGET);
        
        // User1 deposits and claims assets
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Complete a cycle
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Record post-claim state
        uint256 user1AssetAmount = assetToken.balanceOf(user1);
        uint256 postClaimCycleIndex = cycleManager.cycleIndex();
        
        // Advance time to accrue interest
        vm.warp(block.timestamp + INTEREST_ACCRUAL_PERIOD);
        
        // Get current interest rate
        uint256 interestRate = poolStrategy.calculatePoolInterestRate(address(assetPool));
        
        // Verify interest rate is in high range
        uint256 tier1Rate = poolStrategy.interestRate1();
        assertTrue(
            interestRate >= tier1Rate,
            "Interest rate should be high for high utilization"
        );
        
        // Complete another cycle to accrue interest
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // Check interest debt after accrual period
        uint256 currentCycle = cycleManager.cycleIndex();
        uint256 interestDebt = assetPool.getInterestDebt(user1, currentCycle);

        // Calculate expected interest debt using cumulativeInterestIndex
        uint256 currentCumulativeInterestIndex = cycleManager.cumulativeInterestIndex(currentCycle);
        uint256 initialCumulativeInterestIndex = cycleManager.cumulativeInterestIndex(postClaimCycleIndex-1);
        
        // Calculate expected asset growth due to interest
        uint256 indexGrowth = currentCumulativeInterestIndex - initialCumulativeInterestIndex;
        uint256 expectedAdditionalAssets = Math.mulDiv(user1AssetAmount, indexGrowth, PRECISION);
        uint256 expectedInterestDebt = expectedAdditionalAssets / assetPool.reserveToAssetDecimalFactor();
        
        assertApproxEqRel(interestDebt, expectedInterestDebt, 0.0001e18, "Interest debt calculation incorrect for high utilization");
    }

    /**
    * @notice Test interest debt calculation when user increases position
    */
    function testInterestDebt_UserIncreasesPosition() public {
        // Create medium utilization scenario
        _createUtilizationScenario(MEDIUM_UTILIZATION_TARGET);
        
        // User1 initial deposit and claim
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Complete a cycle
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Record state after first deposit
        uint256 initialAssetAmount = assetToken.balanceOf(user1);
        uint256 firstCycleIndex = cycleManager.cycleIndex();
        
        // Advance time to accrue some interest
        vm.warp(block.timestamp + INTEREST_ACCRUAL_PERIOD / 2);
        
        // User1 makes a second deposit
        uint256 secondDepositAmount = depositAmount * 2; // Double the amount
        uint256 secondCollateralAmount = (secondDepositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(secondDepositAmount, secondCollateralAmount);
        vm.stopPrank();
        
        // Complete a cycle
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // Check interest debt accrued on initial position
        uint256 firstInterestDebt = assetPool.getInterestDebt(user1, firstCycleIndex);
        assertGt(firstInterestDebt, 0, "Should have accrued interest on initial position");
        
        // Claim second deposit
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Record state after second deposit
        uint256 secondCycleIndex = cycleManager.cycleIndex();
        uint256 totalAssetAmount = assetToken.balanceOf(user1);
        
        // Advance time to accrue more interest
        vm.warp(block.timestamp + INTEREST_ACCRUAL_PERIOD / 2);
        
        // Complete another cycle
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // Check interest debt accrued on combined position
        uint256 finalInterestDebt = assetPool.getInterestDebt(user1, secondCycleIndex);
        
        // Calculate expected interest debt
        uint256 initialIndex = cycleManager.cumulativeInterestIndex(firstCycleIndex - 1);
        uint256 secondIndex = cycleManager.cumulativeInterestIndex(secondCycleIndex - 1);
        uint256 finalIndex = cycleManager.cumulativeInterestIndex(secondCycleIndex);
        
        // Calculate weighted user index after second deposit
        uint256 weightedOld = Math.mulDiv(initialAssetAmount, initialIndex, totalAssetAmount);
        uint256 weightedNew = Math.mulDiv(totalAssetAmount - initialAssetAmount, secondIndex, totalAssetAmount);
        uint256 userIndexAfterDeposit = weightedOld + weightedNew;
        
        // Expected interest debt = assetAmount * (finalIndex - userIndexAfterDeposit) / (PRECISION * reserveToAssetDecimalFactor)
        uint256 expectedInterestDebt = Math.mulDiv(
            totalAssetAmount,
            finalIndex - userIndexAfterDeposit,
            PRECISION * assetPool.reserveToAssetDecimalFactor()
        );
        
        assertApproxEqRel(
            finalInterestDebt,
            expectedInterestDebt,
            0.0001e18,
            "Interest debt calculation incorrect for increased position"
        );
    }

    /**
     * @notice Test interest debt calculation when user reduces position
     */
    function testInterestDebt_UserReducesPosition() public {
        // Create medium utilization scenario (~75%)
        _createUtilizationScenario(MEDIUM_UTILIZATION_TARGET);
        
        // User1 deposits and claims assets
        uint256 depositAmount = adjustAmountForDecimals(USER_DEPOSIT_AMOUNT, 6);
        uint256 collateralAmount = (depositAmount * COLLATERAL_RATIO) / 100;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Complete a cycle
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        // Record state after first deposit
        uint256 initialAssetAmount = assetToken.balanceOf(user1);
        uint256 firstCycleIndex = cycleManager.cycleIndex();
        
        // Advance time to accrue some interest
        vm.warp(block.timestamp + INTEREST_ACCRUAL_PERIOD / 2);
        
        // User1 requests redemption for half of their position
        uint256 redemptionAmount = initialAssetAmount / 2;
        
        vm.startPrank(user1);
        // Approve AssetPool to spend xTSLA tokens for redemption
        assetToken.approve(address(assetPool), redemptionAmount);
        assetPool.redemptionRequest(redemptionAmount);
        vm.stopPrank();
        
        // Complete a cycle to process redemption
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // Check interest debt accrued on initial position
        uint256 firstInterestDebt = assetPool.getInterestDebt(user1, firstCycleIndex);
        assertGt(firstInterestDebt, 0, "Should have accrued interest on initial position");
        
        // Claim redemption
        vm.prank(user1);
        assetPool.claimReserve(user1);
        
        // Record state after redemption
        uint256 secondCycleIndex = cycleManager.cycleIndex();
        uint256 remainingAssetAmount = assetToken.balanceOf(user1);
        
        // Advance time to accrue more interest
        vm.warp(block.timestamp + INTEREST_ACCRUAL_PERIOD / 2);
        
        // Complete another cycle
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // Check interest debt accrued on remaining position
        uint256 finalInterestDebt = assetPool.getInterestDebt(user1, secondCycleIndex);
        
        // Calculate expected interest debt
        uint256 initialIndex = cycleManager.cumulativeInterestIndex(firstCycleIndex - 1);
        uint256 secondIndex = cycleManager.cumulativeInterestIndex(secondCycleIndex - 1);
        uint256 finalIndex = cycleManager.cumulativeInterestIndex(secondCycleIndex);
        
        // Calculate interest debt for initial position (before redemption)
        uint256 interestDebtBeforeRedemption = Math.mulDiv(
            initialAssetAmount,
            secondIndex - initialIndex,
            PRECISION * assetPool.reserveToAssetDecimalFactor()
        );
        
        // Calculate proportional interest debt paid during redemption
        uint256 interestDebtPaid = Math.mulDiv(
            interestDebtBeforeRedemption,
            redemptionAmount,
            initialAssetAmount
        );
        
        // Calculate interest debt for remaining position
        uint256 expectedInterestDebt = Math.mulDiv(
            remainingAssetAmount,
            finalIndex - secondIndex,
            PRECISION * assetPool.reserveToAssetDecimalFactor()
        );
        
        // Total expected interest debt is the remaining debt after redemption
        uint256 totalExpectedInterestDebt = interestDebtBeforeRedemption - interestDebtPaid + expectedInterestDebt;
        
        assertApproxEqRel(
            finalInterestDebt,
            totalExpectedInterestDebt,
            0.0001e18,
            "Interest debt calculation incorrect for reduced position"
        );
    }

    // ==================== INTEREST BALANCE TESTS ====================

    /**
     * @notice Test that total interest debt accrued by users equals interest paid to LPs plus protocol fee
     */
    function testInterestBalanceAcrossSystem() public {
        uint256 feeRecipientBalanceBefore = reserveToken.balanceOf(feeRecipient);
        // Create medium utilization scenario with multiple users
        _createUtilizationScenarioWithMultipleUsers(MEDIUM_UTILIZATION_TARGET);
        
        // Advance time to accrue interest
        vm.warp(block.timestamp + INTEREST_ACCRUAL_PERIOD);
        
        // Complete cycle to update interest
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // Record total user interest debt
        uint256 totalUserInterestDebt = 0;
        uint256 currentCycle = cycleManager.cycleIndex();
        
        // Sum interest debt for all users who have assets
        for (uint i = 1; i <= 3; i++) {
            address user = i == 1 ? user1 : i == 2 ? user2 : user3;
            
            (uint256 assetAmount, , ) = assetPool.userPositions(user);
            if (assetAmount > 0) {
                totalUserInterestDebt += assetPool.getInterestDebt(user, currentCycle);
            }
        }
        
        // Record fee recipient balance after rebalance
        uint256 feeRecipientBalanceAfter = reserveToken.balanceOf(feeRecipient);
        uint256 actualFeeCollected = feeRecipientBalanceAfter - feeRecipientBalanceBefore;
        
        // Record actual interest distributed to LPs
        IPoolLiquidityManager.LPPosition memory lp1Position = liquidityManager.getLPPosition(liquidityProvider1);
        IPoolLiquidityManager.LPPosition memory lp2Position = liquidityManager.getLPPosition(liquidityProvider2);
        uint256 totalLPInterest = lp1Position.interestAccrued + lp2Position.interestAccrued;
        
        // Verify interest balance across the system
        assertApproxEqRel(
            totalUserInterestDebt - actualFeeCollected,
            totalLPInterest,
            0.0001e18, 
            "Total interest debt accrued should match total interest amount"
        );
    }

    // ==================== HELPER FUNCTIONS ====================
    
    /**
     * @notice Creates a utilization scenario with the specified target percentage
     * @param targetUtilizationPercent Target utilization percentage (0-100)
     */
    function _createUtilizationScenario(uint256 targetUtilizationPercent) internal {
        // Calculate target utilization in basis points
        uint256 targetUtilization = targetUtilizationPercent * 100; // Convert to BPS
        
        // Get current total liquidity
        uint256 totalLiquidity = liquidityManager.totalLPLiquidityCommited();
        
        // Calculate deposit amounts needed to reach target utilization
        uint256 targetDepositValue = Math.mulDiv(totalLiquidity, targetUtilization, BPS);
        
        // Adjust for reserve token decimals
        uint256 depositAmount = targetDepositValue;
        uint256 collateralRatio = poolStrategy.userHealthyCollateralRatio();
        uint256 collateralAmount = Math.mulDiv(depositAmount, collateralRatio, BPS);
        
        // Deposit from user2 to reach target utilization
        vm.startPrank(user2);
        assetPool.depositRequest(depositAmount, collateralAmount);
        vm.stopPrank();
        
        // Complete cycle to process deposits
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // User2 claims assets
        vm.prank(user2);
        assetPool.claimAsset(user2);
        
        // Verify target utilization is reached (approximately)
        uint256 actualUtilization = poolStrategy.calculatePoolUtilizationRatio(address(assetPool));
        assertApproxEqRel(
            actualUtilization, 
            targetUtilization, 
            0.03e18, // Allow 3% variance
            "Actual utilization should be close to target"
        );
    }
    
    /**
     * @notice Creates a utilization scenario with multiple users
     * @param targetUtilizationPercent Target utilization percentage (0-100)
     */
    function _createUtilizationScenarioWithMultipleUsers(uint256 targetUtilizationPercent) internal {
        // Calculate target utilization in basis points
        uint256 targetUtilization = targetUtilizationPercent * 100; // Convert to BPS
        
        // Get current total liquidity
        uint256 totalLiquidity = liquidityManager.totalLPLiquidityCommited();
        
        // Calculate total deposit needed to reach target utilization
        uint256 targetDepositValue = Math.mulDiv(totalLiquidity, targetUtilization, BPS);
        
        // Divide among 3 users (40%, 30%, 30%)
        uint256 user1DepositAmount = Math.mulDiv(targetDepositValue, 40, 100);
        uint256 user2DepositAmount = Math.mulDiv(targetDepositValue, 30, 100);
        uint256 user3DepositAmount = Math.mulDiv(targetDepositValue, 30, 100);
        
        uint256 collateralRatio = poolStrategy.userHealthyCollateralRatio();
        
        // User1 deposits
        uint256 user1CollateralAmount = Math.mulDiv(user1DepositAmount, collateralRatio, BPS);
        vm.startPrank(user1);
        assetPool.depositRequest(user1DepositAmount, user1CollateralAmount);
        vm.stopPrank();
        
        // User2 deposits
        uint256 user2CollateralAmount = Math.mulDiv(user2DepositAmount, collateralRatio, BPS);
        vm.startPrank(user2);
        assetPool.depositRequest(user2DepositAmount, user2CollateralAmount);
        vm.stopPrank();
        
        // User3 deposits
        uint256 user3CollateralAmount = Math.mulDiv(user3DepositAmount, collateralRatio, BPS);
        vm.startPrank(user3);
        assetPool.depositRequest(user3DepositAmount, user3CollateralAmount);
        vm.stopPrank();
        
        // Complete cycle to process deposits
        completeCycleWithPriceChange(INITIAL_PRICE);
        
        // Users claim assets
        vm.prank(user1);
        assetPool.claimAsset(user1);
        
        vm.prank(user2);
        assetPool.claimAsset(user2);
        
        vm.prank(user3);
        assetPool.claimAsset(user3);
        
        // Verify target utilization is reached (approximately)
        uint256 actualUtilization = poolStrategy.calculatePoolUtilizationRatio(address(assetPool));
        assertApproxEqRel(
            actualUtilization, 
            targetUtilization, 
            0.03e18, // Allow 3% variance
            "Actual utilization should be close to target"
        );
    }
    
    /**
     * @notice Convert asset amount to reserve amount
     * @param assetAmount Amount of asset tokens
     * @param price Price of asset in reserve
     * @return Reserve token amount
     */
    function _convertAssetToReserve(uint256 assetAmount, uint256 price) internal view returns (uint256) {
        uint256 decimalFactor = assetPool.reserveToAssetDecimalFactor();
        return Math.mulDiv(assetAmount, price, PRECISION * decimalFactor);
    }
}