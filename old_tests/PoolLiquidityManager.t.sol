// // SPDX-License-Identifier: BUSL-1.1

// pragma solidity ^0.8.20;

// import "forge-std/Test.sol";
// import "./utils/ProtocolTestUtils.sol";

// /**
//  * @title PoolLiquidityManagerTest
//  * @notice Unit and integration tests for the PoolLiquidityManager contract
//  */
// contract PoolLiquidityManagerTest is ProtocolTestUtils {
//     // Constants for testing
//     uint256 constant LP_LIQUIDITY_AMOUNT = 1_000_000 * 1e6; // 1M USDC
//     uint256 constant USER_BALANCE = 1_000_000 * 1e6; // 1M USDC
//     uint256 constant LP_BALANCE = 2_000_000 * 1e6; // 2M USDC
//     uint256 constant INITIAL_PRICE = 100 * 1e18; // $100.00 per asset
    
//     function setUp() public {
//         // Deploy protocol with 6 decimals for USDC
//         deployProtocol("xTSLA", "TSLA", 6);
        
//         // Fund accounts
//         fundAccounts(USER_BALANCE, LP_BALANCE);
        
//         // Set initial asset price
//         updateOraclePrice(INITIAL_PRICE);
//     }
    
//     // Test LP registration
//     function testLpRegistration() public {
//         // Initial state
//         assertEq(liquidityManager.lpCount(), 0);
//         assertEq(liquidityManager.totalLPLiquidity(), 0);
        
//         // Register as LP with invalid amounts
//         vm.startPrank(liquidityProvider1);
//         vm.expectRevert(IPoolLiquidityManager.InvalidAmount.selector);
//         liquidityManager.registerLP(0);
        
//         // Register with valid amount
//         liquidityManager.registerLP(LP_LIQUIDITY_AMOUNT);
        
//         // Check registration state
//         assertEq(liquidityManager.lpCount(), 1);
//         assertEq(liquidityManager.totalLPLiquidity(), LP_LIQUIDITY_AMOUNT);
//         assertTrue(liquidityManager.isLP(liquidityProvider1));
        
//         // Check collateral
//         IPoolLiquidityManager.CollateralInfo memory info = liquidityManager.getLPInfo(liquidityProvider1);
//         uint256 expectedCollateral = (LP_LIQUIDITY_AMOUNT * liquidityManager.registrationCollateralRatio()) / 100_00;
//         assertEq(info.collateralAmount, expectedCollateral);
//         assertEq(info.liquidityAmount, LP_LIQUIDITY_AMOUNT);
        
//         // Try to register again (should fail)
//         vm.expectRevert(IPoolLiquidityManager.AlreadyRegistered.selector);
//         liquidityManager.registerLP(LP_LIQUIDITY_AMOUNT);
        
//         vm.stopPrank();
//     }
    
//     // Test LP liquidity adjustments
//     function testLpLiquidityAdjustment() public {
//         // Register LP
//         vm.startPrank(liquidityProvider1);
//         liquidityManager.registerLP(LP_LIQUIDITY_AMOUNT);
        
//         // Initial state
//         IPoolLiquidityManager.CollateralInfo memory initialInfo = liquidityManager.getLPInfo(liquidityProvider1);
//         uint256 initialCollateral = initialInfo.collateralAmount;
        
//         // Increase liquidity
//         uint256 additionalLiquidity = LP_LIQUIDITY_AMOUNT / 2; // 500k
//         liquidityManager.increaseLiquidity(additionalLiquidity);
        
//         // Check updated state
//         IPoolLiquidityManager.CollateralInfo memory updatedInfo = liquidityManager.getLPInfo(liquidityProvider1);
//         assertEq(updatedInfo.liquidityAmount, LP_LIQUIDITY_AMOUNT + additionalLiquidity);
        
//         // Additional collateral should be proportional to added liquidity
//         uint256 additionalCollateral = (additionalLiquidity * liquidityManager.registrationCollateralRatio()) / 100_00;
//         assertEq(updatedInfo.collateralAmount, initialCollateral + additionalCollateral);
        
//         // Total liquidity should be updated
//         assertEq(liquidityManager.getTotalLPLiquidity(), LP_LIQUIDITY_AMOUNT + additionalLiquidity);
        
//         // Decrease liquidity
//         uint256 decreaseAmount = LP_LIQUIDITY_AMOUNT / 4; // 250k
//         liquidityManager.decreaseLiquidity(decreaseAmount);
        
//         // Check updated state after decrease
//         IPoolLiquidityManager.CollateralInfo memory finalInfo = liquidityManager.getLPInfo(liquidityProvider1);
//         assertEq(finalInfo.liquidityAmount, LP_LIQUIDITY_AMOUNT + additionalLiquidity - decreaseAmount);
        
//         // Collateral should be reduced (if excess collateral allows)
//         uint256 decreaseCollateral = (decreaseAmount * liquidityManager.registrationCollateralRatio()) / 100_00;
        
