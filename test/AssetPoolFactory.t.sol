// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/protocol/AssetPoolFactory.sol";
import "../src/protocol/AssetPool.sol";
import "../src/protocol/PoolCycleManager.sol";
import "../src/protocol/PoolLiquidityManager.sol";
import "../src/protocol/ProtocolRegistry.sol";
import "../src/protocol/strategies/DefaultPoolStrategy.sol";
import "../test/mocks/MockERC20.sol";
import "../test/mocks/MockAssetOracle.sol";

contract AssetPoolFactoryTest is Test {
    AssetPoolFactory public factory;
    AssetPool public assetPoolImpl;
    PoolCycleManager public cycleManagerImpl;
    PoolLiquidityManager public liquidityManagerImpl;
    ProtocolRegistry public registry;
    
    // Mock contracts for testing
    MockERC20 public usdc;
    MockAssetOracle public oracle;
    
    // strategy contract
    IPoolStrategy public strategy;
    
    // Test accounts
    address public owner;
    address public user;
    
    // Test constants
    string constant ASSET_SYMBOL = "xTSLA";
    bytes32 constant DEFAULT_SOURCE_HASH = keccak256(abi.encodePacked("test source"));
    
    function setUp() public {
        // Set up test accounts
        owner = address(this);
        user = makeAddr("user");
        
        // Deploy implementation contracts
        assetPoolImpl = new AssetPool();
        cycleManagerImpl = new PoolCycleManager();
        liquidityManagerImpl = new PoolLiquidityManager();
        
        // Deploy registry
        registry = new ProtocolRegistry();
        
        // Deploy mock contracts
        usdc = new MockERC20("USD Coin", "USDC", 6);
        oracle = new MockAssetOracle("TSLA", DEFAULT_SOURCE_HASH);
        strategy = new DefaultPoolStrategy();
        
        // Deploy factory
        factory = new AssetPoolFactory(
            address(assetPoolImpl),
            address(cycleManagerImpl),
            address(liquidityManagerImpl),
            address(registry)
        );
        
        // Verify oracle and strategy in registry
        registry.setOracleVerification(address(oracle), true);
        registry.setStrategyVerification(address(strategy), true);
    }
    
    function test_Initialization() public view {
        // Test factory initialization
        assertEq(factory.assetPool(), address(assetPoolImpl), "AssetPool address mismatch");
        assertEq(factory.poolCycleManager(), address(cycleManagerImpl), "CycleManager address mismatch");
        assertEq(factory.poolLiquidityManager(), address(liquidityManagerImpl), "LiquidityManager address mismatch");
        assertEq(factory.protocolRegistry(), address(registry), "Registry address mismatch");
        assertEq(factory.owner(), owner, "Owner address mismatch");
    }
    
    function test_UpdateRegistry() public {
        // Deploy new registry
        ProtocolRegistry newRegistry = new ProtocolRegistry();
        
        // Update registry
        factory.updateRegistry(address(newRegistry));
        
        // Verify update
        assertEq(factory.protocolRegistry(), address(newRegistry), "Registry update failed");
    }
    
    function test_RevertWhen_UpdateRegistryWithZeroAddress() public {
        // Expect revert when updating registry with zero address
        vm.expectRevert(IAssetPoolFactory.ZeroAddress.selector);
        factory.updateRegistry(address(0));
    }
    
    function test_RevertWhen_UpdateRegistryNotOwner() public {
        // Deploy new registry
        ProtocolRegistry newRegistry = new ProtocolRegistry();
        
        // Expect revert when non-owner updates registry
        vm.prank(user);
        vm.expectRevert();
        factory.updateRegistry(address(newRegistry));
    }
    
    function test_CreatePool() public {
        // Create a new pool
        address poolAddress = factory.createPool(
            address(usdc),
            ASSET_SYMBOL,
            address(oracle),
            address(strategy)
        );
        
        // Verify pool was created (non-zero address)
        assertTrue(poolAddress != address(0), "Pool address should not be zero");
        
        // Get pool instance
        AssetPool pool = AssetPool(payable(poolAddress));
        
        // Verify pool was initialized correctly
        assertEq(address(pool.getReserveToken()), address(usdc), "Reserve token not set correctly");
        assertEq(pool.getAssetToken().symbol(), ASSET_SYMBOL, "Asset symbol not set correctly");
        assertEq(address(pool.getAssetOracle()), address(oracle), "Oracle not set correctly");
        assertEq(address(pool.getPoolStrategy()), address(strategy), "Strategy not set correctly");
        assertEq(pool.owner(), owner, "Pool owner not set correctly");
        
        // Verify associated contracts were deployed
        address cycleManagerAddress = address(pool.getPoolCycleManager());
        address liquidityManagerAddress = address(pool.getPoolLiquidityManager());
        
        assertTrue(cycleManagerAddress != address(0), "CycleManager address should not be zero");
        assertTrue(liquidityManagerAddress != address(0), "LiquidityManager address should not be zero");
    }
    
    function test_RevertWhen_CreatePoolWithZeroAddress() public {
        // Expect revert when deposit token is zero
        vm.expectRevert(IAssetPoolFactory.InvalidParams.selector);
        factory.createPool(
            address(0),
            ASSET_SYMBOL,
            address(oracle),
            address(strategy)
        );
        
        // Expect revert when oracle is zero
        vm.expectRevert(IAssetPoolFactory.InvalidParams.selector);
        factory.createPool(
            address(usdc),
            ASSET_SYMBOL,
            address(0),
            address(strategy)
        );
        
        // Expect revert when strategy is zero
        vm.expectRevert(IAssetPoolFactory.InvalidParams.selector);
        factory.createPool(
            address(usdc),
            ASSET_SYMBOL,
            address(oracle),
            address(0)
        );
    }
    
    function test_RevertWhen_CreatePoolWithEmptySymbol() public {
        // Expect revert when asset symbol is empty
        vm.expectRevert(IAssetPoolFactory.InvalidParams.selector);
        factory.createPool(
            address(usdc),
            "",
            address(oracle),
            address(strategy)
        );
    }
    
    function test_RevertWhen_CreatePoolWithUnverifiedStrategy() public {
        // Deploy unverified strategy
        IPoolStrategy unverifiedStrategy = new DefaultPoolStrategy();
        
        // Expect revert when strategy is not verified
        vm.expectRevert(IAssetPoolFactory.NotVerified.selector);
        factory.createPool(
            address(usdc),
            ASSET_SYMBOL,
            address(oracle),
            address(unverifiedStrategy)
        );
    }
    
    function test_CreateMultiplePools() public {
        // Create three pools with different symbols
        address pool1 = factory.createPool(
            address(usdc),
            "xTSLA",
            address(oracle),
            address(strategy)
        );
        
        address pool2 = factory.createPool(
            address(usdc),
            "xAAPL",
            address(oracle),
            address(strategy)
        );
        
        address pool3 = factory.createPool(
            address(usdc),
            "xMSFT",
            address(oracle),
            address(strategy)
        );
        
        // Verify pools have unique addresses
        assertTrue(pool1 != pool2, "Pool1 and Pool2 should have different addresses");
        assertTrue(pool1 != pool3, "Pool1 and Pool3 should have different addresses");
        assertTrue(pool2 != pool3, "Pool2 and Pool3 should have different addresses");
        
        // Verify pool symbols are set correctly
        assertEq(AssetPool(payable(pool1)).getAssetToken().symbol(), "xTSLA", "Pool1 symbol not set correctly");
        assertEq(AssetPool(payable(pool2)).getAssetToken().symbol(), "xAAPL", "Pool2 symbol not set correctly");
        assertEq(AssetPool(payable(pool3)).getAssetToken().symbol(), "xMSFT", "Pool3 symbol not set correctly");
    }
    
    function test_PoolsShareImplementations() public {
        // Create two pools
        address pool1 = factory.createPool(
            address(usdc),
            "xTSLA",
            address(oracle),
            address(strategy)
        );
        
        address pool2 = factory.createPool(
            address(usdc),
            "xAAPL",
            address(oracle),
            address(strategy)
        );
        
        // Verify implementation contracts are different from the pools
        assertTrue(pool1 != address(assetPoolImpl), "Pool1 should be different from implementation");
        assertTrue(pool2 != address(assetPoolImpl), "Pool2 should be different from implementation");
        
        // Get pool cycle managers and verify they are different from the implementation
        address cycleManager1 = address(AssetPool(payable(pool1)).getPoolCycleManager());
        address cycleManager2 = address(AssetPool(payable(pool2)).getPoolCycleManager());
        
        assertTrue(cycleManager1 != address(cycleManagerImpl), "CycleManager1 should be different from implementation");
        assertTrue(cycleManager2 != address(cycleManagerImpl), "CycleManager2 should be different from implementation");
        assertTrue(cycleManager1 != cycleManager2, "CycleManagers should be different from each other");
    }
    
    function test_CreatePoolWithNewlyVerifiedStrategy() public {
        // Deploy a new strategy that is initially unverified
        IPoolStrategy newStrategy = new DefaultPoolStrategy();
        
        // Attempt to create a pool with unverified strategy (should fail)
        vm.expectRevert(IAssetPoolFactory.NotVerified.selector);
        factory.createPool(
            address(usdc),
            "xNVDA",
            address(oracle),
            address(newStrategy)
        );
        
        // Verify the strategy in the registry
        registry.setStrategyVerification(address(newStrategy), true);
        
        // Now create a pool with the newly verified strategy (should succeed)
        address poolAddress = factory.createPool(
            address(usdc),
            "xNVDA",
            address(oracle),
            address(newStrategy)
        );
        
        // Verify pool was created successfully
        assertTrue(poolAddress != address(0), "Pool address should not be zero");
        
        // Verify strategy was set correctly
        AssetPool pool = AssetPool(payable(poolAddress));
        assertEq(address(pool.getPoolStrategy()), address(newStrategy), "Strategy not set correctly");
    }

    function test_CreatePoolAfterStrategyVerificationRemoved() public {
        // Create a pool with verified strategy
        address poolAddress = factory.createPool(
            address(usdc),
            "xAMZN",
            address(oracle),
            address(strategy)
        );
        
        // Verify pool was created successfully
        assertTrue(poolAddress != address(0), "Pool address should not be zero");
        
        // Remove strategy verification
        registry.setStrategyVerification(address(strategy), false);
        
        // Attempt to create another pool with the now-unverified strategy (should fail)
        vm.expectRevert(IAssetPoolFactory.NotVerified.selector);
        factory.createPool(
            address(usdc),
            "xAMZN2",
            address(oracle),
            address(strategy)
        );
        
        // Re-verify the strategy
        registry.setStrategyVerification(address(strategy), true);
        
        // Now create another pool (should succeed)
        address poolAddress2 = factory.createPool(
            address(usdc),
            "xAMZN2",
            address(oracle),
            address(strategy)
        );
        
        // Verify second pool was created successfully
        assertTrue(poolAddress2 != address(0), "Second pool address should not be zero");
    }
}