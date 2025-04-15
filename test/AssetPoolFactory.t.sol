// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/protocol/AssetPoolFactory.sol";
import "../src/protocol/AssetPool.sol";
import "../src/protocol/PoolCycleManager.sol";
import "../src/protocol/PoolLiquidityManager.sol";
import "../src/protocol/ProtocolRegistry.sol";
import "../src/protocol/AssetOracle.sol";
import "../src/protocol/strategies/DefaultPoolStrategy.sol";
import "../test/mocks/MockERC20.sol";

contract AssetPoolFactoryTest is Test {
    AssetPoolFactory public factory;
    AssetPool public assetPoolImpl;
    PoolCycleManager public cycleManagerImpl;
    PoolLiquidityManager public liquidityManagerImpl;
    ProtocolRegistry public registry;
    
    // Mock contracts for testing
    MockERC20 public usdc;
    AssetOracle public oracle;
    
    // strategy contract
    IPoolStrategy public strategy;
    
    // Chainlink router (mocked)
    address public chainlinkRouter;
    
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
        chainlinkRouter = makeAddr("chainlinkRouter");
        
        // Deploy implementation contracts
        assetPoolImpl = new AssetPool();
        cycleManagerImpl = new PoolCycleManager();
        liquidityManagerImpl = new PoolLiquidityManager();
        
        // Deploy registry
        registry = new ProtocolRegistry();
        
        // Deploy mock contracts
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // deploy oracle
        oracle = new AssetOracle(
            chainlinkRouter,
            "TSLA",
            DEFAULT_SOURCE_HASH,
            owner
        );
        strategy = new DefaultPoolStrategy();
        
        // Deploy factory
        factory = new AssetPoolFactory(
            address(assetPoolImpl),
            address(cycleManagerImpl),
            address(liquidityManagerImpl),
            address(registry)
        );
        
        // Verify strategy in registry
        registry.setStrategyVerification(address(strategy), true);
    }
    
    // Existing tests remain the same, but modified where needed
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
    
    // New test for createOracle function
    function test_CreateOracle() public {
        
        // Create oracle
        address oracleAddress = factory.createOracle(
            ASSET_SYMBOL,
            DEFAULT_SOURCE_HASH,
            chainlinkRouter
        );
        
        // Verify oracle was created (non-zero address)
        assertTrue(oracleAddress != address(0), "Oracle address should not be zero");
        
        // Verify oracle properties
        assertEq(AssetOracle(oracleAddress).assetSymbol(), ASSET_SYMBOL, "Asset symbol not set correctly");
        assertEq(AssetOracle(oracleAddress).sourceHash(), DEFAULT_SOURCE_HASH, "Source hash not set correctly");
        assertEq(AssetOracle(oracleAddress).owner(), owner, "Oracle owner not set correctly");
    }
    
    function test_RevertWhen_CreateOracleWithEmptySymbol() public {
        // Expect revert when asset symbol is empty
        vm.expectRevert(IAssetPoolFactory.InvalidParams.selector);
        factory.createOracle(
            "",
            DEFAULT_SOURCE_HASH,
            chainlinkRouter
        );
    }
    
    function test_RevertWhen_CreateOracleWithZeroRouterAddress() public {
        // Expect revert when router address is zero
        vm.expectRevert(IAssetPoolFactory.InvalidParams.selector);
        factory.createOracle(
            ASSET_SYMBOL,
            DEFAULT_SOURCE_HASH,
            address(0)
        );
    }
    
    function test_CreateMultipleOracles() public {
        // Create multiple oracles with different symbols
        address oracle1 = factory.createOracle(
            "TSLA",
            DEFAULT_SOURCE_HASH,
            chainlinkRouter
        );
        
        address oracle2 = factory.createOracle(
            "AAPL", 
            DEFAULT_SOURCE_HASH,
            chainlinkRouter
        );
        
        // Verify oracles have unique addresses
        assertTrue(oracle1 != oracle2, "Oracles should have different addresses");
        
        // Verify oracle symbols
        assertEq(AssetOracle(oracle1).assetSymbol(), "TSLA", "Oracle1 symbol not set correctly");
        assertEq(AssetOracle(oracle2).assetSymbol(), "AAPL", "Oracle2 symbol not set correctly");
    }
    
    function test_OracleOwnerIsDifferentFromFactory() public {
        // Create oracle
        address oracleAddress = factory.createOracle(
            ASSET_SYMBOL,
            DEFAULT_SOURCE_HASH,
            chainlinkRouter
        );
        
        // Verify the oracle's owner is the same as the factory's owner (not the factory itself)
        assertEq(AssetOracle(oracleAddress).owner(), factory.owner(), "Oracle owner should be factory owner");
        assertTrue(AssetOracle(oracleAddress).owner() != address(factory), "Oracle owner should not be factory address");
    }
    
    // Modified test for createPool to use factory-created oracle
    function test_CreatePool() public {
        // Create oracle using factory
        address oracleAddress = factory.createOracle(
            ASSET_SYMBOL,
            DEFAULT_SOURCE_HASH,
            chainlinkRouter
        );
        
        // Create a new pool
        address poolAddress = factory.createPool(
            address(usdc),
            ASSET_SYMBOL,
            oracleAddress,
            address(strategy)
        );
        
        // Verify pool was created (non-zero address)
        assertTrue(poolAddress != address(0), "Pool address should not be zero");
        
        // Get pool instance
        AssetPool pool = AssetPool(payable(poolAddress));
        
        // Verify pool was initialized correctly
        assertEq(address(pool.reserveToken()), address(usdc), "Reserve token not set correctly");
        assertEq(pool.assetToken().symbol(), ASSET_SYMBOL, "Asset symbol not set correctly");
        assertEq(address(pool.assetOracle()), oracleAddress, "Oracle not set correctly");
        assertEq(address(pool.poolStrategy()), address(strategy), "Strategy not set correctly");
        
        // Verify associated contracts were deployed
        address cycleManagerAddress = address(pool.poolCycleManager());
        address liquidityManagerAddress = address(pool.poolLiquidityManager());
        
        assertTrue(cycleManagerAddress != address(0), "CycleManager address should not be zero");
        assertTrue(liquidityManagerAddress != address(0), "LiquidityManager address should not be zero");
    }
    
    // New test: Create pool with oracle not created by factory
    function test_RevertWhen_CreatePoolWithUnverifiedOracle() public {
        // Create a new oracle directly (not through factory)
        AssetOracle unverifiedOracle = new AssetOracle(
            chainlinkRouter,
            ASSET_SYMBOL,
            DEFAULT_SOURCE_HASH,
            user // Different owner than factory owner
        );
        
        // Attempt to create pool with unverified oracle (should fail)
        vm.expectRevert(IAssetPoolFactory.NotVerified.selector);
        factory.createPool(
            address(usdc),
            ASSET_SYMBOL,
            address(unverifiedOracle),
            address(strategy)
        );
    }
        
    // Additional tests for existing functionality using factory-created oracles
    function test_CreateMultiplePools() public {
        // Create oracles using factory
        address oracle1 = factory.createOracle("TSLA", DEFAULT_SOURCE_HASH, chainlinkRouter);
        address oracle2 = factory.createOracle("AAPL", DEFAULT_SOURCE_HASH, chainlinkRouter);
        address oracle3 = factory.createOracle("MSFT", DEFAULT_SOURCE_HASH, chainlinkRouter);
        
        // Create three pools with different symbols
        address pool1 = factory.createPool(
            address(usdc),
            "xTSLA",
            oracle1,
            address(strategy)
        );
        
        address pool2 = factory.createPool(
            address(usdc),
            "xAAPL",
            oracle2,
            address(strategy)
        );
        
        address pool3 = factory.createPool(
            address(usdc),
            "xMSFT",
            oracle3,
            address(strategy)
        );
        
        // Verify pools have unique addresses
        assertTrue(pool1 != pool2, "Pool1 and Pool2 should have different addresses");
        assertTrue(pool1 != pool3, "Pool1 and Pool3 should have different addresses");
        assertTrue(pool2 != pool3, "Pool2 and Pool3 should have different addresses");
        
        // Verify pool symbols are set correctly
        assertEq(AssetPool(payable(pool1)).assetToken().symbol(), "xTSLA", "Pool1 symbol not set correctly");
        assertEq(AssetPool(payable(pool2)).assetToken().symbol(), "xAAPL", "Pool2 symbol not set correctly");
        assertEq(AssetPool(payable(pool3)).assetToken().symbol(), "xMSFT", "Pool3 symbol not set correctly");
    }
    
    function test_PoolsShareImplementations() public {
        // Create oracles using factory
        address oracle1 = factory.createOracle("TSLA", DEFAULT_SOURCE_HASH, chainlinkRouter);
        address oracle2 = factory.createOracle("AAPL", DEFAULT_SOURCE_HASH, chainlinkRouter);
        
        // Create two pools
        address pool1 = factory.createPool(
            address(usdc),
            "xTSLA",
            oracle1,
            address(strategy)
        );
        
        address pool2 = factory.createPool(
            address(usdc),
            "xAAPL",
            oracle2,
            address(strategy)
        );
        
        // Verify implementation contracts are different from the pools
        assertTrue(pool1 != address(assetPoolImpl), "Pool1 should be different from implementation");
        assertTrue(pool2 != address(assetPoolImpl), "Pool2 should be different from implementation");
        
        // Get pool cycle managers and verify they are different from the implementation
        address cycleManager1 = address(AssetPool(payable(pool1)).poolCycleManager());
        address cycleManager2 = address(AssetPool(payable(pool2)).poolCycleManager());
        
        assertTrue(cycleManager1 != address(cycleManagerImpl), "CycleManager1 should be different from implementation");
        assertTrue(cycleManager2 != address(cycleManagerImpl), "CycleManager2 should be different from implementation");
        assertTrue(cycleManager1 != cycleManager2, "CycleManagers should be different from each other");
    }
    
    function test_CreatePoolWithNewlyVerifiedStrategy() public {
        // Create oracle using factory
        address oracleAddress = factory.createOracle(ASSET_SYMBOL, DEFAULT_SOURCE_HASH, chainlinkRouter);
        
        // Deploy a new strategy that is initially unverified
        IPoolStrategy newStrategy = new DefaultPoolStrategy();
        
        // Attempt to create a pool with unverified strategy (should fail)
        vm.expectRevert(IAssetPoolFactory.NotVerified.selector);
        factory.createPool(
            address(usdc),
            "xNVDA",
            oracleAddress,
            address(newStrategy)
        );
        
        // Verify the strategy in the registry
        registry.setStrategyVerification(address(newStrategy), true);
        
        // Now create a pool with the newly verified strategy (should succeed)
        address poolAddress = factory.createPool(
            address(usdc),
            "xNVDA",
            oracleAddress,
            address(newStrategy)
        );
        
        // Verify pool was created successfully
        assertTrue(poolAddress != address(0), "Pool address should not be zero");
        
        // Verify strategy was set correctly
        AssetPool pool = AssetPool(payable(poolAddress));
        assertEq(address(pool.poolStrategy()), address(newStrategy), "Strategy not set correctly");
    }

    function test_CreatePoolAfterStrategyVerificationRemoved() public {
        // Create oracle using factory
        address oracleAddress = factory.createOracle(ASSET_SYMBOL, DEFAULT_SOURCE_HASH, chainlinkRouter);
        
        // Create a pool with verified strategy
        address poolAddress = factory.createPool(
            address(usdc),
            "xAMZN",
            oracleAddress,
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
            oracleAddress,
            address(strategy)
        );
        
        // Re-verify the strategy
        registry.setStrategyVerification(address(strategy), true);
        
        // Now create another pool (should succeed)
        address poolAddress2 = factory.createPool(
            address(usdc),
            "xAMZN2",
            oracleAddress,
            address(strategy)
        );
        
        // Verify second pool was created successfully
        assertTrue(poolAddress2 != address(0), "Second pool address should not be zero");
    }
    
    // Test oracle ownership transfer when factory owner changes
    function test_OracleOwnershipWithFactoryOwnerChange() public {
        // Create oracle using factory
        address oracleAddress = factory.createOracle(ASSET_SYMBOL, DEFAULT_SOURCE_HASH, chainlinkRouter);
        
        // Verify initial ownership
        assertEq(AssetOracle(oracleAddress).owner(), owner, "Oracle initial owner should be factory owner");
        
        // Transfer factory ownership to user
        factory.transferOwnership(user);
        
        // Oracle ownership should remain unchanged
        assertEq(AssetOracle(oracleAddress).owner(), owner, "Oracle ownership should not change when factory ownership changes");
        
        // New oracles should be created with new owner
        vm.prank(user);
        address newOracleAddress = factory.createOracle("NVDA", DEFAULT_SOURCE_HASH, chainlinkRouter);
        
        // Verify new oracle ownership
        assertEq(AssetOracle(newOracleAddress).owner(), user, "New oracle owner should be new factory owner");
    }
}