//         // Since we just added collateral proportionally and haven't done any cycles,
//         // collateral should decrease by the full amount
//         assertEq(finalInfo.collateralAmount, updatedInfo.collateralAmount - decreaseCollateral);
        
//         // Total liquidity should be updated
//         assertEq(liquidityManager.getTotalLPLiquidity(), LP_LIQUIDITY_AMOUNT + additionalLiquidity - decreaseAmount);
        
//         // Try to decrease by more than available
//         vm.expectRevert(IPoolLiquidityManager.InsufficientLiquidity.selector);
//         liquidityManager.decreaseLiquidity(finalInfo.liquidityAmount + 1);
        
//         vm.stopPrank();
//     }
    
//     // Test deposit and withdraw
//     function testDepositWithdraw() public {
//         // Register LP
//         vm.startPrank(liquidityProvider1);
//         liquidityManager.registerLP(LP_LIQUIDITY_AMOUNT);
        
//         // Initial state
//         IPoolLiquidityManager.CollateralInfo memory initialInfo = liquidityManager.getLPInfo(liquidityProvider1);
//         uint256 initialCollateral = initialInfo.collateralAmount;
        
//         // Deposit additional collateral
//         uint256 depositAmount = 50_000 * 1e6; // 50k USDC
//         liquidityManager.deposit(depositAmount);
        
//         // Check updated state
//         IPoolLiquidityManager.CollateralInfo memory updatedInfo = liquidityManager.getLPInfo(liquidityProvider1);
//         assertEq(updatedInfo.collateralAmount, initialCollateral + depositAmount);
        
//         // Withdraw some collateral
//         uint256 withdrawAmount = 20_000 * 1e6; // 20k USDC
//         liquidityManager.withdraw(withdrawAmount);
        
//         // Check updated state
//         IPoolLiquidityManager.CollateralInfo memory finalInfo = liquidityManager.getLPInfo(liquidityProvider1);
//         assertEq(finalInfo.collateralAmount, initialCollateral + depositAmount - withdrawAmount);
        
//         // Try to withdraw more than available
//         vm.expectRevert(IPoolLiquidityManager.InvalidWithdrawalAmount.selector);
//         liquidityManager.withdraw(finalInfo.collateralAmount + 1);
        
//         // Withdraw an amount that would put us below required collateral 
//         // (not applicable in this test since we have no assets yet)
        
//         vm.stopPrank();
//     }
    
//     // Test collateral requirements with assets
//     function testCollateralRequirementsWithAssets() public {
//         // Register LP
//         vm.prank(liquidityProvider1);
//         liquidityManager.registerLP(LP_LIQUIDITY_AMOUNT);

//         vm.prank(liquidityProvider2);
//         liquidityManager.registerLP(LP_LIQUIDITY_AMOUNT);
        
//         // User makes a deposit to create assets
//         uint256 depositAmount = 100_000 * 1e6; // 100k USDC
//         uint256 collateralAmount = 20_000 * 1e6; // 20k USDC
        
//         vm.prank(user1);
//         assetPool.depositRequest(depositAmount, collateralAmount);
        
//         // Complete a cycle to mint tokens
//         simulateProtocolCycle(0, 0, INITIAL_PRICE);
        
//         vm.prank(user1);
//         assetPool.claimRequest(user1);
        
//         // Now LP has share of asset holdings
//         uint256 lpAssetHolding = liquidityManager.getLPAssetHoldingValue(liquidityProvider1);
//         assertTrue(lpAssetHolding > 0, "LP should have asset holdings");
        
//         // Get required collateral
//         uint256 requiredCollateral = liquidityManager.getRequiredCollateral(liquidityProvider1);
//         assertTrue(requiredCollateral > 0, "Required collateral should be positive");
        
//         // LP attempts to withdraw too much collateral
//         vm.startPrank(liquidityProvider1);
//         uint256 currentCollateral = liquidityManager.getLPInfo(liquidityProvider1).collateralAmount;
        
//         // Try to withdraw an amount that would put collateral below required
//         uint256 excessWithdrawal = currentCollateral - requiredCollateral + 1;
//         vm.expectRevert(IPoolLiquidityManager.InsufficientCollateral.selector);
//         liquidityManager.withdraw(excessWithdrawal);
        
//         // Withdraw a safe amount
//         uint256 safeWithdrawal = currentCollateral - requiredCollateral - 10_000 * 1e6; // 10k buffer
//         if (safeWithdrawal > 0) {
//             liquidityManager.withdraw(safeWithdrawal);
//             // Check state after withdrawal
//             uint256 newCollateral = liquidityManager.getLPInfo(liquidityProvider1).collateralAmount;
//             assertEq(newCollateral, currentCollateral - safeWithdrawal);
//         }
        
//         vm.stopPrank();
//     }
    
//     // Test collateral health status
//     function testCollateralHealthStatus() public {
//         // Register LP
//         vm.prank(liquidityProvider1);
//         liquidityManager.registerLP(LP_LIQUIDITY_AMOUNT);

//         vm.prank(liquidityProvider2);
//         liquidityManager.registerLP(LP_LIQUIDITY_AMOUNT);
        
