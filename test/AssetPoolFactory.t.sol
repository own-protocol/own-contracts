// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/protocol/AssetPoolFactory.sol";
import "../src/protocol/AssetPool.sol";
import "../src/protocol/PoolLiquidityManager.sol";
import "../src/protocol/PoolCycleManager.sol";
import "../src/protocol/xToken.sol";
import "../src/protocol/DefaultInterestRateStrategy.sol";
import "../src/protocol/AssetOracle.sol";
import "../src/interfaces/IAssetPool.sol";
import "../src/interfaces/IAssetOracle.sol";
import "../src/interfaces/IInterestRateStrategy.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@chainlink/contracts/v0.8/functions/v1_0_0/FunctionsClient.sol";

contract AssetPoolFactoryTest is Test {
    // Test contracts
    AssetPoolFactory public factory;
    AssetPool public assetPoolImpl;
    PoolCycleManager public poolCycleManagerImpl;
    PoolLiquidityManager public poolLiquidityManagerImpl;
    AssetOracle public assetOracle;
    DefaultInterestRateStrategy public interestRateStrategy;
    IERC20Metadata public reserveToken;
    
    // Chainlink related addresses
    address public constant FUNCTIONS_ROUTER = address(0x123456);

    // Test addresses
    address owner = address(1);

    // Test constants
    uint256 constant CYCLE_LENGTH = 7 days;
    uint256 constant REBALANCE_LENGTH = 1 days;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock USDC
        MockERC20 mockUSDC = new MockERC20("USDC", "USDC", 6);
        reserveToken = IERC20Metadata(address(mockUSDC));

        // Deploy real DefaultInterestRateStrategy with appropriate parameters
        // Parameters: baseRate (6%), maxRate (36%), utilTier1 (50%), utilTier2 (75%), maxUtil (95%)
        interestRateStrategy = new DefaultInterestRateStrategy(
            6_00,  // 6% base rate
            36_00, // 36% max rate
            50_00, // 50% first tier
            75_00, // 75% second tier
            95_00  // 95% max utilization
        );
        
        // For AssetOracle, we need to mock the Chainlink Functions Router
        // Create a source hash for the oracle - this would normally be a hash of the JavaScript source
        bytes32 sourceHash = keccak256(abi.encodePacked("// Sample JavaScript source for testing"));
        
        // Deploy the real AssetOracle with our mock router
        assetOracle = new AssetOracle(
            FUNCTIONS_ROUTER,
            "AAPL",  // Apple stock symbol
            sourceHash
        );
        
        // Since we can't actually call Chainlink Functions in a test, we'll use vm.mockCall later to set prices

        // Deploy implementation contracts
        assetPoolImpl = new AssetPool();
        poolCycleManagerImpl = new PoolCycleManager();
        poolLiquidityManagerImpl = new PoolLiquidityManager();

        // Deploy factory with implementation contracts
        factory = new AssetPoolFactory(
            address(assetPoolImpl), 
            address(poolCycleManagerImpl), 
            address(poolLiquidityManagerImpl)
        );

        // Mock the assetPrice and lastUpdated values since we can't call Chainlink Functions
        // We'll use assembly to directly set the storage variables
        vm.store(
            address(assetOracle),
            bytes32(uint256(4)), // assetPrice is the 5th storage slot (0-indexed)
            bytes32(uint256(1e18)) // Set to 1.0 with 18 decimals
        );
        
        vm.store(
            address(assetOracle),
            bytes32(uint256(5)), // lastUpdated is the 6th storage slot
            bytes32(uint256(block.timestamp))
        );

        vm.stopPrank();
    }

    // --------------------------------------------------------------------------------
    //                              FACTORY TESTS
    // --------------------------------------------------------------------------------

    function testFactoryDeployment() public view {
        assertEq(factory.assetPool(), address(assetPoolImpl));
        assertEq(factory.poolCycleManager(), address(poolCycleManagerImpl));
        assertEq(factory.poolLiquidityManager(), address(poolLiquidityManagerImpl));
    }

    function testCreatePool() public {
        vm.startPrank(owner);
        
        // Mint some USDC to owner for testing
        MockERC20(address(reserveToken)).mint(owner, 1_000_000 * 10**6);
        
        address newPool = factory.createPool(
            address(reserveToken),
            "xAAPL",  // asset symbol
            address(assetOracle),
            address(interestRateStrategy),
            CYCLE_LENGTH,
            REBALANCE_LENGTH
        );
        
        vm.stopPrank();

        assertTrue(newPool != address(0));
        
        // Verify pool was initialized correctly
        AssetPool poolInstance = AssetPool(newPool);
        assertEq(address(poolInstance.getReserveToken()), address(reserveToken));
        assertEq(address(poolInstance.getAssetOracle()), address(assetOracle));
        assertEq(address(poolInstance.interestRateStrategy()), address(interestRateStrategy));
        
        // Get cycle manager address
        address cycleManagerAddr = address(poolInstance.getPoolCycleManager());
        PoolCycleManager cycleManager = PoolCycleManager(cycleManagerAddr);
        
        // Verify cycle manager was initialized correctly
        assertEq(cycleManager.cycleLength(), CYCLE_LENGTH);
        assertEq(cycleManager.rebalanceLength(), REBALANCE_LENGTH);
        
        // Verify liquidity manager was initialized correctly
        address liquidityManagerAddr = address(poolInstance.getPoolLiquidityManager());
        assertTrue(liquidityManagerAddr != address(0));
        
        // Verify interest rate strategy parameters
        IInterestRateStrategy strategy = poolInstance.interestRateStrategy();
        
        // Test interest rates at different utilization levels
        uint256 lowUtilizationRate = strategy.calculateInterestRate(40_00); // 40% utilization
        uint256 midUtilizationRate = strategy.calculateInterestRate(60_00); // 60% utilization
        uint256 highUtilizationRate = strategy.calculateInterestRate(80_00); // 80% utilization
        
        // Verify interest rate calculations match our expected values
        assertEq(lowUtilizationRate, 6_00); // Base rate at 40% utilization
        assertTrue(midUtilizationRate > 6_00 && midUtilizationRate < 36_00); // Between base and max rate
        assertEq(highUtilizationRate, 36_00); // Max rate at 80% utilization
    }

    function testCreatePoolRevertsWithZeroAddress() public {
        vm.startPrank(owner);
        
        // Test with zero deposit token address
        vm.expectRevert(IAssetPoolFactory.InvalidParams.selector);
        factory.createPool(
            address(0),  // Zero address for deposit token
            "xAAPL",
            address(assetOracle),
            address(interestRateStrategy),
            CYCLE_LENGTH,
            REBALANCE_LENGTH
        );
        
        // Test with zero oracle address
        vm.expectRevert(IAssetPoolFactory.InvalidParams.selector);
        factory.createPool(
            address(reserveToken),
            "xAAPL",
            address(0),  // Zero address for oracle
            address(interestRateStrategy),
            CYCLE_LENGTH,
            REBALANCE_LENGTH
        );
        
        vm.stopPrank();
    }
    
    function testCreatePoolRevertsWithInvalidCycleTimes() public {
        vm.startPrank(owner);
        
        // Test with zero cycle length
        vm.expectRevert(IAssetPoolFactory.InvalidParams.selector);
        factory.createPool(
            address(reserveToken),
            "xAAPL",
            address(assetOracle),
            address(interestRateStrategy),
            0,  // Zero cycle length
            REBALANCE_LENGTH
        );
        
        // Test with rebalance length >= cycle length
        vm.expectRevert(IAssetPoolFactory.InvalidParams.selector);
        factory.createPool(
            address(reserveToken),
            "xAAPL",
            address(assetOracle),
            address(interestRateStrategy),
            CYCLE_LENGTH,
            CYCLE_LENGTH  // Rebalance length equal to cycle length
        );
        
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