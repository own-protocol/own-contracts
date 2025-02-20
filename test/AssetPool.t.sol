// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/protocol/AssetPoolFactory.sol";
import "../src/protocol/AssetPoolImplementation.sol";
import "../src/protocol/xToken.sol";
import "../src/protocol/LPRegistry.sol";
import "../src/interfaces/IAssetPool.sol";
import "../src/interfaces/IAssetOracle.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract AssetPoolImplementationTest is Test {
    // Test contracts
    AssetPoolFactory public factory;
    AssetPoolImplementation public implementation;
    IAssetPool public pool;
    IERC20Metadata public reserveToken;
    xToken public assetToken;
    LPRegistry public lpRegistry;
    MockAssetOracle assetOracle;

    // Test addresses
    address owner = address(1);
    address user1 = address(2);
    address user2 = address(3);
    address lp1 = address(4);
    address lp2 = address(5);

    // Test constants
    uint256 constant INITIAL_BALANCE = 1000000e18;
    uint256 constant CYCLE_LENGTH = 7 days;
    uint256 constant REBALANCE_LENGTH = 1 days;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock USDC
        MockERC20 mockUSDC = new MockERC20("USDC", "USDC", 18);
        reserveToken = IERC20Metadata(address(mockUSDC));

        // Deploy core contracts
        lpRegistry = new LPRegistry();
        assetOracle = new MockAssetOracle();
        implementation = new AssetPoolImplementation();
        factory = new AssetPoolFactory(address(lpRegistry), address(implementation));

        assetOracle.setAssetPrice(1e18); // Set default price to 1.0

        address poolAddress = factory.createPool(
            address(reserveToken),
            "Tesla Stock Token",
            "xTSLA",
            address(assetOracle),
            CYCLE_LENGTH,
            REBALANCE_LENGTH
        );

        pool = IAssetPool(poolAddress);
        assetToken = xToken(address(pool.assetToken()));

        // Setup initial states
        lpRegistry.addPool(address(pool));
        lpRegistry.registerLP(address(pool), lp1, 100e18);
        lpRegistry.registerLP(address(pool), lp2, 100e18);
        vm.stopPrank();

        // Fund test accounts
        deal(address(reserveToken), user1, INITIAL_BALANCE);
        deal(address(reserveToken), user2, INITIAL_BALANCE);
        deal(address(reserveToken), lp1, INITIAL_BALANCE);
        deal(address(reserveToken), lp2, INITIAL_BALANCE);

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

        (uint256 amount, bool isDeposit, uint256 requestCycle) = pool.pendingRequests(user1);

        // Assert the request details
        assertEq(amount, depositAmount);
        assertTrue(isDeposit);
        assertEq(requestCycle, 0); // First cycle

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

        (uint256 amount,,) = pool.pendingRequests(user1);

        // Assert the request details
        assertEq(amount, 0);
 
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
        completeCycle(pool, lp1, lp2, reserveToken, 1e18);
        
        // Claim assets
        pool.claimRequest(user1);

        // Verify assets were minted
        uint256 newUserBalance = assetToken.balanceOf(user1);
        assertGt(newUserBalance, userBalance, "Asset minting failed");
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

        // Get rebalance info
        (, , , int256 rebalanceAmount) = pool.getLPInfo();
        
        // Calculate LP's share (lp1 has 100e18 out of total 200e18 liquidity = 50%)
        uint256 expectedAmount = uint256(rebalanceAmount > 0 ? rebalanceAmount : -rebalanceAmount) / 2;
        uint256 rebalancePrice = 1e18;

        vm.startPrank(lp1);
        reserveToken.approve(address(pool), expectedAmount);
        pool.rebalancePool(lp1, rebalancePrice, expectedAmount, rebalanceAmount > 0);
        vm.stopPrank();

        assertTrue(pool.lastRebalancedCycle(lp1) == pool.cycleIndex());
        assertEq(pool.rebalancedLPs(), 1);
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
        completeCycle(pool, lp1, lp2, reserveToken, 1e18);
        
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

        (uint256 amount, bool isDeposit, uint256 requestCycle) = pool.pendingRequests(user1);

        // Assert the request details
        assertEq(amount, burnAmount);
        assertFalse(isDeposit);
        assertEq(requestCycle, 1);
    }

    function testCancelRedemptionRequest() public {
        // Setup deposit
        uint256 depositAmount = 100e18;
        vm.startPrank(user1);
        reserveToken.approve(address(pool), depositAmount);
        pool.depositRequest(depositAmount);
        vm.stopPrank();

        // Complete deposit cycle
        completeCycle(pool, lp1, lp2, reserveToken, 1e18);
        
        // Claim assets
        pool.claimRequest(user1);

        // Verify user has assets before burning
        uint256 userBalance = assetToken.balanceOf(user1);
        assertGt(userBalance, 0, "User should have assets");

        uint256 burnAmount = userBalance / 2; // Burn half of the balance

        vm.startPrank(user1);
        assetToken.approve(address(pool), burnAmount);
        pool.redemptionRequest(burnAmount);
        (uint256 amount, bool isDeposit, uint256 requestCycle) = pool.pendingRequests(user1);
        assertEq(amount, burnAmount);

        // Cancel burn
        pool.cancelRequest();
        vm.stopPrank();

        (amount, isDeposit, requestCycle) = pool.pendingRequests(user1);
        assertEq(amount, 0);
    }

    function testClaimReserve() public {
        // Setup initial deposit
        uint256 depositAmount = 100e18;
        vm.startPrank(user1);
        reserveToken.approve(address(pool), depositAmount);
        pool.depositRequest(depositAmount);
        vm.stopPrank();

        // Complete first cycle (deposit cycle)
        completeCycle(pool, lp1, lp2, reserveToken, 1e18);
        
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
        
        // Complete second cycle (redemption cycle) with price 2.0
        completeCycle(pool, lp1, lp2, reserveToken, 2e18);
        
        // Claim reserve tokens
        pool.claimRequest(user1);
        
        // Verify pending request was cleared
        (uint256 amount,,) = pool.pendingRequests(user1);
        assertEq(amount, 0);

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
        
        // Register LPs for both pools
        lpRegistry.addPool(pool6);
        lpRegistry.addPool(pool18);
        lpRegistry.registerLP(pool6, lp1, 100e18);
        lpRegistry.registerLP(pool6, lp2, 100e18);
        lpRegistry.registerLP(pool18, lp1, 100e18);
        lpRegistry.registerLP(pool18, lp2, 100e18);
        vm.stopPrank();
        
        // Fund accounts
        deal(address(usdc6), user1, 10000 * 10**6); // 10000 USDC with 6 decimals
        deal(address(dai18), user1, 10000 * 10**18); // 10000 DAI with 18 decimals
        deal(address(usdc6), lp1, 100000 * 10**6);
        deal(address(usdc6), lp2, 100000 * 10**6);
        deal(address(dai18), lp1, 100000 * 10**18);
        deal(address(dai18), lp2, 100000 * 10**18);
        
        // Get pool instances
        IAssetPool poolUsdc = IAssetPool(pool6);
        IAssetPool poolDai = IAssetPool(pool18);
        xToken assetTokenUsdc = xToken(address(poolUsdc.assetToken()));
        xToken assetTokenDai = xToken(address(poolDai.assetToken()));
        
        // Test USDC pool (6 decimals)
        uint256 usdcAmount = 1000 * 10**6; // 1000 USDC
        vm.startPrank(user1);
        usdc6.approve(pool6, usdcAmount);
        poolUsdc.depositRequest(usdcAmount);
        vm.stopPrank();
        
        // Complete cycle for USDC pool
        completeCycle(poolUsdc, lp1, lp2, usdc6, 1 * 10**18); // price = 1.0
        
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
        completeCycle(poolDai, lp1, lp2, dai18, 1 * 10**18); // price = 1.0
        
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
        
        // Register LPs
        lpRegistry.addPool(poolAddr);
        lpRegistry.registerLP(poolAddr, lp1, 100e18);
        lpRegistry.registerLP(poolAddr, lp2, 100e18);
        vm.stopPrank();
        
        // Fund accounts (6 decimals)
        uint256 userFundAmount = 10000 * 10**6;
        uint256 lpFundAmount = 100000 * 10**6;
        uint256 depositAmount = 1000 * 10**6;
        
        deal(address(usdc), user1, userFundAmount);
        deal(address(usdc), lp1, lpFundAmount);
        deal(address(usdc), lp2, lpFundAmount);
        
        // Get pool instance
        IAssetPool usdcPool = IAssetPool(poolAddr);
        xToken usdcAssetToken = xToken(address(usdcPool.assetToken()));
        
        // First, deposit and claim assets
        vm.startPrank(user1);
        usdc.approve(poolAddr, depositAmount);
        usdcPool.depositRequest(depositAmount);
        vm.stopPrank();
        
        // Complete deposit cycle
        completeCycle(usdcPool, lp1, lp2, usdc, 1 * 10**18);
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
        completeCycle(usdcPool, lp1, lp2, usdc, 2 * 10**18);
        
        // Claim reserve tokens
        usdcPool.claimRequest(user1);
        
        // Calculate expected USDC amount (6 decimals)
        // When converting asset (18 decimals) to USDC (6 decimals) at price 2.0:
        // Need to divide by 10^12 to adjust for decimal difference
        uint256 expectedUsdcAmount = assetAmount * 2 * 10**18 / 10**30;
        
        // Assert
        assertEq(
            usdc.balanceOf(user1) - usdcBalanceBefore,
            expectedUsdcAmount,
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
        
        // Register LPs
        lpRegistry.addPool(poolAddr);
        lpRegistry.registerLP(poolAddr, lp1, 100e18);
        lpRegistry.registerLP(poolAddr, lp2, 100e18);
        vm.stopPrank();
        
        // Fund accounts (18 decimals)
        uint256 userFundAmount = 10000 * 10**18;
        uint256 lpFundAmount = 100000 * 10**18;
        uint256 depositAmount = 1000 * 10**18;
        
        deal(address(dai), user1, userFundAmount);
        deal(address(dai), lp1, lpFundAmount);
        deal(address(dai), lp2, lpFundAmount);
        
        // Get pool instance
        IAssetPool daiPool = IAssetPool(poolAddr);
        xToken daiAssetToken = xToken(address(daiPool.assetToken()));
        
        // First, deposit and claim assets
        vm.startPrank(user1);
        dai.approve(poolAddr, depositAmount);
        daiPool.depositRequest(depositAmount);
        vm.stopPrank();
        
        // Complete deposit cycle
        completeCycle(daiPool, lp1, lp2, dai, 1 * 10**18);
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
        completeCycle(daiPool, lp1, lp2, dai, 2 * 10**18);
        
        // Claim reserve tokens
        daiPool.claimRequest(user1);
        
        // Calculate expected DAI amount (18 decimals)
        // No decimal conversion needed for 18->18 decimals
        uint256 expectedDaiAmount = assetAmount * 2;
        
        // Assert
        assertEq(
            dai.balanceOf(user1) - daiBalanceBefore,
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

    // --------------------------------------------------------------------------------
    //                              HELPER FUNCTIONS
    // --------------------------------------------------------------------------------

    // Helper function to complete a cycle for any pool
    function completeCycle(
        IAssetPool _targetPool, 
        address _lp1, 
        address _lp2, 
        IERC20 token, 
        uint256 price
    ) internal {
        // Move to after rebalance start
        vm.warp(block.timestamp + CYCLE_LENGTH + 1);
        
        // Complete rebalancing
        _targetPool.initiateOffchainRebalance();
        
        vm.warp(block.timestamp + REBALANCE_LENGTH + 1);
        assetOracle.setAssetPrice(price);

        _targetPool.initiateOnchainRebalance();
        
        // Get rebalance info
        (, , , int256 rebalanceAmount) = _targetPool.getLPInfo();
        
        uint256 expectedAmount = uint256(rebalanceAmount > 0 ? rebalanceAmount : -rebalanceAmount) / 2;
        bool isDeposit = rebalanceAmount > 0;
        
        // LP1 rebalance
        vm.startPrank(_lp1);
        token.approve(address(_targetPool), expectedAmount);
        _targetPool.rebalancePool(_lp1, price, expectedAmount, isDeposit);
        vm.stopPrank();

        // LP2 rebalance
        vm.startPrank(_lp2);
        token.approve(address(_targetPool), expectedAmount);
        _targetPool.rebalancePool(_lp2, price, expectedAmount, isDeposit);
        vm.stopPrank();
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
