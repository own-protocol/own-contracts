// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/protocol/LPLiquidityManager.sol";
import "../src/protocol/AssetPoolFactory.sol";
import "../src/protocol/AssetPool.sol";
import "../src/protocol/xToken.sol";
import "../src/interfaces/IAssetPool.sol";
import "../src/interfaces/IAssetOracle.sol";
import "../src/interfaces/ILPLiquidityManager.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract LPLiquidityManagerTest is Test {
    // Test contracts
    AssetPoolFactory public factory;
    AssetPool public implementation;
    IAssetPool public pool;
    LPLiquidityManager public lpManagerImplementation;
    ILPLiquidityManager public lpManager;
    IERC20Metadata public reserveToken;
    IXToken public assetToken;
    MockAssetOracle assetOracle;

    // Test addresses
    address owner = address(1);
    address user1 = address(2);
    address user2 = address(3);
    address lp1 = address(4);
    address lp2 = address(5);
    address lp3 = address(6);
    address nonLp = address(7);

    // Test constants
    uint256 constant INITIAL_BALANCE = 1000000000e18;
    uint256 constant CYCLE_LENGTH = 7 days;
    uint256 constant REBALANCE_LENGTH = 1 days;
    uint256 constant LP_LIQUIDITY_AMOUNT = 1000e18;
    uint256 constant HEALTHY_COLLATERAL_RATIO = 50_00; // 50%
    uint256 constant COLLATERAL_THRESHOLD = 30_00;     // 30%
    uint256 constant REGISTRATION_COLLATERAL_RATIO = 20_00; // 20%
    uint256 constant LIQUIDATION_REWARD_PERCENTAGE = 5_00; // 5%

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock USDC
        MockERC20 mockUSDC = new MockERC20("USDC", "USDC", 18);
        reserveToken = IERC20Metadata(address(mockUSDC));

        // Deploy core contracts
        assetOracle = new MockAssetOracle();
        
        // Deploy LP Liquidity Manager Implementation
        lpManagerImplementation = new LPLiquidityManager();
        
        // Deploy AssetPool Implementation
        implementation = new AssetPool();
        
        // Deploy AssetPool Factory
        factory = new AssetPoolFactory(
            address(lpManagerImplementation), 
            address(implementation)
        );

        // Set default price in oracle
        assetOracle.setAssetPrice(1e18); // Set default price to 1.0

        // Create pool via factory
        address poolAddress = factory.createPool(
            address(reserveToken),
            "Tesla Stock Token",
            "xTSLA",
            address(assetOracle),
            CYCLE_LENGTH,
            REBALANCE_LENGTH
        );

        pool = IAssetPool(poolAddress);
        assetToken = pool.assetToken();
        lpManager = pool.lpLiquidityManager();

        vm.stopPrank();

        // Fund test accounts
        deal(address(reserveToken), user1, INITIAL_BALANCE);
        deal(address(reserveToken), user2, INITIAL_BALANCE);
        deal(address(reserveToken), lp1, INITIAL_BALANCE);
        deal(address(reserveToken), lp2, INITIAL_BALANCE);
        deal(address(reserveToken), lp3, INITIAL_BALANCE);
        deal(address(reserveToken), nonLp, INITIAL_BALANCE);

        vm.warp(block.timestamp + 1);
    }

    // ----------------------------------------------------------------------------------
    //                             LP REGISTRATION TESTS
    // ----------------------------------------------------------------------------------

    function testRegisterLP() public {
        uint256 liquidityAmount = 1000e18;
        uint256 expectedCollateral = (liquidityAmount * REGISTRATION_COLLATERAL_RATIO) / 100_00;
        
        vm.startPrank(lp1);
        reserveToken.approve(address(lpManager), expectedCollateral);
        lpManager.registerLP(liquidityAmount);
        vm.stopPrank();
        
        // Check LP was registered
        assertTrue(lpManager.isLP(lp1), "LP was not registered");
        
        // Check collateral was transferred
        assertEq(
            reserveToken.balanceOf(address(lpManager)), 
            expectedCollateral, 
            "Collateral amount incorrect"
        );
        
        // Check LP info was updated correctly
        ILPLiquidityManager.CollateralInfo memory info = lpManager.getLPInfo(lp1);
        assertEq(info.collateralAmount, expectedCollateral, "Collateral amount not recorded correctly");
        assertEq(info.liquidityAmount, liquidityAmount, "Liquidity amount not recorded correctly");
        
        // Check total liquidity updated
        assertEq(lpManager.totalLPLiquidity(), liquidityAmount, "Total liquidity not updated");
        
        // Check LP count updated
        assertEq(lpManager.lpCount(), 1, "LP count not updated");
    }
    
    function testRegisterLPRevertsOnZeroAmount() public {
        vm.startPrank(lp1);
        vm.expectRevert(ILPLiquidityManager.InvalidAmount.selector);
        lpManager.registerLP(0);
        vm.stopPrank();
    }
    
    function testRegisterLPRevertsWhenAlreadyRegistered() public {
        // Register first time
        vm.startPrank(lp1);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(LP_LIQUIDITY_AMOUNT);
        
        // Try to register again
        vm.expectRevert(ILPLiquidityManager.AlreadyRegistered.selector);
        lpManager.registerLP(LP_LIQUIDITY_AMOUNT);
        vm.stopPrank();
    }

    // ----------------------------------------------------------------------------------
    //                            LIQUIDITY MANAGEMENT TESTS
    // ----------------------------------------------------------------------------------

    function testIncreaseLiquidity() public {
        // First register LP
        uint256 initialLiquidity = 1000e18;
        vm.startPrank(lp1);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(initialLiquidity);
        
        // Then increase liquidity
        uint256 additionalLiquidity = 500e18;
        uint256 additionalCollateral = (additionalLiquidity * REGISTRATION_COLLATERAL_RATIO) / 100_00;
        lpManager.increaseLiquidity(additionalLiquidity);
        vm.stopPrank();
        
        // Check liquidity amount updated
        ILPLiquidityManager.CollateralInfo memory info = lpManager.getLPInfo(lp1);
        assertEq(
            info.liquidityAmount, 
            initialLiquidity + additionalLiquidity, 
            "Liquidity amount not updated correctly"
        );
        
        // Check collateral updated
        uint256 expectedTotalCollateral = 
            (initialLiquidity * REGISTRATION_COLLATERAL_RATIO) / 100_00 + additionalCollateral;
        assertEq(
            info.collateralAmount, 
            expectedTotalCollateral, 
            "Collateral amount not updated correctly"
        );
        
        // Check total liquidity updated
        assertEq(
            lpManager.totalLPLiquidity(), 
            initialLiquidity + additionalLiquidity, 
            "Total liquidity not updated"
        );
    }
    
    function testDecreaseLiquidity() public {
        // First register LP
        uint256 initialLiquidity = 1000e18;
        uint256 initialCollateral = (initialLiquidity * REGISTRATION_COLLATERAL_RATIO) / 100_00;
        
        vm.startPrank(lp1);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(initialLiquidity);
        
        // Add some extra collateral to ensure we can decrease liquidity
        uint256 extraCollateral = 100e18;
        lpManager.deposit(extraCollateral);
        
        // Then decrease liquidity
        uint256 decreaseAmount = 300e18;
        uint256 releasableCollateral = (decreaseAmount * REGISTRATION_COLLATERAL_RATIO) / 100_00;
        
        uint256 balanceBefore = reserveToken.balanceOf(lp1);
        lpManager.decreaseLiquidity(decreaseAmount);
        vm.stopPrank();
        
        // Check liquidity amount updated
        ILPLiquidityManager.CollateralInfo memory info = lpManager.getLPInfo(lp1);
        assertEq(
            info.liquidityAmount, 
            initialLiquidity - decreaseAmount, 
            "Liquidity amount not updated correctly"
        );
        
        // Check collateral was released
        uint256 expectedCollateral = initialCollateral + extraCollateral - releasableCollateral;
        assertEq(
            info.collateralAmount, 
            expectedCollateral, 
            "Collateral amount not updated correctly"
        );
        
        // Ensure LP received the released collateral
        assertEq(
            reserveToken.balanceOf(lp1) - balanceBefore, 
            releasableCollateral, 
            "Collateral not returned to LP"
        );
        
        // Check total liquidity updated
        assertEq(
            lpManager.totalLPLiquidity(), 
            initialLiquidity - decreaseAmount, 
            "Total liquidity not updated"
        );
    }
    
    function testDecreaseLiquidityRevertsForNonLP() public {
        vm.startPrank(nonLp);
        vm.expectRevert(ILPLiquidityManager.NotRegisteredLP.selector);
        lpManager.decreaseLiquidity(100e18);
        vm.stopPrank();
    }
    
    function testDecreaseLiquidityRevertsWhenAmountTooLarge() public {
        // Register LP
        uint256 initialLiquidity = 1000e18;
        vm.startPrank(lp1);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(initialLiquidity);
        
        // Try to decrease more than available
        vm.expectRevert(ILPLiquidityManager.InsufficientLiquidity.selector);
        lpManager.decreaseLiquidity(initialLiquidity + 1);
        vm.stopPrank();
    }

    // ----------------------------------------------------------------------------------
    //                           COLLATERAL MANAGEMENT TESTS
    // ----------------------------------------------------------------------------------

    function testDepositCollateral() public {
        // First register LP
        uint256 initialLiquidity = 1000e18;
        uint256 initialCollateral = (initialLiquidity * REGISTRATION_COLLATERAL_RATIO) / 100_00;
        
        vm.startPrank(lp1);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(initialLiquidity);
        
        // Then deposit additional collateral
        uint256 additionalCollateral = 200e18;
        lpManager.deposit(additionalCollateral);
        vm.stopPrank();
        
        // Check collateral updated
        ILPLiquidityManager.CollateralInfo memory info = lpManager.getLPInfo(lp1);
        assertEq(
            info.collateralAmount, 
            initialCollateral + additionalCollateral, 
            "Collateral amount not updated correctly"
        );
    }
    
    function testWithdrawCollateral() public {
        // First register LP
        uint256 initialLiquidity = 1000e18;
        uint256 initialCollateral = (initialLiquidity * REGISTRATION_COLLATERAL_RATIO) / 100_00;
        
        vm.startPrank(lp1);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(initialLiquidity);
        
        // Add extra collateral
        uint256 extraCollateral = 300e18;
        lpManager.deposit(extraCollateral);
        
        // Then withdraw some collateral
        uint256 withdrawAmount = 100e18;
        uint256 balanceBefore = reserveToken.balanceOf(lp1);
        lpManager.withdraw(withdrawAmount);
        vm.stopPrank();
        
        // Check collateral updated
        ILPLiquidityManager.CollateralInfo memory info = lpManager.getLPInfo(lp1);
        assertEq(
            info.collateralAmount, 
            initialCollateral + extraCollateral - withdrawAmount, 
            "Collateral amount not updated correctly"
        );
        
        // Ensure LP received the withdrawn collateral
        assertEq(
            reserveToken.balanceOf(lp1) - balanceBefore, 
            withdrawAmount, 
            "Collateral not returned to LP"
        );
    }
    
    function testWithdrawCollateralRevertsWhenBelowRequired() public {
        // Register LP
        uint256 initialLiquidity = 1000e18;
        uint256 initialCollateral = (initialLiquidity * REGISTRATION_COLLATERAL_RATIO) / 100_00;
        
        vm.startPrank(lp1);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(initialLiquidity);
        
        // Create user deposit to generate assets
        vm.stopPrank();
        vm.startPrank(user1);
        reserveToken.approve(address(pool), 100e18);
        pool.depositRequest(100e18);
        vm.stopPrank();

        vm.startPrank(lp2);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(1000e18);
        vm.stopPrank();
        
        // Simulate cycle completion
        completeCycle(pool, lp1, lp2, 1e18);

        pool.claimRequest(user1);
        
        // Now try to withdraw too much (should revert)
        vm.startPrank(lp1);
        vm.expectRevert(ILPLiquidityManager.InsufficientCollateral.selector);
        lpManager.withdraw(initialCollateral);
        vm.stopPrank();
    }

    // ----------------------------------------------------------------------------------
    //                         COLLATERAL HEALTH CHECKING TESTS
    // ----------------------------------------------------------------------------------

    function testGetRequiredCollateral() public {
        // Register LP
        vm.startPrank(lp1);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(1000e18);
        vm.stopPrank();

        vm.startPrank(lp2);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(1000e18);
        vm.stopPrank();
        
        // Create user deposit to generate assets
        vm.startPrank(user1);
        reserveToken.approve(address(pool), 100e18);
        pool.depositRequest(100e18);
        vm.stopPrank();
        
        // Complete cycle to create assets
        completeCycle(pool, lp1, lp2, 1e18);
        
        // Claim assets
        pool.claimRequest(user1);
        
        // Get required collateral
        uint256 requiredCollateral = lpManager.getRequiredCollateral(lp1);
        
        // Value should be non-zero after assets are created
        assertGt(requiredCollateral, 0, "Required collateral should be non-zero");
        
        // Test for non-registered address
        assertEq(
            lpManager.getRequiredCollateral(nonLp), 
            0, 
            "Non-LP should have zero required collateral"
        );
    }
    
    function testGetCurrentRatio() public {
        // Register LP
        uint256 initialLiquidity = 500e18;
        
        vm.startPrank(lp1);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(initialLiquidity);
        vm.stopPrank();

        vm.startPrank(lp2);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(500e18);
        vm.stopPrank();
        
        // Initially should report healthy ratio
        assertEq(
            lpManager.getCurrentRatio(lp1), 
            HEALTHY_COLLATERAL_RATIO, 
            "Initially should report healthy ratio"
        );
        
        // Create user deposit to generate assets
        vm.startPrank(user1);
        reserveToken.approve(address(pool), 500e18);
        pool.depositRequest(500e18);
        vm.stopPrank();
        
        // Complete cycle to create assets
        completeCycle(pool, lp1, lp2, 1e18);
        pool.claimRequest(user1);

        // Now ratio should be lower since assets exist
        uint256 newRatio = lpManager.getCurrentRatio(lp1);

        assertLt(
            newRatio, 
            HEALTHY_COLLATERAL_RATIO, 
            "Ratio should decrease after assets are created"
        );
    }
    
    function testCheckCollateralHealth() public {
        // Register LP
        vm.startPrank(lp1);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(1000e18);
        
        // Initially should report "great" health (3)
        assertEq(
            lpManager.checkCollateralHealth(lp1), 
            3, 
            "Initially should report great health"
        );
        
        // Add some extra collateral
        uint256 extraCollateral = 500e18;
        lpManager.deposit(extraCollateral);
        vm.stopPrank();

        vm.startPrank(lp2);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(1000e18);
        vm.stopPrank();
        
        // Create large user deposit to generate significant assets
        vm.startPrank(user1);
        reserveToken.approve(address(pool), 4000e18);
        pool.depositRequest(4000e18);
        vm.stopPrank();
        
        // Complete cycle to create assets
        completeCycle(pool, lp1, lp2, 1e18);
        
        // Claim assets
        pool.claimRequest(user1);
        
        // Now health should have changed based on asset generation
        uint8 health = lpManager.checkCollateralHealth(lp1);
        
        // Depending on asset amounts, could be 2 ("good") or 1 ("bad")
        assertTrue(
            health == 2 || health == 1,
            "Health should change after assets are created"
        );
    }

    // ----------------------------------------------------------------------------------
    //                           ASSET HOLDINGS TESTS
    // ----------------------------------------------------------------------------------

    function testGetLPAssetHolding() public {
        // Register 2 LPs with different amounts
        vm.startPrank(lp1);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(1000e18);
        vm.stopPrank();
        
        vm.startPrank(lp2);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(3000e18);
        vm.stopPrank();
        
        // Create user deposit
        vm.startPrank(user1);
        reserveToken.approve(address(pool), 1000e18);
        pool.depositRequest(1000e18);
        vm.stopPrank();
        
        // Complete cycle to create assets
        completeCycle(pool, lp1, lp2, 1e18);

        pool.claimRequest(user1);
        
        // Get asset holdings
        uint256 lp1Holding = lpManager.getLPAssetHolding(lp1);
        uint256 lp2Holding = lpManager.getLPAssetHolding(lp2);
        
        // LP2 should have 3x the holding of LP1
        assertApproxEqRel(
            lp2Holding,
            lp1Holding * 3,
            0.01e18, // 1% tolerance for rounding
            "LP2 should have 3x the holding of LP1"
        );
        
        // Total holdings should be positive
        assertGt(lp1Holding + lp2Holding, 0, "Total holdings should be positive");
        
        // Non-registered address should have zero holdings
        assertEq(
            lpManager.getLPAssetHolding(nonLp), 
            0, 
            "Non-LP should have zero holdings"
        );
    }

    // ----------------------------------------------------------------------------------
    //                              LIQUIDATION TESTS
    // ----------------------------------------------------------------------------------

    function testLiquidateLP() public {
        // Register LPs - lp3 will be the one to get liquidated
        vm.startPrank(lp1);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(1000e18);
        lpManager.deposit(500e18); // Extra collateral for lp1
        vm.stopPrank();
        
        vm.startPrank(lp3);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(1000e18);
        // Note: NOT adding extra collateral to lp3
        vm.stopPrank();
        
        // Create large user deposit to generate significant assets
        vm.startPrank(user1);
        reserveToken.approve(address(pool), 5000e18);
        pool.depositRequest(5000e18);
        vm.stopPrank();
        
        // Complete cycle with high price to create lots of assets
        completeCycle(pool, lp1, lp3, 3e18);
        
        // Claim assets
        pool.claimRequest(user1);
        
        // Check lp3's health - should be bad (1)
        assertEq(
            lpManager.checkCollateralHealth(lp3), 
            1, 
            "LP3 should have bad health"
        );
        
        // Store collateral values before liquidation
        ILPLiquidityManager.CollateralInfo memory lp1InfoBefore = lpManager.getLPInfo(lp1);
        ILPLiquidityManager.CollateralInfo memory lp3InfoBefore = lpManager.getLPInfo(lp3);
        uint256 lp1AssetHoldingBefore = lpManager.getLPAssetHolding(lp1);
        uint256 lp3AssetHoldingBefore = lpManager.getLPAssetHolding(lp3);
        
        // Approve more tokens for lp1 to cover additional collateral needed
        uint256 lp3Liquidity = lp3InfoBefore.liquidityAmount;

        vm.startPrank(lp1);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.liquidateLP(lp3);
        vm.stopPrank();
        
        // Check lp3 is no longer registered
        ILPLiquidityManager.CollateralInfo memory lp3InfoAfter = lpManager.getLPInfo(lp3);
        assertEq(lp3InfoAfter.collateralAmount, 0, "LP3 collateral should be cleared");
        assertEq(lp3InfoAfter.liquidityAmount, 0, "LP3 liquidity should be cleared");
        
        // Check lp1 got lp3's liquidity and assets
        ILPLiquidityManager.CollateralInfo memory lp1InfoAfter = lpManager.getLPInfo(lp1);
        assertEq(
            lp1InfoAfter.liquidityAmount,
            lp1InfoBefore.liquidityAmount + lp3Liquidity,
            "LP1 should get LP3's liquidity"
        );
        
        // Check LP1 got reward in their collateral
        assertGt(
            lp1InfoAfter.collateralAmount,
            lp1InfoBefore.collateralAmount,
            "LP1 collateral should increase from liquidation"
        );
        
        // Check LP1 got LP3's asset holdings
        uint256 lp1AssetHoldingAfter = lpManager.getLPAssetHolding(lp1);
        assertApproxEqRel(
            lp1AssetHoldingAfter,
            lp1AssetHoldingBefore + lp3AssetHoldingBefore,
            0.01e18, // 1% tolerance
            "LP1 should get LP3's asset holdings"
        );
    }
    
    function testLiquidateLPRevertsWhenNotEligible() public {
        // Register LPs with enough collateral
        vm.startPrank(lp1);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(1000e18);
        // Add plenty of collateral
        lpManager.deposit(1000e18);
        vm.stopPrank();
        
        vm.startPrank(lp2);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(1000e18);
        // Add plenty of collateral
        lpManager.deposit(1000e18);
        vm.stopPrank();
        
        // Create some assets
        vm.startPrank(user1);
        reserveToken.approve(address(pool), 100e18);
        pool.depositRequest(100e18);
        vm.stopPrank();
        
        // Complete cycle
        completeCycle(pool, lp1, lp2, 1e18);
        
        // Try to liquidate lp2 - should revert because has enough collateral
        vm.startPrank(lp1);
        vm.expectRevert(ILPLiquidityManager.NotEligibleForLiquidation.selector);
        lpManager.liquidateLP(lp2);
        vm.stopPrank();
    }

    // ----------------------------------------------------------------------------------
    //                            LP REMOVAL TESTS
    // ----------------------------------------------------------------------------------

    function testRemoveLP() public {
        // Register LP
        vm.startPrank(lp1);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(1000e18);
        vm.stopPrank();
        
        // Check LP count before
        assertEq(lpManager.lpCount(), 1, "LP count should be 1");
        
        // Remove all liquidity first
        vm.startPrank(lp1);
        lpManager.decreaseLiquidity(1000e18);
        
        // Remove LP
        uint256 balanceBefore = reserveToken.balanceOf(lp1);
        lpManager.removeLP(lp1);
        vm.stopPrank();
        
        // Check LP is no longer registered
        assertFalse(lpManager.isLP(lp1), "LP should be removed");
        
        // Check LP count
        assertEq(lpManager.lpCount(), 0, "LP count should be 0");
        
        // Ensure any remaining collateral was returned
        assertGe(
            reserveToken.balanceOf(lp1),
            balanceBefore,
            "Any remaining collateral should be returned"
        );
    }
    
    function testRemoveLPRevertsWithActiveLiquidity() public {
        // Register LP
        vm.startPrank(lp1);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(1000e18);
        
        // Try to remove without removing liquidity
        vm.expectRevert("LP has active liquidity");
        lpManager.removeLP(lp1);
        vm.stopPrank();
    }

    // ----------------------------------------------------------------------------------
    //                           ASSET POOL INTERACTIONS
    // ----------------------------------------------------------------------------------

    function testDeductRebalanceAmount() public {
        // Register LP
        vm.startPrank(lp1);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(1000e18);
        // Add extra collateral
        lpManager.deposit(500e18);
        vm.stopPrank();
        
        // Total collateral should be 200e18 (from registration) + 500e18 = 700e18
        ILPLiquidityManager.CollateralInfo memory infoBefore = lpManager.getLPInfo(lp1);
        assertEq(infoBefore.collateralAmount, 700e18, "Initial collateral incorrect");
        
        // Simulate call from AssetPool
        uint256 poolBalanceBefore = reserveToken.balanceOf(address(pool));
        
        vm.prank(address(pool)); // Only pool can call this
        lpManager.deductRebalanceAmount(lp1, 100e18);
        
        // Check LP's collateral decreased
        ILPLiquidityManager.CollateralInfo memory infoAfter = lpManager.getLPInfo(lp1);
        assertEq(
            infoAfter.collateralAmount,
            infoBefore.collateralAmount - 100e18,
            "Collateral should decrease by deduction amount"
        );
        
        // Check pool received the tokens
        assertEq(
            reserveToken.balanceOf(address(pool)) - poolBalanceBefore,
            100e18,
            "Pool should receive the deducted amount"
        );
    }
    
    function testAddToCollateral() public {
        // Register LP
        vm.startPrank(lp1);
        reserveToken.approve(address(lpManager), INITIAL_BALANCE);
        lpManager.registerLP(1000e18);
        vm.stopPrank();
        
        // Initial collateral from registration (20% of 1000e18 = 200e18)
        ILPLiquidityManager.CollateralInfo memory infoBefore = lpManager.getLPInfo(lp1);
        assertEq(infoBefore.collateralAmount, 200e18, "Initial collateral incorrect");
        
        // Simulate call from AssetPool
        vm.prank(address(pool)); // Only pool can call this
        lpManager.addToCollateral(lp1, 150e18);
        
        // Check LP's collateral increased
        ILPLiquidityManager.CollateralInfo memory infoAfter = lpManager.getLPInfo(lp1);
        assertEq(
            infoAfter.collateralAmount,
            infoBefore.collateralAmount + 150e18,
            "Collateral should increase by added amount"
        );
    }

    // ----------------------------------------------------------------------------------
    //                              HELPER FUNCTIONS
    // ----------------------------------------------------------------------------------

    // Helper function to complete a cycle for testing
    function completeCycle(
        IAssetPool _targetPool, 
        address _lp1, 
        address _lp2, 
        uint256 price
    ) internal {
        // Move to after rebalance start
        vm.warp(block.timestamp + CYCLE_LENGTH + 1);
        
        // Complete rebalancing
        _targetPool.initiateOffchainRebalance();
        
        vm.warp(block.timestamp + REBALANCE_LENGTH + 1);
        assetOracle.setAssetPrice(price);

        _targetPool.initiateOnchainRebalance();
        
        // LP1 rebalance
        vm.prank(_lp1);
        _targetPool.rebalancePool(_lp1, price);

        // LP2 rebalance
        vm.prank(_lp2);
        _targetPool.rebalancePool(_lp2, price);
    }

}

// Mock ERC20 contract for testing
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimalsValue
    ) ERC20(name, symbol) {
        _decimals = decimalsValue;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

// Mock asset oracle contract for testing
contract MockAssetOracle {
    uint256 public assetPrice;
    uint256 public lastUpdated;
    
    constructor() {
        assetPrice = 1e18; // Default to 1.0
        lastUpdated = block.timestamp;
    }
    
    // Test helper to set price
    function setAssetPrice(uint256 newPrice) external {
        assetPrice = newPrice;
        lastUpdated = block.timestamp;
    }
}
