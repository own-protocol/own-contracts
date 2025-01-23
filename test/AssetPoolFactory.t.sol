// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/protocol/AssetPoolFactory.sol";
import "../src/protocol/AssetPoolImplementation.sol";
import "../src/protocol/xToken.sol";
import "../src/protocol/LPRegistry.sol";
import "../src/interfaces/IAssetPool.sol";
import "../src/interfaces/IAssetOracle.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract AssetPoolFactoryTest is Test {
    // Test contracts
    AssetPoolFactory public factory;
    AssetPoolImplementation public implementation;
    IAssetPool public pool;
    IERC20 public reserveToken;
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
    uint256 constant CYCLE_PERIOD = 7 days;
    uint256 constant REBALANCE_PERIOD = 1 days;

    function setUp() public {

        vm.startPrank(owner);

        // Deploy mock USDC
        MockERC20 mockUSDC = new MockERC20("USDC", "USDC", 18);
        reserveToken = IERC20(address(mockUSDC));

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
            CYCLE_PERIOD,
            REBALANCE_PERIOD
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
    //                              FACTORY TESTS
    // --------------------------------------------------------------------------------

    function testFactoryDeployment() public view {
        assertEq(address(factory.lpRegistry()), address(lpRegistry));
        assertEq(factory.assetPoolImplementation(), address(implementation));
    }

    function testCreatePool() public {
        vm.startPrank(owner);
        address newPool = factory.createPool(
            address(reserveToken),
            "Apple Stock Token",
            "xAAPL",
            address(assetOracle),
            CYCLE_PERIOD,
            REBALANCE_PERIOD
        );
        vm.stopPrank();

        assertTrue(newPool != address(0));
        IAssetPool poolInstance = IAssetPool(newPool);
        assertEq(address(poolInstance.reserveToken()), address(reserveToken));
        assertEq(poolInstance.cycleTime(), CYCLE_PERIOD);
        assertEq(poolInstance.rebalanceTime(), REBALANCE_PERIOD);
    }

    function testCreatePoolReverts() public {
        vm.startPrank(owner);
        vm.expectRevert(IAssetPoolFactory.InvalidParams.selector);
        factory.createPool(
            address(0),
            "Apple Stock Token",
            "xAAPL",
            address(assetOracle),
            CYCLE_PERIOD,
            REBALANCE_PERIOD
        );
        vm.stopPrank();
    }

    function testUpdateLPRegistry() public {
        address newRegistry = address(new LPRegistry());
        
        vm.prank(owner);
        factory.updateLPRegistry(newRegistry);
        
        assertEq(address(factory.lpRegistry()), newRegistry);
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
        assertEq(userBalance, 0, "User should have assets to mint");

        setupCompleteDepositCycle();

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
        vm.warp(block.timestamp + CYCLE_PERIOD + 1);
        
        // Initiate rebalance
        pool.initiateRebalance();
        
        assertEq(uint8(pool.cycleState()), uint8(IAssetPool.CycleState.REBALANCING));
        assertEq(pool.rebalancedLPs(), 0);
    }

    function testRebalancePool() public {
        // Setup initial deposits
        vm.startPrank(user1);
        reserveToken.approve(address(pool), 100e18);
        pool.depositRequest(100e18);
        vm.stopPrank();

        // Move time to after rebalance start
        vm.warp(block.timestamp + CYCLE_PERIOD + 1);
        
        // Initiate rebalance
        pool.initiateRebalance();

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
        // Setup: Complete a cycle first to have assets to burn
        setupCompleteDepositCycle();

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
        // Setup: Complete a cycle first to have assets to burn
        setupCompleteDepositCycle();

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
        // complete the deposit & burn cycle
        setupCompleteBurnCycle();

        // withdraw the reserve tokens
        pool.claimRequest(user1);
        (uint256 amount,,) = pool.pendingRequests(user1);
        assertEq(amount, 0);

        // assert that the user has received the reserve tokens
        uint256 userBalance = reserveToken.balanceOf(user1);
        assertGt(userBalance, 0, "User should have received reserve tokens");
    }

    // ToDO: Add tests to validate rebalance amount & reserve balances & asset balances pre & post rebalance

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

    function setupCompleteDepositCycle() internal {
        // Setup initial balance
        uint256 depositAmount = 100e18;

        // Setup deposit
        vm.startPrank(user1);
        reserveToken.approve(address(pool), depositAmount);
        pool.depositRequest(depositAmount);
        vm.stopPrank();

        // Move to after rebalance start
        vm.warp(block.timestamp + CYCLE_PERIOD + 1);
        
        // Complete rebalancing
        pool.initiateRebalance();
        
        // Get rebalance info
        (, , , int256 rebalanceAmount) = pool.getLPInfo();
        uint256 expectedAmount = uint256(rebalanceAmount > 0 ? rebalanceAmount : -rebalanceAmount) / 2;
        bool isDeposit = rebalanceAmount > 0;
        uint256 rebalancePrice = 1e18;

        // LP1 rebalance
        vm.startPrank(lp1);
        reserveToken.approve(address(pool), expectedAmount);
        pool.rebalancePool(lp1, rebalancePrice, expectedAmount, isDeposit);
        vm.stopPrank();

        // LP2 rebalance
        vm.startPrank(lp2);
        reserveToken.approve(address(pool), expectedAmount);
        pool.rebalancePool(lp2, rebalancePrice, expectedAmount, isDeposit);
        vm.stopPrank();
        
    }

    function setupCompleteBurnCycle() internal {

        setupCompleteDepositCycle();
        pool.claimRequest(user1);

        // Verify user has assets before burning
        uint256 userBalance = assetToken.balanceOf(user1);
        assertGt(userBalance, 0, "User should have assets");

        uint256 burnAmount = userBalance / 2; // Burn half of the balance

        vm.startPrank(user1);
        assetToken.approve(address(pool), burnAmount);
        pool.redemptionRequest(burnAmount);

        // Move to after rebalance start
        vm.warp(block.timestamp + CYCLE_PERIOD + 1);

        assetOracle.setAssetPrice(2e18);
        
        // Complete rebalancing
        pool.initiateRebalance();
        
        // Get rebalance info
        (, , , int256 rebalanceAmount) = pool.getLPInfo();

        uint256 expectedAmount = uint256(rebalanceAmount > 0 ? rebalanceAmount : -rebalanceAmount) / 2;
        bool isDeposit = rebalanceAmount > 0;
        uint256 rebalancePrice = 2e18;

        // LP1 rebalance
        vm.startPrank(lp1);
        reserveToken.approve(address(pool), expectedAmount);
        pool.rebalancePool(lp1, rebalancePrice, expectedAmount, isDeposit);
        vm.stopPrank();

        // LP2 rebalance
        vm.startPrank(lp2);
        reserveToken.approve(address(pool), expectedAmount);
        pool.rebalancePool(lp2, rebalancePrice, expectedAmount, isDeposit);
        vm.stopPrank();
        
    }
}

// Mock ERC20 contract for testing
contract MockERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) ERC20(name, symbol) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

// Mock asset oracle contract for testing
contract MockAssetOracle {
    uint256 public assetPrice;
    
    constructor() {
        assetPrice = 1e18; // Default to 1.0
    }
    
    // Test helper to set price
    function setAssetPrice(uint256 newPrice) external {
        assetPrice = newPrice;
    }
}