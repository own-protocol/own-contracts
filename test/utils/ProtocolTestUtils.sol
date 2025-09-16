// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "openzeppelin-contracts/contracts/proxy/Clones.sol";

import "../../src/protocol/AssetPool.sol";
import "../../src/protocol/PoolCycleManager.sol";
import "../../src/protocol/PoolLiquidityManager.sol";
import "../../src/protocol/strategies/DefaultPoolStrategy.sol";
import "../../src/protocol/xToken.sol";
import "../../src/protocol/AssetOracle.sol";
import "../mocks/MockAssetOracle.sol";
import "../mocks/MockERC20.sol";

/**
 * @title ProtocolTestUtils
 * @notice Comprehensive testing framework with reusable utility functions for protocol testing
 */
contract ProtocolTestUtils is Test {
    // Protocol contracts
    AssetPool public assetPool;
    PoolCycleManager public cycleManager;
    PoolLiquidityManager public liquidityManager;
    xToken public assetToken;
    IPoolStrategy public poolStrategy;
    MockAssetOracle public assetOracle;
    
    // Mock contracts
    MockERC20 public reserveToken;
    
    // Test accounts
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    address public liquidityProvider1;
    address public liquidityProvider2;
    
    // Test constants
    uint256 public constant REBALANCE_LENGTH = 1 days;
    bytes32 public constant DEFAULT_SOURCE_HASH = keccak256(abi.encodePacked("console.log(JSON.stringify({price: 42069000000000000000000}));"));
    string public constant DEFAULT_SOURCE_CODE = "console.log(JSON.stringify({price: 42069000000000000000000}));";
    uint64 public constant SUBSCRIPTION_ID = 123;
    uint32 public constant GAS_LIMIT = 300000;
    bytes32 public constant DON_ID = bytes32("don1");
    uint256 public constant BPS = 10000; // 100% in basis points

     // Set default values for tests
    uint256 public constant rebalancePeriod = 1 days;
    uint256 public constant oracleUpdateThreshold = 15 minutes;

    // Set halt parameters
    uint256 public constant haltThreshold = 5 days;
    uint256 public constant haltLiquidityPercent = 7000; // 70%
    uint256 public constant haltFeePercent = 500; // 5%
    uint256 public constant haltRequestThreshold = 20; // 20 cycles
    
    // Set interest rate parameters
    uint256 public constant baseRate = 900; // 9%
    uint256 public constant rate1 = 1800;   // 18%
    uint256 public constant maxRate = 7200; // 72%
    uint256 public constant utilTier1 = 6500; // 65%
    uint256 public constant utilTier2 = 8500; // 85%
    
    // Set fee parameters  
    uint256 public constant protocolFee = 1000; // 10%
    address public constant feeRecipient = address(0x1234567890123456789012345678901234567890);
    
    // Set user collateral parameters
    uint256 public constant userhealthyRatio = 2000; // 20%
    uint256 public constant userLiquidationThreshold = 1250;  // 12.5%
    
    // Set LP parameters
    uint256 public constant lpHealthyRatio = 3000;  // 30%
    uint256 public constant lpLiquidationThreshold = 2000;   // 20%
    uint256 public constant lpLiquidationReward = 50;        // 0.5%
    uint256 public constant lpMinCommitment = 0; // 0, no minimum commitment

    // Event records for testing
    struct EventRecord {
        address user;
        uint256 amount;
        uint256 cycleIndex;
        bool emitted;
    }
    
    mapping(bytes32 => EventRecord) public eventRecords;
    
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
        
        // Deploy oracle
        assetOracle = new MockAssetOracle(
            _assetOracleSymbol,
            DEFAULT_SOURCE_HASH
        );
        
        // Deploy strategy
        poolStrategy = new DefaultPoolStrategy();

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
            address(assetPool),
            address(cycleManager),
            address(liquidityManager),
            address(poolStrategy)
        );
        
        // Get asset token address created by AssetPool
        address assetTokenAddress = address(assetPool.assetToken());
        assetToken = xToken(assetTokenAddress);
        
        // Initialize CycleManager
        cycleManager.initialize(
            address(reserveToken),
            assetTokenAddress,
            address(assetOracle),
            address(assetPool),
            address(cycleManager),
            address(liquidityManager),
            address(poolStrategy),
            owner
        );
        
        // Initialize LiquidityManager
        liquidityManager.initialize(
            address(reserveToken),
            assetTokenAddress,
            address(assetOracle),
            address(assetPool),
            address(cycleManager),
            address(liquidityManager),
            address(poolStrategy)
        );


        poolStrategy.setCycleParams(rebalancePeriod, oracleUpdateThreshold);
        poolStrategy.setInterestRateParams(baseRate, rate1, maxRate, utilTier1, utilTier2);
        poolStrategy.setLPLiquidityParams(lpHealthyRatio, lpLiquidationThreshold, lpLiquidationReward, lpMinCommitment);
        poolStrategy.setProtocolFeeParams(protocolFee, feeRecipient);
        poolStrategy.setUserCollateralParams(userhealthyRatio, userLiquidationThreshold);
        poolStrategy.setHaltParams(haltThreshold, haltLiquidityPercent, haltFeePercent, haltRequestThreshold);
    }
    
    /**
     * @notice Funds test accounts with reserve tokens and approves spending
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
        reserveToken.approve(address(cycleManager), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(liquidityProvider2);
        reserveToken.approve(address(liquidityManager), type(uint256).max);
        reserveToken.approve(address(cycleManager), type(uint256).max);
        vm.stopPrank();
    }
    
    /**
     * @notice Sets up liquidity providers by registering them and completing a full rebalance cycle
     * @param _liquidityAmount Amount of liquidity for each LP to provide
     * @param _initialPrice Initial price for the rebalance
     */
    function setupLiquidityProviders(uint256 _liquidityAmount, uint256 _initialPrice) public {
        // First add liquidity to the pool
        vm.startPrank(liquidityProvider1);
        liquidityManager.addLiquidity(_liquidityAmount / 2);
        vm.stopPrank();
        
        vm.startPrank(liquidityProvider2);
        liquidityManager.addLiquidity(_liquidityAmount / 2);
        vm.stopPrank();
        
        // Complete initial setup to activate the pool
        vm.startPrank(owner);
        // Market should be open for offchain rebalance
        assetOracle.setMarketOpen(true);
        updateOraclePrice(_initialPrice);
        cycleManager.initiateOffchainRebalance();
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        
        // Market should be closed for onchain rebalance
        assetOracle.setMarketOpen(false);
        updateOraclePrice(_initialPrice);
        cycleManager.initiateOnchainRebalance();
        vm.stopPrank();
        
        // LPs rebalance their positions
        vm.startPrank(liquidityProvider1);
        (uint256 rebalanceAmount, bool isDeposit) = cycleManager.calculateLPRebalanceAmount(liquidityProvider1, _initialPrice);
        cycleManager.rebalancePool(liquidityProvider1, _initialPrice);
        vm.stopPrank();
        
        vm.startPrank(liquidityProvider2);
        (rebalanceAmount, isDeposit) = cycleManager.calculateLPRebalanceAmount(liquidityProvider2, _initialPrice);
        cycleManager.rebalancePool(liquidityProvider2, _initialPrice);
        vm.stopPrank();
        
        // Set market back to open for normal operations
        vm.startPrank(owner);
        assetOracle.setMarketOpen(true);
        vm.stopPrank();
        
        // Add more liquidity in the active state
        vm.startPrank(liquidityProvider1);
        liquidityManager.addLiquidity(_liquidityAmount / 2);
        vm.stopPrank();
        
        vm.startPrank(liquidityProvider2);
        liquidityManager.addLiquidity(_liquidityAmount / 2);
        vm.stopPrank();
        
        // Complete another cycle to process the additional liquidity
        vm.startPrank(owner);
        // Market should be open for offchain rebalance
        assetOracle.setMarketOpen(true);
        updateOraclePrice(_initialPrice);
        cycleManager.initiateOffchainRebalance();
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        
        // Market should be closed for onchain rebalance
        assetOracle.setMarketOpen(false);
        updateOraclePrice(_initialPrice);
        cycleManager.initiateOnchainRebalance();
        vm.stopPrank();
        
        // LPs rebalance again
        vm.startPrank(liquidityProvider1);
        (rebalanceAmount, isDeposit) = cycleManager.calculateLPRebalanceAmount(liquidityProvider1, _initialPrice);
        cycleManager.rebalancePool(liquidityProvider1, _initialPrice);
        vm.stopPrank();
        
        vm.startPrank(liquidityProvider2);
        (rebalanceAmount, isDeposit) = cycleManager.calculateLPRebalanceAmount(liquidityProvider2, _initialPrice);
        cycleManager.rebalancePool(liquidityProvider2, _initialPrice);
        vm.stopPrank();
        
        // Set market back to open for normal operations
        vm.startPrank(owner);
        assetOracle.setMarketOpen(true);
        vm.stopPrank();
        
        // Verify LP commitment is properly set
        IPoolLiquidityManager.LPPosition memory position1 = liquidityManager.getLPPosition(liquidityProvider1);
        require(position1.liquidityCommitment > 0, "LP1 should have non-zero liquidity commitment");
        
        IPoolLiquidityManager.LPPosition memory position2 = liquidityManager.getLPPosition(liquidityProvider2);
        require(position2.liquidityCommitment > 0, "LP2 should have non-zero liquidity commitment");
    }
    
    /**
     * @notice Simulates an oracle price update with full OHLC data
     * @param _price New price to set (in 18 decimals, used as close price)
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
        
        // Set OHLC data with some reasonable variation
        // Open: 99% of close
        // High: 103% of close
        // Low: 97% of close
        // Close: provided price
        uint256 openPrice = (_price * 99) / 100;
        uint256 highPrice = (_price * 103) / 100;
        uint256 lowPrice = (_price * 97) / 100;
        uint256 closePrice = _price;
        uint256 timestamp = block.timestamp;
        
        // Encode the OHLC data as the response
        bytes memory response = abi.encode(openPrice, highPrice, lowPrice, closePrice, timestamp);
        bytes memory error = "";
        
        // Fulfill the request
        assetOracle.mockFulfillRequest(
            requestId,
            response,
            error
        );
    }

    /**
     * @notice Simulates an oracle price update with custom OHLC data
     * @param _open Open price
     * @param _high High price
     * @param _low Low price
     * @param _close Close price
     */
    function updateOraclePriceWithOHLC(
        uint256 _open,
        uint256 _high,
        uint256 _low,
        uint256 _close
    ) public {
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
        
        // Encode the OHLC data as the response
        bytes memory response = abi.encode(_open, _high, _low, _close, block.timestamp);
        bytes memory error = "";
        
        // Fulfill the request
        assetOracle.mockFulfillRequest(
            requestId,
            response,
            error
        );
    }
    
    /**
     * @notice Helper function to simulate a protocol cycle with deposits and redemptions
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
        if (_depositAmount > 0) {
            vm.prank(user1);
            assetPool.depositRequest(_depositAmount, _depositAmount * 20 / 100); // 20% collateral
            
            vm.prank(user2);
            assetPool.depositRequest(_depositAmount, _depositAmount * 20 / 100);
        }
        
        // Process redemption requests (if there are any assets to redeem)
        if (assetToken.balanceOf(user3) >= _redemptionAmount && _redemptionAmount > 0) {
            vm.startPrank(user3);
            assetToken.approve(address(assetPool), type(uint256).max);
            assetPool.redemptionRequest(_redemptionAmount);
            vm.stopPrank();
        }
        
        // Start offchain rebalance
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
        if (_depositAmount > 0) {
            vm.prank(user1);
            assetPool.claimAsset(user1);
            
            vm.prank(user2);
            assetPool.claimAsset(user2);
        }
        
        if (assetToken.balanceOf(user3) >= _redemptionAmount && _redemptionAmount > 0) {
            vm.prank(user3);
            assetPool.claimReserve(user3);
        }
    }
    
    /**
     * @notice Advances time and simulates a new cycle without requests
     */
    function advanceCycle() public {
        
        // Start offchain rebalance
        vm.prank(liquidityProvider1);
        cycleManager.initiateOffchainRebalance();
        
        // Advance time to simulate offchain rebalance period
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        
        // Update oracle price
        updateOraclePrice(assetOracle.assetPrice());
        
        // Start onchain rebalance
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
    
    /**
     * @notice Helper function to adjust amount based on decimals
     * @param _amount Base amount (in standard units)
     * @param _decimals Target decimals precision
     * @return Adjusted amount with proper decimal precision
     */
    function adjustAmountForDecimals(uint256 _amount, uint8 _decimals) public pure returns (uint256) {
        if (_decimals == 18) {
            return _amount * 1e18;
        } else if (_decimals == 6) {
            return _amount * 1e6;
        } else {
            return _amount * (10 ** _decimals);
        }
    }

    /**
     * @notice Sets up protocol with all necessary components for testing
     * @param _assetSymbol Symbol for the asset token
     * @param _reserveDecimals Decimals for the reserve token
     * @param _initialPrice Initial price for the asset (in 18 decimals)
     * @param _userBaseAmount User amount in standard unit (will be adjusted for decimals)
     * @param _lpBaseAmount LP amount in standard unit (will be adjusted for decimals)
     * @param _lpLiquidityBaseAmount LP liquidity in standard unit (will be adjusted for decimals)
     * @return True if setup completed successfully
     */
    function setupProtocol(
        string memory _assetSymbol,
        uint8 _reserveDecimals,
        uint256 _initialPrice,
        uint256 _userBaseAmount,
        uint256 _lpBaseAmount,
        uint256 _lpLiquidityBaseAmount
    ) public returns (bool) {
        // Adjust amounts based on reserve token decimals
        uint256 userAmount = adjustAmountForDecimals(_userBaseAmount, _reserveDecimals);
        uint256 lpAmount = adjustAmountForDecimals(_lpBaseAmount, _reserveDecimals);
        uint256 lpLiquidity = adjustAmountForDecimals(_lpLiquidityBaseAmount, _reserveDecimals);
        
        // Deploy protocol
        deployProtocol(_assetSymbol, _assetSymbol, _reserveDecimals);
        
        // Fund accounts
        fundAccounts(userAmount, lpAmount);
        
        // Set initial asset price
        updateOraclePrice(_initialPrice);
        
        // Setup liquidity providers with initial price
        setupLiquidityProviders(lpLiquidity, _initialPrice);
        
        // Verify pool is active and setup was successful
        bool isActive = (cycleManager.cycleState() == IPoolCycleManager.CycleState.POOL_ACTIVE);
        
        // Verify LP positions are properly set up
        IPoolLiquidityManager.LPPosition memory position = liquidityManager.getLPPosition(liquidityProvider1);
        bool hasLiquidity = position.liquidityCommitment > 0;
        
        return isActive && hasLiquidity;
    }
    
    /**
     * @notice Performs a deposit request and verifies it was successful
     * @param _user User address
     * @param _amount Amount to deposit
     * @param _collateralAmount Collateral amount
     * @return True if successful
     */
    function performDeposit(
        address _user,
        uint256 _amount,
        uint256 _collateralAmount
    ) public returns (bool) {
        uint256 initialBalance = reserveToken.balanceOf(_user);
        
        vm.startPrank(_user);
        assetPool.depositRequest(_amount, _collateralAmount);
        vm.stopPrank();
        
        // Verify request state
         (IAssetPool.RequestType reqType, uint256 reqAmount, uint256 reqCollateral, uint256 reqCycle) = assetPool.userRequests(_user);
        
        return (
            reqType == IAssetPool.RequestType.DEPOSIT &&
            reqAmount == _amount &&
            reqCollateral == _collateralAmount &&
            reqCycle == cycleManager.cycleIndex() &&
            reserveToken.balanceOf(_user) == initialBalance - _amount - _collateralAmount
        );
    }
    
    /**
     * @notice Performs a redemption request and verifies it was successful
     * @param _user User address
     * @param _amount Amount to redeem
     * @return True if successful
     */
    function performRedemption(
        address _user,
        uint256 _amount
    ) public returns (bool) {
        uint256 initialBalance = assetToken.balanceOf(_user);
        
        vm.startPrank(_user);
        assetToken.approve(address(assetPool), _amount);
        assetPool.redemptionRequest(_amount);
        vm.stopPrank();
        
        // Verify request state
        (IAssetPool.RequestType reqType, uint256 reqAmount, , uint256 reqCycle) = assetPool.userRequests(_user);
        
        return (
            reqType == IAssetPool.RequestType.REDEEM &&
            reqAmount == _amount &&
            reqCycle == cycleManager.cycleIndex() &&
            assetToken.balanceOf(_user) == initialBalance - _amount
        );
    }
    

    /**
     * @notice Get expected asset token amount for a deposit
     * @param _depositAmount Amount of reserve tokens deposited
     * @param _price Asset price
     * @return Expected asset token amount
     */
    function getExpectedAssetAmount(
        uint256 _depositAmount,
        uint256 _price
    ) public view returns (uint256) {
        uint256 decimalFactor = assetPool.reserveToAssetDecimalFactor();
        return (_depositAmount * 1e18 * decimalFactor) / _price;
    }
    
    /**
     * @notice Get expected reserve amount for a redemption
     * @param _assetAmount Amount of asset tokens to redeem
     * @param _price Asset price
     * @return Expected reserve token amount
     */
    function getExpectedReserveAmount(
        uint256 _assetAmount,
        uint256 _price
    ) public view returns (uint256) {
        uint256 decimalFactor = assetPool.reserveToAssetDecimalFactor();
        return (_assetAmount * _price) / (1e18 * decimalFactor);
    }
    
    /**
     * @notice Helper to determine if a user can be liquidated
     * @param _user Address of the user to check
     * @return True if the user is liquidatable
     */
    function isUserLiquidatable(address _user) public view returns (bool) {
        uint8 collateralHealth = poolStrategy.getUserCollateralHealth(address(assetPool), _user);
        return collateralHealth == 1;
    }
    
    /**
     * @notice Execute a complete protocol cycle with price change
     * @param _newPrice New price to set for the next cycle
     */
    function completeCycleWithPriceChange(uint256 _newPrice) public {
        // Verify LPs have non-zero liquidity commitment 
        IPoolLiquidityManager.LPPosition memory position = liquidityManager.getLPPosition(liquidityProvider1);
        require(position.liquidityCommitment > 0, "LP1 should have non-zero liquidity commitment");
        
        // OFFCHAIN REBALANCE PHASE
        // Set market open and start offchain rebalance
        vm.startPrank(owner);
        assetOracle.setMarketOpen(true);
        // Update oracle price to the new price
        updateOraclePrice(_newPrice);
        cycleManager.initiateOffchainRebalance();
        vm.stopPrank();
        
        // Advance time to after rebalance period
        vm.warp(block.timestamp + REBALANCE_LENGTH);
        
        // Update oracle price to the new price
        updateOraclePrice(_newPrice);
        
        // ONCHAIN REBALANCE PHASE
        // Close market and start onchain rebalance
        vm.startPrank(owner);
        assetOracle.setMarketOpen(false);
        cycleManager.initiateOnchainRebalance();
        vm.stopPrank();
        
        // LPs perform rebalancing
        vm.startPrank(liquidityProvider1);
        (uint256 rebalanceAmount, bool isDeposit) = cycleManager.calculateLPRebalanceAmount(liquidityProvider1, _newPrice);
        cycleManager.rebalancePool(liquidityProvider1, _newPrice);
        vm.stopPrank();
        
        vm.startPrank(liquidityProvider2);
        (rebalanceAmount, isDeposit) = cycleManager.calculateLPRebalanceAmount(liquidityProvider2, _newPrice);
        cycleManager.rebalancePool(liquidityProvider2, _newPrice);
        vm.stopPrank();
    }
}