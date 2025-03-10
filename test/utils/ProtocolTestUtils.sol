// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "openzeppelin-contracts/contracts/proxy/Clones.sol";

import "../../src/protocol/AssetPool.sol";
import "../../src/protocol/PoolCycleManager.sol";
import "../../src/protocol/PoolLiquidityManager.sol";
import "../../src/protocol/xToken.sol";
import "../../src/protocol/DefaultInterestRateStrategy.sol";
import "../../src/protocol/AssetOracle.sol";
import "../mocks/MockFunctionsRouter.sol";
import "../mocks/MockAssetOracle.sol";

/**
 * @title ProtocolTestUtils
 * @notice Utility contract for testing the protocol with reusable setup and helper functions
 */
contract ProtocolTestUtils is Test {
    // Protocol contracts
    AssetPool public assetPool;
    PoolCycleManager public cycleManager;
    PoolLiquidityManager public liquidityManager;
    xToken public assetToken;
    DefaultInterestRateStrategy public interestRateStrategy;
    MockAssetOracle public assetOracle;
    
    // Mock contracts
    MockERC20 public reserveToken;
    MockFunctionsRouter public functionsRouter;
    
    // Test accounts
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    address public liquidityProvider1;
    address public liquidityProvider2;
    
    // Test constants
    uint256 public constant CYCLE_LENGTH = 7 days;
    uint256 public constant REBALANCE_LENGTH = 1 days;
    bytes32 public constant DEFAULT_SOURCE_HASH = keccak256(abi.encodePacked("console.log(JSON.stringify({price: 42069000000000000000000}));"));
    string public constant DEFAULT_SOURCE_CODE = "console.log(JSON.stringify({price: 42069000000000000000000}));";
    uint64 public constant SUBSCRIPTION_ID = 123;
    uint32 public constant GAS_LIMIT = 300000;
    bytes32 public constant DON_ID = bytes32("don1");
    
    /**
     * @notice Deploys all mock contracts and protocol contracts
     * @param _assetTokenSymbol Symbol for the asset token
     * @param _assetOracleSymbol Symbol for the asset oracle
     * @param _reserveTokenDecimals Decimals for the reserve token
     */
    function deployProtocol(
        string memory _assetTokenSymbol,
        string memory _assetOracleSymbol,
        uint8 _reserveTokenDecimals
    ) public {
        // Set up test accounts
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        liquidityProvider1 = makeAddr("lp1");
        liquidityProvider2 = makeAddr("lp2");
        
        // Deploy mock contracts
        reserveToken = new MockERC20("USD Coin", "USDC", _reserveTokenDecimals);
        functionsRouter = new MockFunctionsRouter();
        
        // Deploy real interest rate strategy
        interestRateStrategy = new DefaultInterestRateStrategy(
            6_00,  // 6% base rate
            36_00, // 36% max rate
            50_00, // 50% first tier
            75_00, // 75% second tier
            95_00  // 95% max utilization
        );
        
        // Deploy oracle
        assetOracle = new MockAssetOracle(
            _assetOracleSymbol,
            DEFAULT_SOURCE_HASH
        );
        
        // Deploy implementation contracts
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
            _assetTokenSymbol,
            address(assetOracle),
            address(cycleManager),
            address(liquidityManager),
            address(interestRateStrategy),
            owner
        );
        
        // Get asset token address created by AssetPool
        address assetTokenAddress = address(assetPool.getAssetToken());
        assetToken = xToken(assetTokenAddress);
        
        // Initialize CycleManager
        cycleManager.initialize(
            address(reserveToken),
            assetTokenAddress,
            address(assetOracle),
            address(assetPool),
            address(liquidityManager),
            CYCLE_LENGTH,
            REBALANCE_LENGTH
        );
        
        // Initialize LiquidityManager
        liquidityManager.initialize(
            address(reserveToken),
            assetTokenAddress,
            address(assetOracle),
            address(assetPool),
            address(cycleManager),
            owner
        );
    }
    
    /**
     * @notice Funds test accounts with reserve tokens
     * @param _userAmount Amount to fund each user with
     * @param _lpAmount Amount to fund each LP with
     */
    function fundAccounts(uint256 _userAmount, uint256 _lpAmount) public {
        reserveToken.mint(user1, _userAmount);
        reserveToken.mint(user2, _userAmount);
        reserveToken.mint(user3, _userAmount);
        reserveToken.mint(liquidityProvider1, _lpAmount);
        reserveToken.mint(liquidityProvider2, _lpAmount);
        
        // Approve spending for accounts
        vm.startPrank(user1);
        reserveToken.approve(address(assetPool), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        reserveToken.approve(address(assetPool), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user3);
        reserveToken.approve(address(assetPool), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(liquidityProvider1);
        reserveToken.approve(address(liquidityManager), type(uint256).max);
        reserveToken.approve(address(assetPool), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(liquidityProvider2);
        reserveToken.approve(address(liquidityManager), type(uint256).max);
        reserveToken.approve(address(assetPool), type(uint256).max);
        vm.stopPrank();
    }
    
    /**
     * @notice Sets up liquidity providers
     * @param _liquidityAmount Amount of liquidity for each LP to provide
     */
    function setupLiquidityProviders(uint256 _liquidityAmount) public {
        vm.startPrank(liquidityProvider1);
        liquidityManager.registerLP(_liquidityAmount);
        vm.stopPrank();
        
        vm.startPrank(liquidityProvider2);
        liquidityManager.registerLP(_liquidityAmount);
        vm.stopPrank();
    }
    
    /**
     * @notice Simulates an oracle price update
     * @param _price New price to set (in 18 decimals)
     */
    function updateOraclePrice(uint256 _price) public {
        // Request a price update
        vm.startPrank(owner);
        assetOracle.requestAssetPrice(
            DEFAULT_SOURCE_CODE,
            SUBSCRIPTION_ID,
            GAS_LIMIT,
            DON_ID
        );
        bytes32 requestId = assetOracle.s_lastRequestId();
        vm.stopPrank();
        
        // Encode the price as the response
        bytes memory response = abi.encode(_price);
        bytes memory error = "";
        
        // Fulfill the request
        assetOracle.mockFulfillRequest(
            requestId,
            response,
            error
        );
    }
    
    /**
     * @notice Helper function to simulate a full protocol cycle
     * @param _depositAmount Amount each user should deposit
     * @param _redemptionAmount Amount each user should redeem
     * @param _rebalancePrice Price at which LPs should rebalance
     */
    function simulateProtocolCycle(
        uint256 _depositAmount,
        uint256 _redemptionAmount,
        uint256 _rebalancePrice
    ) public {
        // Process deposit requests
        vm.prank(user1);
        assetPool.depositRequest(_depositAmount, _depositAmount / 5); // 20% collateral
        
        vm.prank(user2);
        assetPool.depositRequest(_depositAmount, _depositAmount / 5);
        
        // Process redemption requests (if there are any assets to redeem)
        if (assetToken.balanceOf(user3) >= _redemptionAmount && _redemptionAmount > 0) {
            vm.startPrank(user3);
            assetToken.approve(address(assetPool), type(uint256).max);
            assetPool.redemptionRequest(_redemptionAmount);
            vm.stopPrank();
        }
        
        // Start offchain rebalance
        vm.warp(block.timestamp + CYCLE_LENGTH);
        vm.prank(owner);
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to simulate offchain rebalance period
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        
        // Update oracle price
        updateOraclePrice(_rebalancePrice);
        
        // Start onchain rebalance
        vm.prank(owner);
        cycleManager.initiateOnchainRebalance();
        
        // Perform LP rebalancing
        vm.prank(liquidityProvider1);
        cycleManager.rebalancePool(liquidityProvider1, _rebalancePrice);
        
        vm.prank(liquidityProvider2);
        cycleManager.rebalancePool(liquidityProvider2, _rebalancePrice);
        
        // Claim processed requests
        vm.prank(user1);
        assetPool.claimRequest(user1);
        
        vm.prank(user2);
        assetPool.claimRequest(user2);
        
        if (assetToken.balanceOf(user3) >= _redemptionAmount && _redemptionAmount > 0) {
            vm.prank(user3);
            assetPool.claimRequest(user3);
        }
    }
    
    /**
     * @notice Advances time and simulates a new cycle without requests
     */
    function advanceCycle() public {
        // Advance time to the next cycle
        vm.warp(block.timestamp + CYCLE_LENGTH);
        
        // Start offchain rebalance
        vm.prank(liquidityProvider1);
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to simulate offchain rebalance period
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        
        // Update oracle price
        updateOraclePrice(assetOracle.assetPrice());
        
        // If there are no deposits or redemptions, we can start a new cycle
        if (assetPool.cycleTotalDepositRequests() == 0 && assetPool.cycleTotalRedemptionRequests() == 0) {
            vm.prank(liquidityProvider1);
            cycleManager.startNewCycle();
        } else {
            // Otherwise start onchain rebalance
            vm.prank(liquidityProvider1);
            cycleManager.initiateOnchainRebalance();
            
            // LPs rebalance
            vm.startPrank(liquidityProvider1);
            cycleManager.rebalancePool(liquidityProvider1, assetOracle.assetPrice());
            vm.stopPrank();
            
            vm.startPrank(liquidityProvider2);
            cycleManager.rebalancePool(liquidityProvider2, assetOracle.assetPrice());
            vm.stopPrank();
        }
    }
}

/**
 * @title MockERC20
 * @notice Mock ERC20 token with customizable decimals for testing
 */
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