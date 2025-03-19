// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./utils/ProtocolTestUtils.sol";

/**
 * @title AssetPoolTest
 * @notice Unit and integration tests for the AssetPool contract
 */
contract AssetPoolTest is ProtocolTestUtils {
    // Constants for testing
    uint256 constant LP_LIQUIDITY_AMOUNT = 1_000_000 * 1e6; // 1M USDC
    uint256 constant USER_BALANCE = 100_000 * 1e6; // 100k USDC
   uint256 constant LP_BALANCE = 2_000_000 * 1e6; // 2M USDC
    uint256 constant INITIAL_PRICE = 100 * 1e18; // $100.00 per asset
    
    function setUp() public {
        // Deploy protocol with 6 decimals for USDC
        deployProtocol("xTSLA", "TSLA", 6);
        
        // Fund accounts
        fundAccounts(USER_BALANCE, LP_BALANCE);
        
        // Setup liquidity providers
        setupLiquidityProviders(LP_LIQUIDITY_AMOUNT);
        
        // Set initial asset price
        updateOraclePrice(INITIAL_PRICE);
    }
    
    // Test deposit request validation
    function testDepositRequestValidation() public {
        // Test with zero amount
        vm.startPrank(user1);
        vm.expectRevert(IAssetPool.InvalidAmount.selector);
        assetPool.depositRequest(0, 1000 * 1e6);
        
        // Test with zero collateral
        vm.expectRevert(IAssetPool.InvalidAmount.selector);
        assetPool.depositRequest(1000 * 1e6, 0);
        
        // Test with insufficient collateral
        uint256 depositAmount = 10_000 * 1e6;
        uint256 collateralAmount = 1_000 * 1e6; // 10%, below the 20% minimum
        
        vm.expectRevert(IAssetPool.InsufficientCollateral.selector);
        assetPool.depositRequest(depositAmount, collateralAmount);
        
        // Valid deposit request
        collateralAmount = 2_000 * 1e6; // 20%
        assetPool.depositRequest(depositAmount, collateralAmount);
        
        // Try to make second request (should fail)
        vm.expectRevert(IAssetPool.RequestPending.selector);
        assetPool.depositRequest(depositAmount, collateralAmount);
        
        vm.stopPrank();
    }
    
    // Test redemption request validation
    function testRedemptionRequestValidation() public {
        // First make a deposit and complete a cycle to get xTokens
        uint256 depositAmount = 10_000 * 1e6;
        uint256 collateralAmount = 2_000 * 1e6;
        
        vm.prank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        
        // Complete a cycle
        simulateProtocolCycle(0, 0, INITIAL_PRICE);

        vm.prank(user1);
        assetPool.claimRequest(user1);
        
        // Test redemption with zero amount
        vm.startPrank(user1);
        vm.expectRevert(IAssetPool.InvalidAmount.selector);
        assetPool.redemptionRequest(0);
        
        // Test redemption with amount greater than balance
        uint256 userBalance = assetToken.balanceOf(user1);
        vm.expectRevert(IAssetPool.InsufficientBalance.selector);
        assetPool.redemptionRequest(userBalance + 1);
        
        // Valid redemption request
        assetToken.approve(address(assetPool), userBalance);
        assetPool.redemptionRequest(userBalance);
        
        // Try to make second request (should fail)
        vm.expectRevert(IAssetPool.InsufficientBalance.selector);
        assetPool.redemptionRequest(userBalance);
        
        vm.stopPrank();
    }
    
    // Test cancel request
    function testCancelRequest() public {
        // Setup a deposit request
        uint256 depositAmount = 10_000 * 1e6;
        uint256 collateralAmount = 2_000 * 1e6;
        
        vm.startPrank(user1);
        uint256 initialBalance = reserveToken.balanceOf(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        
        // Cancel the request
        assetPool.cancelRequest();
        
        // Verify request is cleared
        (uint256 reqAmount, , , ) = assetPool.userRequest(user1);
        assertEq(reqAmount, 0);
        
        // Verify tokens returned
        assertEq(reserveToken.balanceOf(user1), initialBalance);
        
        // Try to cancel again (should fail)
        vm.expectRevert(IAssetPool.NothingToCancel.selector);
        assetPool.cancelRequest();
        
        vm.stopPrank();
    }
    
    // Test claim request
    function testClaimRequest() public {
        // Setup a deposit request
        uint256 depositAmount = 10_000 * 1e6;
        uint256 collateralAmount = 2_000 * 1e6;
        
        vm.prank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        
        // Try to claim before cycle completes (should fail)
        vm.prank(user1);
        vm.expectRevert(IAssetPool.NothingToClaim.selector);
        assetPool.claimRequest(user1);
        
        // Complete a cycle
        simulateProtocolCycle(0, 0, INITIAL_PRICE);
        
        // Claim processed request
        vm.prank(user1);
        assetPool.claimRequest(user1);
        
        // Check xToken balance
        uint256 expectedXTokens = (depositAmount * 1e18 * assetPool.reserveToAssetDecimalFactor()) / INITIAL_PRICE;
        assertApproxEqRel(assetToken.balanceOf(user1), expectedXTokens, 0.01e18);
        
        // Try to claim again (should fail)
        vm.prank(user1);
        vm.expectRevert(IAssetPool.NothingToClaim.selector);
        assetPool.claimRequest(user1);
    }
    
    // Test collateral management
    function testCollateralManagement() public {
        // Setup a user with xTokens
        uint256 depositAmount = 10_000 * 1e6;
        uint256 collateralAmount = 2_000 * 1e6;
        
        vm.prank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        
        simulateProtocolCycle(0, 0, INITIAL_PRICE);
        
        vm.prank(user1);
        assetPool.claimRequest(user1);
        
        // Add more collateral
        uint256 additionalCollateral = 10_000 * 1e6;
        vm.startPrank(user1);
        uint256 initialBalance = reserveToken.balanceOf(user1);
        assetPool.addCollateral(additionalCollateral);
        
        // Verify collateral added
        assertEq(reserveToken.balanceOf(user1), initialBalance - additionalCollateral);
        assertEq(assetPool.userCollateral(user1), collateralAmount + additionalCollateral);
        
        // Withdraw some collateral
        uint256 withdrawAmount = 500 * 1e6;
        assetPool.withdrawCollateral(withdrawAmount);
        
        // Verify collateral withdrawn
        assertEq(reserveToken.balanceOf(user1), initialBalance - additionalCollateral + withdrawAmount);
        assertEq(assetPool.userCollateral(user1), collateralAmount + additionalCollateral - withdrawAmount);
        
        // Try to withdraw too much (should fail)
        uint256 excessAmount = assetPool.userCollateral(user1) + 1;
        vm.expectRevert(IAssetPool.InsufficientBalance.selector);
        assetPool.withdrawCollateral(excessAmount);
        
        vm.stopPrank();
    }
    
    // Test multiple users and cycles
    function testMultipleUsersCycles() public {
        // Multiple users deposit
        uint256 depositAmount = 10_000 * 1e6;
        uint256 collateralAmount = 2_000 * 1e6;
        
        vm.prank(user1);
        assetPool.depositRequest(depositAmount, collateralAmount);
        
        vm.prank(user2);
        assetPool.depositRequest(depositAmount * 2, collateralAmount * 2);
        
        // Complete first cycle
        simulateProtocolCycle(0, 0, INITIAL_PRICE);
        
        // Users claim their tokens
        vm.prank(user1);
        assetPool.claimRequest(user1);
        
        vm.prank(user2);
        assetPool.claimRequest(user2);
        
        // User3 makes a deposit in the second cycle
        vm.prank(user3);
        assetPool.depositRequest(depositAmount, collateralAmount);
        
        // User1 redeems half their tokens
        uint256 user1Balance = assetToken.balanceOf(user1);
        vm.startPrank(user1);
        assetToken.approve(address(assetPool), user1Balance / 2);
        assetPool.redemptionRequest(user1Balance / 2);
        vm.stopPrank();
        
        // Complete second cycle
        simulateProtocolCycle(0, 0, INITIAL_PRICE * 110 / 100); // 10% price increase
        
        // Users claim their requests
        vm.prank(user1);
        assetPool.claimRequest(user1);
        
        vm.prank(user3);
        assetPool.claimRequest(user3);
        
        // Verify final balances
        assertApproxEqRel(assetToken.balanceOf(user1), user1Balance / 2, 0.01e18);
        assertTrue(assetToken.balanceOf(user3) > 0, "User3 should have xTokens");
    }
}