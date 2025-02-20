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

contract AssetPoolFactoryTest is Test {
    // Test contracts
    AssetPoolFactory public factory;
    AssetPoolImplementation public implementation;
    LPRegistry public lpRegistry;
    MockAssetOracle assetOracle;
    IERC20Metadata public reserveToken;

    // Test addresses
    address owner = address(1);

    // Test constants
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

        vm.stopPrank();
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
            CYCLE_LENGTH,
            REBALANCE_LENGTH
        );
        vm.stopPrank();

        assertTrue(newPool != address(0));
        IAssetPool poolInstance = IAssetPool(newPool);
        assertEq(address(poolInstance.reserveToken()), address(reserveToken));
        assertEq(poolInstance.cycleLength(), CYCLE_LENGTH);
        assertEq(poolInstance.rebalanceLength(), REBALANCE_LENGTH);
    }

    function testCreatePoolReverts() public {
        vm.startPrank(owner);
        vm.expectRevert(IAssetPoolFactory.InvalidParams.selector);
        factory.createPool(
            address(0),
            "Apple Stock Token",
            "xAAPL",
            address(assetOracle),
            CYCLE_LENGTH,
            REBALANCE_LENGTH
        );
        vm.stopPrank();
    }

    function testUpdateLPRegistry() public {
        address newRegistry = address(new LPRegistry());
        
        vm.prank(owner);
        factory.updateLPRegistry(newRegistry);
        
        assertEq(address(factory.lpRegistry()), newRegistry);
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