//         // Initial health should be great (no assets yet)
//         uint8 initialHealth = liquidityManager.checkCollateralHealth(liquidityProvider1);
//         assertEq(initialHealth, 3); // Great (>= healthyCollateralRatio)
        
//         // User makes a deposit to create assets
//         uint256 depositAmount = 500_000 * 1e6; // 500k USDC (50% of LP liquidity)
//         uint256 collateralAmount = 100_000 * 1e6; // 100k USDC
        
//         vm.prank(user1);
//         assetPool.depositRequest(depositAmount, collateralAmount);
        
//         // Complete a cycle to mint tokens
//         simulateProtocolCycle(0, 0, INITIAL_PRICE);
        
//         vm.prank(user1);
//         assetPool.claimRequest(user1);
        
//         // With assets but sufficient collateral, health should still be good
//         uint8 midHealth = liquidityManager.checkCollateralHealth(liquidityProvider1);
//         assertTrue(midHealth >= 2, "Health should be at least good");
        
//         // Price increases, creating more asset value
//         updateOraclePrice(INITIAL_PRICE * 2); // Double price
        
//         // Health should now be lower (potentially below threshold)
//         uint8 finalHealth = liquidityManager.checkCollateralHealth(liquidityProvider1);
//         assertTrue(finalHealth <= midHealth, "Health should be worse after price increase");
//     }
    
//     // Test LP removal
//     function testLpRemoval() public {
//         // Register LP
//         vm.prank(liquidityProvider1);
//         liquidityManager.registerLP(LP_LIQUIDITY_AMOUNT);
        
//         // Try to remove LP directly (should fail because of liquidity)
//         vm.prank(liquidityProvider1);
//         vm.expectRevert();
//         liquidityManager.removeLP(liquidityProvider1);
        
//         // Withdraw all liquidity first
//         vm.prank(liquidityProvider1);
//         liquidityManager.decreaseLiquidity(LP_LIQUIDITY_AMOUNT);
        
//         // Now remove LP
//         vm.prank(liquidityProvider1);
//         liquidityManager.removeLP(liquidityProvider1);
        
//         // Check LP was removed
//         assertFalse(liquidityManager.isLP(liquidityProvider1));
//         assertEq(liquidityManager.lpCount(), 0);
//     }
    
//     // Test LP edge cases
//     function testLpEdgeCases() public {
//         // Non-LP tries to call onlyLP functions
//         vm.startPrank(user1);
        
//         vm.expectRevert(IPoolLiquidityManager.NotRegisteredLP.selector);
//         liquidityManager.increaseLiquidity(1000 * 1e6);
        
//         vm.expectRevert(IPoolLiquidityManager.NotRegisteredLP.selector);
//         liquidityManager.decreaseLiquidity(1000 * 1e6);
        
//         vm.expectRevert(IPoolLiquidityManager.NotRegisteredLP.selector);
//         liquidityManager.deposit(1000 * 1e6);
        
//         vm.expectRevert(IPoolLiquidityManager.NotRegisteredLP.selector);
//         liquidityManager.withdraw(1000 * 1e6);
        
//         vm.expectRevert(IPoolLiquidityManager.NotRegisteredLP.selector);
//         liquidityManager.liquidateLP(liquidityProvider1);
        
//         vm.stopPrank();
//     }
    
//     // Test get functions
//     function testGetFunctions() public {
//         // Register LPs
//         vm.prank(liquidityProvider1);
//         liquidityManager.registerLP(LP_LIQUIDITY_AMOUNT);
        
//         vm.prank(liquidityProvider2);
//         liquidityManager.registerLP(LP_LIQUIDITY_AMOUNT * 2);
        
//         // Test getLPCount
//         assertEq(liquidityManager.getLPCount(), 2);
        
//         // Test isLP
//         assertTrue(liquidityManager.isLP(liquidityProvider1));
//         assertTrue(liquidityManager.isLP(liquidityProvider2));
//         assertFalse(liquidityManager.isLP(user1));
        
//         // Test getLPLiquidity
//         assertEq(liquidityManager.getLPLiquidity(liquidityProvider1), LP_LIQUIDITY_AMOUNT);
//         assertEq(liquidityManager.getLPLiquidity(liquidityProvider2), LP_LIQUIDITY_AMOUNT * 2);
        
//         // Test getTotalLPLiquidity
//         assertEq(liquidityManager.getTotalLPLiquidity(), LP_LIQUIDITY_AMOUNT * 3);
        
//         // Test getLPInfo
//         IPoolLiquidityManager.CollateralInfo memory lp1Info = liquidityManager.getLPInfo(liquidityProvider1);
//         assertEq(lp1Info.liquidityAmount, LP_LIQUIDITY_AMOUNT);
        
//         IPoolLiquidityManager.CollateralInfo memory lp2Info = liquidityManager.getLPInfo(liquidityProvider2);
//         assertEq(lp2Info.liquidityAmount, LP_LIQUIDITY_AMOUNT * 2);
//     }
// }