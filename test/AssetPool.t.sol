// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/protocol/AssetPoolFactory.sol";
import "../src/protocol/AssetPool.sol";
import "../src/protocol/xToken.sol";
import "../src/protocol/PoolLiquidityManager.sol";
import "../src/interfaces/IAssetPool.sol";
import "../src/interfaces/IAssetOracle.sol";
import "../src/interfaces/IPoolLiquidityManager.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract AssetPoolTest is Test {
    // Test contracts
    AssetPoolFactory public factory;
    AssetPool public implementation;
    IAssetPool public pool;
    IERC20Metadata public reserveToken;
    IXToken public assetToken;
    IPoolLiquidityManager public liquidityManager;
    MockAssetOracle assetOracle;

    // Test addresses
    address owner = address(1);
    address user1 = address(2);
    address user2 = address(3);
    address lp1 = address(4);
    address lp2 = address(5);

    // Test constants
    uint256 constant INITIAL_BALANCE = 1000000000e18;
    uint256 constant CYCLE_LENGTH = 7 days;
    uint256 constant REBALANCE_LENGTH = 1 days;
    uint256 constant LP_LIQUIDITY_AMOUNT = 1000e18;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock USDC
        MockERC20 mockUSDC = new MockERC20("USDC", "USDC", 18);
        reserveToken = IERC20Metadata(address(mockUSDC));

        // Deploy core contracts
        assetOracle = new MockAssetOracle();
        
        // Deploy LP Liquidity Manager Implementation
        PoolLiquidityManager liquidityManagerImpl = new PoolLiquidityManager();
        
        // Deploy AssetPool Implementation
        implementation = new AssetPool();
        
        // Deploy AssetPool Factory
        factory = new AssetPoolFactory(address(liquidityManagerImpl), address(implementation));

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
        liquidityManager = pool.poolLiquidityManager();

        vm.stopPrank();

        // Fund test accounts
        deal(address(reserveToken), user1, INITIAL_BALANCE);
        deal(address(reserveToken), user2, INITIAL_BALANCE);
        deal(address(reserveToken), lp1, INITIAL_BALANCE);
        deal(address(reserveToken), lp2, INITIAL_BALANCE);

        // Register LPs
        vm.startPrank(lp1);
        reserveToken.approve(address(liquidityManager), INITIAL_BALANCE);
        liquidityManager.registerLP(LP_LIQUIDITY_AMOUNT);
        // Add extra collateral to avoid InsufficientCollateral errors
        liquidityManager.deposit(LP_LIQUIDITY_AMOUNT);
        vm.stopPrank();

        vm.startPrank(lp2);
        reserveToken.approve(address(liquidityManager), INITIAL_BALANCE);
        liquidityManager.registerLP(LP_LIQUIDITY_AMOUNT);
        // Add extra collateral to avoid InsufficientCollateral errors
        liquidityManager.deposit(LP_LIQUIDITY_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + 1);
    }

    // --------------------------------------------------------------------------------
    //                              POOL IMPLEMENTATION TESTS
    // --------------------------------------------------------------------------------

    function testDepositReserve() public {
        uint256 depositAmount = 100e18;
        
        vm.startPrank(user1);
        reserveToken.approve(address(pool), depositAmount);
        pool.depositRequest(depositAmount);
        vm.stopPrank();

        UserRequest memory request = getUserRequest(user1);

        // Assert the request details
        assertEq(request.amount, depositAmount);
        assertTrue(request.isDeposit);
        assertEq(request.requestCycle, 0); // First cycle

        // Assert total deposit requests for the cycle
        assertEq(pool.cycleTotalDepositRequests(), depositAmount);

        // Assert the reserve tokens were transferred
        assertEq(reserveToken.balanceOf(address(pool)), depositAmount);
        assertEq(reserveToken.balanceOf(user1), INITIAL_BALANCE - depositAmount);
    }

    function testDepositReserveReverts() public {
        vm.startPrank(user1);
        
        // Test zero amount
        vm.expectRevert(IAssetPool.InvalidAmount.selector);
        pool.depositRequest(0);

        // Test insufficient allowance
        bytes memory error = abi.encodeWithSignature(
            "ERC20InsufficientAllowance(address,uint256,uint256)", 
            address(pool), 0, 100e18
        );
        vm.expectRevert(error);
        pool.depositRequest(100e18);

        vm.stopPrank();
    }

    function testCancelDepositRequest() public {
        uint256 depositAmount = 100e18;
        
        // Setup deposit
        vm.startPrank(user1);
        reserveToken.approve(address(pool), depositAmount);
        pool.depositRequest(depositAmount);
        
        // Cancel deposit
        pool.cancelRequest();
        vm.stopPrank();

        UserRequest memory request = getUserRequest(user1);

        // Assert the request was cancelled
        assertEq(request.amount, 0);
        
        // Assert total deposit requests updated
        assertEq(pool.cycleTotalDepositRequests(), 0);
 
        // Assert the reserve tokens were returned
        assertEq(reserveToken.balanceOf(user1), INITIAL_BALANCE);
    }

    function testClaimAsset() public {
        // Verify user has assets before minting
        uint256 userBalance = assetToken.balanceOf(user1);
        assertEq(userBalance, 0, "User should have no assets initially");

        // Setup deposit
        uint256 depositAmount = 100e18;
        vm.startPrank(user1);
        reserveToken.approve(address(pool), depositAmount);
        pool.depositRequest(depositAmount);
        vm.stopPrank();

        // Complete cycle
        completeCycle(pool, lp1, lp2, 1e18);
        
        // Claim assets
        pool.claimRequest(user1);

        // Verify assets were minted
        uint256 newUserBalance = assetToken.balanceOf(user1);
        assertGt(newUserBalance, userBalance, "Asset minting failed");
        
        // Check request was cleared
        UserRequest memory request = getUserRequest(user1);
        assertEq(request.amount, 0, "Request should be cleared after claiming");
    }

    // --------------------------------------------------------------------------------
    //                              REBALANCING TESTS
    // --------------------------------------------------------------------------------

    function testInitiateRebalance() public {
        // Setup initial deposits
        vm.startPrank(user1);
        reserveToken.approve(address(pool), 100e18);
        pool.depositRequest(100e18);
        vm.stopPrank();

        // Move time to rebalance period
        vm.warp(block.timestamp + CYCLE_LENGTH + 1);
        
        // Initiate rebalance
        pool.initiateOffchainRebalance(); 
        assertEq(uint8(pool.cycleState()), uint8(IAssetPool.CycleState.REBALANCING_OFFCHAIN));
        
        vm.warp(block.timestamp + REBALANCE_LENGTH + 1);
        assetOracle.setAssetPrice(1e18);

        pool.initiateOnchainRebalance();
        assertEq(uint8(pool.cycleState()), uint8(IAssetPool.CycleState.REBALANCING_ONCHAIN));

        assertEq(pool.rebalancedLPs(), 0);
    }

    function testRebalancePool() public {
        // Setup initial deposits
        vm.startPrank(user1);
        reserveToken.approve(address(pool), 100e18);
        pool.depositRequest(100e18);
        vm.stopPrank();

        // Move time to after rebalance start
        vm.warp(block.timestamp + CYCLE_LENGTH + 1);
        
        // Initiate rebalance
        pool.initiateOffchainRebalance(); 
        
        vm.warp(block.timestamp + REBALANCE_LENGTH + 1);
        assetOracle.setAssetPrice(1e18);

        pool.initiateOnchainRebalance();
        
        uint256 rebalancePrice = 1e18;
        
        // LP1 rebalance
        vm.startPrank(lp1);
        pool.rebalancePool(lp1, rebalancePrice);
        vm.stopPrank();

        // Check LP1 rebalanced - this should be 1 after the first LP rebalances
        assertEq(pool.lastRebalancedCycle(lp1), pool.cycleIndex(), "LP1 cycle not updated");
        assertEq(pool.rebalancedLPs(), 1, "LP1 not counted in rebalancedLPs");
        
        // LP2 rebalance
        vm.startPrank(lp2);
        pool.rebalancePool(lp2, rebalancePrice);
        vm.stopPrank();
        
        // Check cycle completed - rebalancedLPs should reset to 0 since cycle advances
        assertEq(pool.lastRebalancedCycle(lp2), pool.cycleIndex()-1, "LP2 cycle not updated");
        assertEq(pool.rebalancedLPs(), 0, "rebalancedLPs not reset for new cycle");
        assertEq(pool.cycleIndex(), 1, "Cycle not advanced"); 
        assertEq(uint8(pool.cycleState()), uint8(IAssetPool.CycleState.ACTIVE), "Not back to active state");
    }

    // --------------------------------------------------------------------------------
    //                              REDEMPTION TESTS
    // --------------------------------------------------------------------------------

    function testRedemptionRequest() public {
        // Setup deposit
        uint256 depositAmount = 100e18;
        vm.startPrank(user1);
        reserveToken.approve(address(pool), depositAmount);
        pool.depositRequest(depositAmount);
        vm.stopPrank();

        // Complete deposit cycle
        completeCycle(pool, lp1, lp2, 1e18);
        
        // Claim assets
        pool.claimRequest(user1);

        // Verify user has assets before burning
        uint256 userBalance = assetToken.balanceOf(user1);
        assertGt(userBalance, 0, "User should have assets to burn");

        uint256 burnAmount = userBalance / 2; // Burn half of the balance
        
        vm.startPrank(user1);
        assetToken.approve(address(pool), burnAmount);
        pool.redemptionRequest(burnAmount);
        vm.stopPrank();

        UserRequest memory request = getUserRequest(user1);

        // Assert the request details
        assertEq(request.amount, burnAmount);
        assertFalse(request.isDeposit);
        assertEq(request.requestCycle, 1);
        
        // Check total redemption requests
        assertEq(pool.cycleTotalRedemptionRequests(), burnAmount);
    }

    function testCancelRedemptionRequest() public {
        // Setup deposit
        uint256 depositAmount = 100e18;
        vm.startPrank(user1);
        reserveToken.approve(address(pool), depositAmount);
        pool.depositRequest(depositAmount);
        vm.stopPrank();

        // Complete deposit cycle
        completeCycle(pool, lp1, lp2, 1e18);
        
        // Claim assets
        pool.claimRequest(user1);

        // Verify user has assets before burning
        uint256 userBalance = assetToken.balanceOf(user1);
        assertGt(userBalance, 0, "User should have assets");

        uint256 burnAmount = userBalance / 2; // Burn half of the balance

        vm.startPrank(user1);
        assetToken.approve(address(pool), burnAmount);
        pool.redemptionRequest(burnAmount);
        
        // Verify request was created
        UserRequest memory request = getUserRequest(user1);
        assertEq(request.amount, burnAmount);

        // Cancel burn
        pool.cancelRequest();
        vm.stopPrank();

        // Verify request was cancelled
        request = getUserRequest(user1);
        assertEq(request.amount, 0);
        
        // Verify total redemption requests updated
        assertEq(pool.cycleTotalRedemptionRequests(), 0);
        
        // Verify asset tokens returned
        assertEq(assetToken.balanceOf(user1), userBalance);
    }

    function testClaimReserve() public {
        // Setup initial deposit
        uint256 depositAmount = 100e18;
        vm.startPrank(user1);
        reserveToken.approve(address(pool), depositAmount);
        pool.depositRequest(depositAmount);
        vm.stopPrank();

        vm.startPrank(lp1);
        liquidityManager.deposit(LP_LIQUIDITY_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(lp2);
        liquidityManager.deposit(LP_LIQUIDITY_AMOUNT);
        vm.stopPrank();

        // Complete first cycle (deposit cycle)
        completeCycle(pool, lp1, lp2, 1e18);
        
        // Claim assets
        pool.claimRequest(user1);
        
        // Record reserve balance before redemption
        uint256 initialReserveBalance = reserveToken.balanceOf(user1);
        
        // Request redemption of half the assets
        uint256 burnAmount = assetToken.balanceOf(user1) / 2;
        vm.startPrank(user1);
        assetToken.approve(address(pool), burnAmount);
        pool.redemptionRequest(burnAmount);
        vm.stopPrank();
        
        vm.startPrank(lp1);
        liquidityManager.deposit(LP_LIQUIDITY_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(lp2);
        liquidityManager.deposit(LP_LIQUIDITY_AMOUNT);
        vm.stopPrank();
        
        // Complete second cycle (redemption cycle) with price 2.0
        completeCycle(pool, lp1, lp2, 2e18);
        
        // Claim reserve tokens
        pool.claimRequest(user1);
        
        // Verify pending request was cleared
        UserRequest memory request = getUserRequest(user1);
        assertEq(request.amount, 0);

        // Assert that the user has received reserve tokens
        uint256 finalReserveBalance = reserveToken.balanceOf(user1);
        assertGt(finalReserveBalance, initialReserveBalance, "User should have received reserve tokens");
    }

    // --------------------------------------------------------------------------------
    //                             CLAIM TESTS
    // --------------------------------------------------------------------------------

    function testClaimAssetWithDecimalPrecision() public {
        // Test with different reserve token decimals
        MockERC20 usdc6 = new MockERC20("USDC", "USDC", 6);
        MockERC20 dai18 = new MockERC20("DAI", "DAI", 18);
        
        // Create pools with different reserve tokens
        vm.startPrank(owner);
        address pool6 = factory.createPool(
            address(usdc6),
            "Stock Token 6 Decimals",
            "xSTK6",
            address(assetOracle),
            CYCLE_LENGTH,
            REBALANCE_LENGTH
        );
        
        address pool18 = factory.createPool(
            address(dai18),
            "Stock Token 18 Decimals",
            "xSTK18",
            address(assetOracle),
            CYCLE_LENGTH,
            REBALANCE_LENGTH
        );
        vm.stopPrank();
        
        // Get pool instances
        IAssetPool poolUsdc = IAssetPool(pool6);
        IAssetPool poolDai = IAssetPool(pool18);
        IPoolLiquidityManager liquidityManagerUsdc = poolUsdc.poolLiquidityManager();
        IPoolLiquidityManager liquidityManagerDai = poolDai.poolLiquidityManager();
        
        // Fund accounts
        deal(address(usdc6), user1, 10000 * 10**6); // 10000 USDC with 6 decimals
        deal(address(dai18), user1, 10000 * 10**18); // 10000 DAI with 18 decimals
        deal(address(usdc6), lp1, 100000 * 10**6);
        deal(address(usdc6), lp2, 100000 * 10**6);
        deal(address(dai18), lp1, 100000 * 10**18);
        deal(address(dai18), lp2, 100000 * 10**18);
        
        // Register LPs for both pools with extra collateral
        vm.startPrank(lp1);
        usdc6.approve(address(liquidityManagerUsdc), 500e6);
        liquidityManagerUsdc.registerLP(100e6);
        liquidityManagerUsdc.deposit(200e6); // Add extra collateral
        
        dai18.approve(address(liquidityManagerDai), 500e18);
        liquidityManagerDai.registerLP(100e18);
        liquidityManagerDai.deposit(200e18); // Add extra collateral
        vm.stopPrank();
        
        vm.startPrank(lp2);
        usdc6.approve(address(liquidityManagerUsdc), 500e6);
        liquidityManagerUsdc.registerLP(100e6);
        liquidityManagerUsdc.deposit(200e6); // Add extra collateral
        
        dai18.approve(address(liquidityManagerDai), 500e18);
        liquidityManagerDai.registerLP(100e18);
        liquidityManagerDai.deposit(200e18); // Add extra collateral
        vm.stopPrank();
        
        IXToken assetTokenUsdc = poolUsdc.assetToken();
        IXToken assetTokenDai = poolDai.assetToken();
        
        // Test USDC pool (6 decimals)
        uint256 usdcAmount = 1000 * 10**6; // 1000 USDC
        vm.startPrank(user1);
        usdc6.approve(pool6, usdcAmount);
        poolUsdc.depositRequest(usdcAmount);
        vm.stopPrank();
        
        // Complete cycle for USDC pool
        completeCycleForPool(poolUsdc, lp1, lp2, 1 * 10**18); // price = 1.0
        
        // Record balances before claim
        uint256 user1AssetBalanceBefore = assetTokenUsdc.balanceOf(user1);
        
        // Claim assets
        poolUsdc.claimRequest(user1);
        
        // Assert correct amount was minted - should be adjusted for 6->18 decimal conversion
        uint256 expectedUsdcAssets = usdcAmount * 10**12; // Convert 6 decimals to 18
        assertEq(
            assetTokenUsdc.balanceOf(user1) - user1AssetBalanceBefore,
            expectedUsdcAssets,
            "USDC (6 decimals): Incorrect asset amount minted"
        );
        
        // Test DAI pool (18 decimals)
        uint256 daiAmount = 1000 * 10**18; // 1000 DAI
        vm.startPrank(user1);
        dai18.approve(pool18, daiAmount);
        poolDai.depositRequest(daiAmount);
        vm.stopPrank();
        
        // Complete cycle for DAI pool
        completeCycleForPool(poolDai, lp1, lp2, 1 * 10**18); // price = 1.0
        
        // Record balances before claim
        uint256 user1DaiAssetBalanceBefore = assetTokenDai.balanceOf(user1);
        
        // Claim assets
        poolDai.claimRequest(user1);
        
        // Assert correct amount was minted - no decimal adjustment needed
        uint256 expectedDaiAssets = daiAmount; // No conversion needed for 18->18 decimals
        assertEq(
            assetTokenDai.balanceOf(user1) - user1DaiAssetBalanceBefore,
            expectedDaiAssets,
            "DAI (18 decimals): Incorrect asset amount minted"
        );
    }

     function testClaimReserveWithUSDC() public {
        // Create USDC with 6 decimals
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);
        
        // Create pool with USDC as reserve
        vm.startPrank(owner);
        address poolAddr = factory.createPool(
            address(usdc),
            "Stock Token 6 Decimals",
            "xSTK6",
            address(assetOracle),
            CYCLE_LENGTH,
            REBALANCE_LENGTH
        );
        vm.stopPrank();
        
        // Get pool instance
        IAssetPool usdcPool = IAssetPool(poolAddr);
        IPoolLiquidityManager liquidityManagerUsdc = usdcPool.poolLiquidityManager();
        IXToken usdcAssetToken = usdcPool.assetToken();
        
        // Fund accounts (6 decimals)
        uint256 userFundAmount = 10000 * 10**6;
        uint256 lpFundAmount = 1000000 * 10**6;
        uint256 depositAmount = 1000 * 10**6;
        
        deal(address(usdc), user1, userFundAmount);
        deal(address(usdc), lp1, lpFundAmount);
        deal(address(usdc), lp2, lpFundAmount);
        
        // Register LPs with extra collateral
        vm.startPrank(lp1);
        usdc.approve(address(liquidityManagerUsdc), lpFundAmount);
        liquidityManagerUsdc.registerLP(30000 * 10**6);
        liquidityManagerUsdc.deposit(20000 * 10**6); // Add extra collateral
        vm.stopPrank();
        
        vm.startPrank(lp2);
        usdc.approve(address(liquidityManagerUsdc), lpFundAmount);
        liquidityManagerUsdc.registerLP(30000 * 10**6);
        liquidityManagerUsdc.deposit(20000 * 10**6); // Add extra collateral
        vm.stopPrank();
        
        // First, deposit and claim assets
        vm.startPrank(user1);
        usdc.approve(poolAddr, depositAmount);
        usdcPool.depositRequest(depositAmount);
        vm.stopPrank();
        
        // Complete deposit cycle
        completeCycleForPool(usdcPool, lp1, lp2, 1 * 10**18);
        usdcPool.claimRequest(user1);
        
        // Request redemption
        uint256 assetAmount = usdcAssetToken.balanceOf(user1) / 2; // Redeem half
        vm.startPrank(user1);
        usdcAssetToken.approve(poolAddr, assetAmount);
        usdcPool.redemptionRequest(assetAmount);
        vm.stopPrank();
        
        // Record balance before redeeming
        uint256 usdcBalanceBefore = usdc.balanceOf(user1);
        
        // Complete redemption cycle with price of 2.0
        completeCycleForPool(usdcPool, lp1, lp2, 2 * 10**18);
        
        // Claim reserve tokens
        usdcPool.claimRequest(user1);
        
        // Verify user received USDC
        uint256 usdcBalanceAfter = usdc.balanceOf(user1);
        assertGt(usdcBalanceAfter, usdcBalanceBefore, "USDC: User should have received reserve tokens");
        
        // Calculate expected USDC amount with adjustment for decimals and price
        uint256 expectedUsdcAmount = (assetAmount * 2 * 10**18) / (10**18 * 10**12);
        assertApproxEqAbs(
            usdcBalanceAfter - usdcBalanceBefore,
            expectedUsdcAmount,
            10**6, // Allow for small rounding errors
            "USDC: Incorrect reserve amount"
        );
    }
    
    function testClaimReserveWithDAI() public {
        // Create DAI with 18 decimals
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);
        
        // Create pool with DAI as reserve
        vm.startPrank(owner);
        address poolAddr = factory.createPool(
            address(dai),
            "Stock Token 18 Decimals",
            "xSTK18",
            address(assetOracle),
            CYCLE_LENGTH,
            REBALANCE_LENGTH
        );
        vm.stopPrank();
        
        // Get pool instance
        IAssetPool daiPool = IAssetPool(poolAddr);
        IPoolLiquidityManager liquidityManagerDai = daiPool.poolLiquidityManager();
        IXToken daiAssetToken = daiPool.assetToken();
        
        // Fund accounts (18 decimals)
        uint256 userFundAmount = 10000 * 10**18;
        uint256 lpFundAmount = 1000000 * 10**18;
        uint256 depositAmount = 1000 * 10**18;
        
        deal(address(dai), user1, userFundAmount);
        deal(address(dai), lp1, lpFundAmount);
        deal(address(dai), lp2, lpFundAmount);
        
        // Register LPs with extra collateral
        vm.startPrank(lp1);
        dai.approve(address(liquidityManagerDai), lpFundAmount);
        liquidityManagerDai.registerLP(30000 * 10**18);
        liquidityManagerDai.deposit(20000 * 10**18); // Add extra collateral
        vm.stopPrank();
        
        vm.startPrank(lp2);
        dai.approve(address(liquidityManagerDai), lpFundAmount);
        liquidityManagerDai.registerLP(30000 * 10**18);
        liquidityManagerDai.deposit(20000 * 10**18); // Add extra collateral
        vm.stopPrank();
        
        // First, deposit and claim assets
        vm.startPrank(user1);
        dai.approve(poolAddr, depositAmount);
        daiPool.depositRequest(depositAmount);
        vm.stopPrank();
        
        // Complete deposit cycle
        completeCycleForPool(daiPool, lp1, lp2, 1 * 10**18);
        daiPool.claimRequest(user1);
        
        // Request redemption
        uint256 assetAmount = daiAssetToken.balanceOf(user1) / 2; // Redeem half
        vm.startPrank(user1);
        daiAssetToken.approve(poolAddr, assetAmount);
        daiPool.redemptionRequest(assetAmount);
        vm.stopPrank();
        
        // Record balance before redeeming
        uint256 daiBalanceBefore = dai.balanceOf(user1);
        
        // Complete redemption cycle with price of 2.0
        completeCycleForPool(daiPool, lp1, lp2, 2 * 10**18);
        
        // Claim reserve tokens
        daiPool.claimRequest(user1);
        
        // Verify user received DAI
        uint256 daiBalanceAfter = dai.balanceOf(user1);
        assertGt(daiBalanceAfter, daiBalanceBefore, "DAI: User should have received reserve tokens");
        
        // Calculate expected DAI amount (no decimal adjustment needed for 18->18 decimals)
        uint256 expectedDaiAmount = assetAmount * 2;
        assertEq(
            daiBalanceAfter - daiBalanceBefore,
            expectedDaiAmount,
            "DAI: Incorrect reserve amount"
        );
    }

    // --------------------------------------------------------------------------------
    //                              GOVERNANCE TESTS
    // --------------------------------------------------------------------------------

    function testPausePool() public {
        vm.prank(owner);
        pool.pausePool();
        
        // Test that operations revert when paused
        bytes memory error = abi.encodeWithSignature("EnforcedPause()");
        vm.expectRevert(error);
        pool.depositRequest(100e18);
    }

    function testUnpausePool() public {
        // First pause the pool
        vm.prank(owner);
        pool.pausePool();
        
        // Then unpause
        vm.prank(owner);
        pool.unpausePool();
        
        // Test that operations work after unpausing
        uint256 depositAmount = 100e18;
        vm.startPrank(user1);
        reserveToken.approve(address(pool), depositAmount);
        pool.depositRequest(depositAmount); // Should succeed
        vm.stopPrank();
        
        // Verify deposit succeeded
        UserRequest memory request = getUserRequest(user1);
        assertEq(request.amount, depositAmount);
    }

    // --------------------------------------------------------------------------------
    //                              HELPER FUNCTIONS
    // --------------------------------------------------------------------------------

    // Helper function to get user request struct
    function getUserRequest(address user) internal view returns (UserRequest memory) {
        (uint256 amount, bool isDeposit, uint256 requestCycle) = pool.pendingRequests(user);
        return UserRequest({
            amount: amount,
            isDeposit: isDeposit,
            requestCycle: requestCycle
        });
    }

    // Helper struct for user requests
    struct UserRequest {
        uint256 amount;
        bool isDeposit;
        uint256 requestCycle;
    }

    // Helper function to complete a cycle for the main pool
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
    
    // Helper function to complete a cycle for any pool
    function completeCycleForPool(
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