// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "openzeppelin-contracts/contracts/proxy/Clones.sol";
import "../src/protocol/PoolLiquidityManager.sol";
import "../src/protocol/AssetPool.sol";
import "../src/protocol/PoolCycleManager.sol";
import "../src/protocol/xToken.sol";

contract PoolLiquidityManagerTest is Test {
    // Test contracts
    PoolLiquidityManager public liquidityManager;
    AssetPool public assetPool;
    PoolCycleManager public cycleManager;
    MockERC20 public reserveToken;
    MockAssetOracle public oracle;
    xToken public assetToken;
    
    // Addresses
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    address public interestRateStrategy;
    
    // Constants
    uint256 public constant INITIAL_LIQUIDITY = 1_000_000 * 1e6; // 1M USDC
    uint256 public constant REGISTRATION_COLLATERAL_RATIO = 20_00; // 20%
    uint256 public constant CYCLE_LENGTH = 7 days;
    uint256 public constant REBALANCE_LENGTH = 1 days;

    function setUp() public {
        // Set up accounts
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        interestRateStrategy = makeAddr("interestRateStrategy");
        
        // Deploy mock contracts
        reserveToken = new MockERC20("USD Coin", "USDC", 6);
        oracle = new MockAssetOracle();
        
        // Deploy implementations
        AssetPool assetPoolImpl = new AssetPool();
        PoolCycleManager cycleManagerImpl = new PoolCycleManager();
        PoolLiquidityManager liquidityManagerImpl = new PoolLiquidityManager();
        
        // Clone implementations
        address assetPoolClone = Clones.clone(address(assetPoolImpl));
        address cycleManagerClone = Clones.clone(address(cycleManagerImpl));
        address liquidityManagerClone = Clones.clone(address(liquidityManagerImpl));
        
        // Cast to contracts
        assetPool = AssetPool(payable(assetPoolClone));
        cycleManager = PoolCycleManager(cycleManagerClone);
        liquidityManager = PoolLiquidityManager(payable(liquidityManagerClone));
        
        // Initialize AssetPool
        assetPool.initialize(
            address(reserveToken),
            "xUSDC",
            address(oracle),
            address(cycleManager),
            address(liquidityManager),
            address(interestRateStrategy),
            owner
        );
        
        // Get asset token address created by AssetPool
        address assetTokenAddress = address(assetPool.assetToken());
        assetToken = xToken(assetTokenAddress);
        
        // Initialize CycleManager
        cycleManager.initialize(
            address(reserveToken),
            assetTokenAddress,
            address(oracle),
            address(assetPool),
            address(liquidityManager),
            CYCLE_LENGTH,
            REBALANCE_LENGTH
        );
        
        // Initialize LiquidityManager
        liquidityManager.initialize(
            address(reserveToken),
            assetTokenAddress,
            address(oracle),
            address(assetPool),
            address(cycleManager),
            owner
        );
        
        // Mint some tokens to users for testing
        reserveToken.mint(user1, 1_000_000 * 1e6);
        reserveToken.mint(user2, 1_000_000 * 1e6);
        reserveToken.mint(user3, 1_000_000 * 1e6);
        
        // Approve spending for users
        vm.startPrank(user1);
        reserveToken.approve(address(liquidityManager), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        reserveToken.approve(address(liquidityManager), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user3);
        reserveToken.approve(address(liquidityManager), type(uint256).max);
        vm.stopPrank();
    }
    
    function test_RegisterLP() public {
        uint256 liquidityAmount = 100_000 * 1e6; // 100k USDC
        uint256 expectedCollateral = (liquidityAmount * REGISTRATION_COLLATERAL_RATIO) / 100_00;
        
        // Check initial state
        assertEq(liquidityManager.lpCount(), 0);
        assertEq(liquidityManager.totalLPLiquidity(), 0);
        assertFalse(liquidityManager.registeredLPs(user1));
        
        // Register LP
        vm.startPrank(user1);
        liquidityManager.registerLP(liquidityAmount);
        vm.stopPrank();
        
        // Check post-registration state
        assertEq(liquidityManager.lpCount(), 1);
        assertEq(liquidityManager.totalLPLiquidity(), liquidityAmount);
        assertTrue(liquidityManager.registeredLPs(user1));
        
        // Check LP's info
        IPoolLiquidityManager.CollateralInfo memory info = liquidityManager.getLPInfo(user1);
        assertEq(info.collateralAmount, expectedCollateral);
        assertEq(info.liquidityAmount, liquidityAmount);
        
        // Check token balances
        assertEq(reserveToken.balanceOf(address(liquidityManager)), expectedCollateral);
        assertEq(reserveToken.balanceOf(user1), 1_000_000 * 1e6 - expectedCollateral);
    }
    
    function test_IncreaseLiquidity() public {
        // First register LP
        uint256 initialLiquidity = 100_000 * 1e6; // 100k USDC
        vm.startPrank(user1);
        liquidityManager.registerLP(initialLiquidity);
        
        // Increase liquidity
        uint256 additionalLiquidity = 50_000 * 1e6; // 50k USDC
        uint256 additionalCollateral = (additionalLiquidity * REGISTRATION_COLLATERAL_RATIO) / 100_00;
        liquidityManager.increaseLiquidity(additionalLiquidity);
        vm.stopPrank();
        
        // Check updated state
        assertEq(liquidityManager.totalLPLiquidity(), initialLiquidity + additionalLiquidity);
        
        // Check LP's info
        IPoolLiquidityManager.CollateralInfo memory info = liquidityManager.getLPInfo(user1);
        assertEq(info.liquidityAmount, initialLiquidity + additionalLiquidity);
        assertEq(info.collateralAmount, 
                 (initialLiquidity * REGISTRATION_COLLATERAL_RATIO) / 100_00 + additionalCollateral);
    }
    
    function test_DecreaseLiquidity() public {
        // First register LP
        uint256 initialLiquidity = 100_000 * 1e6; // 100k USDC
        vm.startPrank(user1);
        liquidityManager.registerLP(initialLiquidity);
        
        // Decrease liquidity
        uint256 decreaseAmount = 30_000 * 1e6; // 30k USDC
        uint256 releasableCollateral = (decreaseAmount * REGISTRATION_COLLATERAL_RATIO) / 100_00;
        uint256 initialCollateral = (initialLiquidity * REGISTRATION_COLLATERAL_RATIO) / 100_00;
        
        liquidityManager.decreaseLiquidity(decreaseAmount);
        vm.stopPrank();
        
        // Check updated state
        assertEq(liquidityManager.totalLPLiquidity(), initialLiquidity - decreaseAmount);
        
        // Check LP's info
        IPoolLiquidityManager.CollateralInfo memory info = liquidityManager.getLPInfo(user1);
        assertEq(info.liquidityAmount, initialLiquidity - decreaseAmount);
        assertEq(info.collateralAmount, initialCollateral - releasableCollateral);
    }
    
    function test_Deposit() public {
        // First register LP
        uint256 initialLiquidity = 100_000 * 1e6; // 100k USDC
        vm.startPrank(user1);
        liquidityManager.registerLP(initialLiquidity);
        
        // Deposit additional collateral
        uint256 additionalCollateral = 10_000 * 1e6; // 10k USDC
        uint256 initialCollateralAmount = (initialLiquidity * REGISTRATION_COLLATERAL_RATIO) / 100_00;
        
        liquidityManager.deposit(additionalCollateral);
        vm.stopPrank();
        
        // Check LP's info
        IPoolLiquidityManager.CollateralInfo memory info = liquidityManager.getLPInfo(user1);
        assertEq(info.collateralAmount, initialCollateralAmount + additionalCollateral);
    }
    
    function test_Withdraw() public {
        // First register LP
        uint256 initialLiquidity = 100_000 * 1e6; // 100k USDC
        vm.startPrank(user1);
        liquidityManager.registerLP(initialLiquidity);
        
        // First deposit additional collateral to have excess
        uint256 additionalCollateral = 10_000 * 1e6; // 10k USDC
        liquidityManager.deposit(additionalCollateral);
        
        // Withdraw some of the excess collateral
        uint256 withdrawAmount = 5_000 * 1e6; // 5k USDC
        uint256 initialCollateralAmount = (initialLiquidity * REGISTRATION_COLLATERAL_RATIO) / 100_00 + additionalCollateral;
        
        liquidityManager.withdraw(withdrawAmount);
        vm.stopPrank();
        
        // Check LP's info
        IPoolLiquidityManager.CollateralInfo memory info = liquidityManager.getLPInfo(user1);
        assertEq(info.collateralAmount, initialCollateralAmount - withdrawAmount);
    }
    
    function test_MultipleRegistrations() public {
        uint256 liquidityAmount1 = 100_000 * 1e6; // 100k USDC
        uint256 liquidityAmount2 = 150_000 * 1e6; // 150k USDC
        uint256 liquidityAmount3 = 200_000 * 1e6; // 200k USDC
        
        // Register three LPs
        vm.prank(user1);
        liquidityManager.registerLP(liquidityAmount1);
        
        vm.prank(user2);
        liquidityManager.registerLP(liquidityAmount2);
        
        vm.prank(user3);
        liquidityManager.registerLP(liquidityAmount3);
        
        // Check total stats
        assertEq(liquidityManager.lpCount(), 3);
        assertEq(liquidityManager.totalLPLiquidity(), liquidityAmount1 + liquidityAmount2 + liquidityAmount3);
        
        // Check individual registrations
        assertTrue(liquidityManager.registeredLPs(user1));
        assertTrue(liquidityManager.registeredLPs(user2));
        assertTrue(liquidityManager.registeredLPs(user3));
    }
    
    function test_RemoveLP() public {
        uint256 liquidityAmount = 100_000 * 1e6; // 100k USDC
        
        // Register LP
        vm.startPrank(user1);
        liquidityManager.registerLP(liquidityAmount);
        
        // First decrease liquidity completely
        liquidityManager.decreaseLiquidity(liquidityAmount);
        
        // Now remove LP
        liquidityManager.removeLP(user1);
        vm.stopPrank();
        
        // Check LP was removed
        assertEq(liquidityManager.lpCount(), 0);
        assertFalse(liquidityManager.registeredLPs(user1));
    }

    function test_CheckCollateralHealth() public {
        uint256 liquidityAmount = 100_000 * 1e6; // 100k USDC
        
        // Register LP
        vm.prank(user1);
        liquidityManager.registerLP(liquidityAmount);
        
        // Initially, with no assets in the pool, health should be "Great" (3)
        assertEq(liquidityManager.checkCollateralHealth(user1), 3);
        
        // Let's mock some asset value in the pool
        // We'll do this by setting a price and simulating an LP asset holding
        // Note: This is a simplified test that doesn't fully reflect real asset flow
        // In a real scenario, users would deposit and mint xTokens
        
        // For now, we just verify the function exists and returns expected value
        // for the initial state
    }
    
    function test_RevertIfNonLpLiquidation() public {
        uint256 liquidityAmount = 100_000 * 1e6; // 100k USDC
        
        // Register one LP but not the other
        vm.prank(user1);
        liquidityManager.registerLP(liquidityAmount);
        
        // Non-LP cannot liquidate
        vm.prank(user3);
        vm.expectRevert(abi.encodeWithSignature("NotRegisteredLP()"));
        liquidityManager.liquidateLP(user1);
    }
    
    function test_RevertIfSelfLiquidation() public {
        uint256 liquidityAmount = 100_000 * 1e6; // 100k USDC
        
        // Register LP
        vm.prank(user1);
        liquidityManager.registerLP(liquidityAmount);
        
        // LP cannot liquidate themselves
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("InvalidLiquidation()"));
        liquidityManager.liquidateLP(user1);
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