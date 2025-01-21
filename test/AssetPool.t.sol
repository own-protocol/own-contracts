// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/protocol/AssetPool.sol";
import "../src/protocol/xToken.sol";
import "../src/protocol/LPRegistry.sol";
import "../src/protocol/AssetOracle.sol";
import "../src/interfaces/IAssetPool.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract AssetPoolTest is Test {
    // Test contracts
    AssetPool public pool;
    IERC20 public reserveToken;
    xToken public assetToken;
    LPRegistry public lpRegistry;
    AssetOracle public assetOracle;

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
        assetOracle = new AssetOracle(
            address(0), // Mock router address
            "TSLA",
            bytes32(0) // Mock source hash
        );

        pool = new AssetPool(
            address(reserveToken),
            "Tesla Stock Token",
            "xTSLA",
            address(assetOracle),
            address(lpRegistry),
            CYCLE_PERIOD,
            REBALANCE_PERIOD,
            owner
        );

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
    //                              DEPLOYMENT TESTS
    // --------------------------------------------------------------------------------

    function testConstructor() public view {
        assertEq(address(pool.reserveToken()), address(reserveToken));
        assertEq(address(pool.lpRegistry()), address(lpRegistry));
        assertEq(address(pool.assetOracle()), address(assetOracle));
        assertEq(pool.cycleTime(), CYCLE_PERIOD);
        assertEq(pool.rebalanceTime(), REBALANCE_PERIOD);
    }

    function testConstructorReverts() public {
        vm.expectRevert(IAssetPool.ZeroAddress.selector);
        new AssetPool(
            address(0),
            "Tesla Stock Token",
            "xTSLA",
            address(assetOracle),
            address(lpRegistry),
            CYCLE_PERIOD,
            REBALANCE_PERIOD,
            owner
        );
    }

    // --------------------------------------------------------------------------------
    //                              DEPOSIT TESTS
    // --------------------------------------------------------------------------------

    function testDepositReserve() public {
        uint256 depositAmount = 100e18;
        
        vm.startPrank(user1);
        reserveToken.approve(address(pool), depositAmount);
        pool.depositReserve(depositAmount);
        vm.stopPrank();

        assertEq(pool.cycleDepositRequests(0, user1), depositAmount);
        assertEq(pool.cycleTotalDepositRequests(0), depositAmount);
        assertEq(pool.lastActionCycle(user1), 0);
    }

    function testDepositReserveReverts() public {
        vm.startPrank(user1);
        
        // Test zero amount
        vm.expectRevert(IAssetPool.InvalidAmount.selector);
        pool.depositReserve(0);

        // Test insufficient allowance
        bytes memory error = abi.encodeWithSignature(
            "ERC20InsufficientAllowance(address,uint256,uint256)", 
            address(pool), 0, 100e18
        );
        vm.expectRevert(error);
        pool.depositReserve(100e18);

        vm.stopPrank();
    }

    function testCancelDeposit() public {
        uint256 depositAmount = 100e18;
        
        // Setup deposit
        vm.startPrank(user1);
        reserveToken.approve(address(pool), depositAmount);
        pool.depositReserve(depositAmount);
        
        // Cancel deposit
        pool.cancelDeposit();
        vm.stopPrank();

        assertEq(pool.cycleDepositRequests(0, user1), 0);
        assertEq(pool.cycleTotalDepositRequests(0), 0);
        assertEq(pool.lastActionCycle(user1), 0);
    }

    function testMintAsset() public {

        // Verify user has assets before minting
        uint256 userBalance = assetToken.balanceOf(user1);
        assertEq(userBalance, 0, "User should have assets to mint");

        setupCompleteDepositCycle();

        pool.mintAsset(user1);

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
        pool.depositReserve(100e18);
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
        pool.depositReserve(100e18);
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

        assertTrue(pool.hasRebalanced(lp1));
        assertEq(pool.rebalancedLPs(), 1);
    }

    // --------------------------------------------------------------------------------
    //                              REDEMPTION TESTS
    // --------------------------------------------------------------------------------

    function testBurnAsset() public {
        // Setup: Complete a cycle first to have assets to burn
        setupCompleteDepositCycle();

        pool.mintAsset(user1);

        // Verify user has assets before burning
        uint256 userBalance = assetToken.balanceOf(user1);
        assertGt(userBalance, 0, "User should have assets to burn");

        uint256 burnAmount = userBalance / 2; // Burn half of the balance
        
        vm.startPrank(user1);
        assetToken.approve(address(pool), burnAmount);
        pool.burnAsset(burnAmount);
        vm.stopPrank();

        assertEq(pool.cycleRedemptionRequests(pool.cycleIndex(), user1), burnAmount);
    }

    // --------------------------------------------------------------------------------
    //                              GOVERNANCE TESTS
    // --------------------------------------------------------------------------------

    function testUpdateCycleTime() public {
        uint256 newCycleTime = 14 days;
        
        vm.prank(owner);
        pool.updateCycleTime(newCycleTime);
        
        assertEq(pool.cycleTime(), newCycleTime);
    }

    function testPausePool() public {
        vm.prank(owner);
        pool.pausePool();
        
        assertTrue(pool.paused());
        
        // Test that operations revert when paused
        bytes memory error = abi.encodeWithSignature("EnforcedPause()");
        vm.expectRevert(error);
        pool.depositReserve(100e18);
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
        pool.depositReserve(depositAmount);
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

        // Move to next cycle start
        vm.warp(block.timestamp + REBALANCE_PERIOD + 1);
        
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