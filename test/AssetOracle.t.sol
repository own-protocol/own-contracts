// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./mocks/MockFunctionsClient.sol";

/**
 * @title AssetOracleTest
 * @notice Comprehensive unit tests for the AssetOracle contract
 * @dev Uses MockFunctionsClient to simulate the Chainlink Functions Router
 * @dev This uses a different mock oracle from other tests which is
 * more aligned with the actual Chainlink Functions Router. Its defined in the MockFunctionsClient file.
 */
contract AssetOracleTest is Test {
    // Test constants
    bytes32 constant SOURCE_HASH = bytes32(keccak256(abi.encodePacked("console.log(JSON.stringify({price: 42069000000000000000000}));")));
    string constant ASSET_SYMBOL = "TSLA";
    uint64 constant SUBSCRIPTION_ID = 123;
    uint32 constant GAS_LIMIT = 300000;
    bytes32 constant DON_ID = bytes32("don1");
    uint256 constant PRECISION = 1e18;
    
    // Test accounts
    address owner;
    address user1;
    address user2;
    
    // Contracts
    MockAssetOracle assetOracle;
    MockFunctionsRouter mockRouter;

    // Events to test
    event AssetPriceUpdated(uint256 price, uint256 timestamp);
    event AssetSymbolUpdated(string newAssetSymbol);
    event SourceHashUpdated(bytes32 newSourceHash);
    event OHLCDataUpdated(uint256 open, uint256 high, uint256 low, uint256 close, uint256 timestamp);
    event SplitDetected(uint256 prevPrice, uint256 newPrice, uint256 timestamp);
    event RequestSent(bytes32 indexed id);
    event RequestFulfilled(bytes32 indexed id);

    function setUp() public {
        // Set up accounts
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Deploy mock router
        mockRouter = new MockFunctionsRouter();
        
        // Deploy AssetOracle with mock router
        assetOracle = new MockAssetOracle(
            address(mockRouter),
            ASSET_SYMBOL,
            SOURCE_HASH,
            owner
        );
    }
    
    // ==================== BASIC FUNCTIONALITY TESTS ====================
    
    function testInitialState() public view {
        // Verify initial state
        assertEq(assetOracle.assetSymbol(), ASSET_SYMBOL, "Asset symbol mismatch");
        assertEq(assetOracle.sourceHash(), SOURCE_HASH, "Source hash mismatch");
        assertEq(assetOracle.owner(), owner, "Owner mismatch");
        assertEq(assetOracle.assetPrice(), 0, "Initial price should be 0");
        assertEq(assetOracle.lastUpdated(), 0, "Initial lastUpdated should be 0");
    }
    
    function testUpdateSourceHash() public {
        // Create a new source hash
        bytes32 newSourceHash = bytes32(keccak256(abi.encodePacked("new source code")));
        
        // Update source hash
        assetOracle.updateSourceHash(newSourceHash);
        
        // Verify source hash update
        assertEq(assetOracle.sourceHash(), newSourceHash, "Source hash not updated");
    }
    
    function testUpdateSourceHashUnauthorized() public {
        // Create a new source hash
        bytes32 newSourceHash = bytes32(keccak256(abi.encodePacked("new source code")));
        
        // Try to update source hash from unauthorized account
        vm.prank(user1);
        vm.expectRevert();
        assetOracle.updateSourceHash(newSourceHash);
    }
    
    function testUpdateAssetSymbol() public {
        // Update asset symbol
        string memory newSymbol = "BTC";
        assetOracle.updateAssetSymbol(newSymbol);
        
        // Verify asset symbol update
        assertEq(assetOracle.assetSymbol(), newSymbol, "Asset symbol not updated");
    }
    
    function testUpdateAssetSymbolUnauthorized() public {
        // Try to update asset symbol from unauthorized account
        vm.prank(user1);
        vm.expectRevert();
        assetOracle.updateAssetSymbol("BTC");
    }
    
    // ==================== PRICE REQUEST TESTS ====================
    
    function testRequestAssetPrice() public {
        // Valid source code that matches the source hash
        string memory source = "console.log(JSON.stringify({price: 42069000000000000000000}));";
        
        // Request asset price
        assetOracle.requestAssetPrice(
            source,
            SUBSCRIPTION_ID,
            GAS_LIMIT,
            DON_ID
        );
        
        // Verify request was made
        assertTrue(assetOracle.s_lastRequestId() != bytes32(0), "Request ID not set");
    }
    
    function testRequestAssetPriceInvalidSource() public {
        // Invalid source code that doesn't match the source hash
        string memory invalidSource = "console.log('invalid source');";
        
        // Expect revert when source doesn't match hash
        vm.expectRevert(IAssetOracle.InvalidSource.selector);
        assetOracle.requestAssetPrice(
            invalidSource,
            SUBSCRIPTION_ID,
            GAS_LIMIT,
            DON_ID
        );
    }
        
    // ==================== FULFILLMENT TESTS ====================
    
    function testOracleFulfillment() public {
        // First make a request
        string memory source = "console.log(JSON.stringify({price: 42069000000000000000000}));";
        assetOracle.requestAssetPrice(
            source,
            SUBSCRIPTION_ID,
            GAS_LIMIT,
            DON_ID
        );
        
        bytes32 requestId = assetOracle.s_lastRequestId();
        
        // Create OHLC data for the response
        uint256 openPrice = 100 * 1e18;
        uint256 highPrice = 110 * 1e18;
        uint256 lowPrice = 95 * 1e18;
        uint256 closePrice = 105 * 1e18;
        uint256 timestamp = block.timestamp;
        
        // Encode the response data
        bytes memory response = abi.encode(openPrice, highPrice, lowPrice, closePrice, timestamp);
        
        // Fulfill the request (simulate Chainlink Functions callback)
        vm.prank(address(mockRouter));
        mockRouter.fulfillRequest(
            address(assetOracle),
            requestId,
            response,
            bytes("")
        );
        
        // Verify price was updated
        assertEq(assetOracle.assetPrice(), closePrice, "Asset price not updated correctly");
        assertEq(assetOracle.lastUpdated(), block.timestamp, "Last updated timestamp not set");
        
        // Verify OHLC data
        (uint256 open, uint256 high, uint256 low, uint256 close, uint256 dataTimestamp) = assetOracle.ohlcData();
        assertEq(open, openPrice, "Open price not updated correctly");
        assertEq(high, highPrice, "High price not updated correctly");
        assertEq(low, lowPrice, "Low price not updated correctly");
        assertEq(close, closePrice, "Close price not updated correctly");
        assertEq(dataTimestamp, timestamp, "Data timestamp not updated correctly");
    }
    
    function testOracleFulfillmentUnexpectedRequestId() public {
        // Create a request
        string memory source = "console.log(JSON.stringify({price: 42069000000000000000000}));";
        assetOracle.requestAssetPrice(
            source,
            SUBSCRIPTION_ID,
            GAS_LIMIT,
            DON_ID
        );
        
        // Use an unexpected request ID
        bytes32 unexpectedRequestId = bytes32(uint256(1234));
        bytes memory response = abi.encode(uint256(100e18), uint256(110e18), uint256(95e18), uint256(105e18), block.timestamp);
        
        // Expect revert with UnexpectedRequestID
        vm.prank(address(mockRouter));
        vm.expectRevert("Fulfillment call failed");
        mockRouter.fulfillRequest(
            address(assetOracle),
            unexpectedRequestId,
            response,
            bytes("")
        );
    }
    
    function testOracleFulfillmentInvalidResponse() public {
        // First make a request
        string memory source = "console.log(JSON.stringify({price: 42069000000000000000000}));";
        assetOracle.requestAssetPrice(
            source,
            SUBSCRIPTION_ID,
            GAS_LIMIT,
            DON_ID
        );
        
        bytes32 requestId = assetOracle.s_lastRequestId();
        
        // Create invalid data with zero prices
        uint256 openPrice = 0;
        uint256 highPrice = 0;
        uint256 lowPrice = 0;
        uint256 closePrice = 0;
        uint256 timestamp = block.timestamp;
        
        // Encode the response data
        bytes memory response = abi.encode(openPrice, highPrice, lowPrice, closePrice, timestamp);
        
        // Expect revert with InvalidPrice
        vm.prank(address(mockRouter));
        vm.expectRevert("Fulfillment call failed");
        mockRouter.fulfillRequest(
            address(assetOracle),
            requestId,
            response,
            bytes("")
        );
    }
    
    // ==================== SEQUENTIAL PRICE UPDATES ====================
    
    function testSequentialPriceUpdates() public {
        // First price update
        requestAndFulfillPrice(100e18, 110e18, 95e18, 105e18);
        
        // Verify first price update
        assertEq(assetOracle.assetPrice(), 105e18, "First price update failed");
        
        // Second price update - normal change
        requestAndFulfillPrice(105e18, 115e18, 100e18, 110e18);
        
        // Verify second price update
        assertEq(assetOracle.assetPrice(), 110e18, "Second price update failed");
        
        // Verify OHLC data update
        (uint256 open, uint256 high, uint256 low, uint256 close, ) = assetOracle.ohlcData();
        assertEq(open, 105e18, "Open price not updated correctly");
        assertEq(high, 115e18, "High price not updated correctly");
        assertEq(low, 100e18, "Low price not updated correctly");
        assertEq(close, 110e18, "Close price not updated correctly");
    }
    
    // ==================== MARKET STATUS TESTS ====================
    
    function testIsMarketOpenInitialState() public view {
        // When no data has been set, market should be closed
        assertFalse(assetOracle.isMarketOpen(), "Market should be closed initially");
    }
    
    function testIsMarketOpen() public {
        // First make a request and fulfill it
        string memory source = "console.log(JSON.stringify({price: 42069000000000000000000}));";
        assetOracle.requestAssetPrice(
            source,
            SUBSCRIPTION_ID,
            GAS_LIMIT,
            DON_ID
        );
        
        bytes32 requestId = assetOracle.s_lastRequestId();
        
        // Create OHLC data with a timestamp very close to the current time
        vm.warp(block.timestamp + 1 hours);
        uint256 dataTimestamp = block.timestamp - 100; // 100 seconds ago
        bytes memory response = abi.encode(
            uint256(100e18), 
            uint256(110e18), 
            uint256(95e18), 
            uint256(105e18), 
            dataTimestamp
        );
        
        // Fulfill the request
        vm.prank(address(mockRouter));
        mockRouter.fulfillRequest(
            address(assetOracle),
            requestId,
            response,
            bytes("")
        );
        
        // Market should be open since the data timestamp is very recent
        assertTrue(assetOracle.isMarketOpen(), "Market should be open");
        
        // Now let's try with an old timestamp
        assetOracle.requestAssetPrice(
            source,
            SUBSCRIPTION_ID,
            GAS_LIMIT,
            DON_ID
        );
        
        requestId = assetOracle.s_lastRequestId();
        dataTimestamp = block.timestamp - 400; // 400 seconds ago, which is > 300 threshold
        response = abi.encode(
            uint256(100e18), 
            uint256(110e18), 
            uint256(95e18), 
            uint256(105e18), 
            dataTimestamp
        );
        
        // Fulfill the request
        vm.prank(address(mockRouter));
        mockRouter.fulfillRequest(
            address(assetOracle),
            requestId,
            response,
            bytes("")
        );
        
        // Market should be closed since the data timestamp is older than threshold
        assertFalse(assetOracle.isMarketOpen(), "Market should be closed");
    }
    
    // ==================== SPLIT DETECTION TESTS ====================
    
    function testSplitDetection() public {
        // First set an initial price
        requestAndFulfillPrice(100e18, 110e18, 95e18, 105e18);
        
        // Verify initial price
        assertEq(assetOracle.assetPrice(), 105e18, "Initial price not set correctly");
        assertFalse(assetOracle.splitDetected(), "Split should not be detected initially");
        
        // Now simulate a price shock (>45% decrease) - should trigger split detection
        requestAndFulfillPrice(50e18, 55e18, 45e18, 52e18);
        
        // Verify split was detected
        assertTrue(assetOracle.splitDetected(), "Split should be detected");
        assertEq(assetOracle.preSplitPrice(), 105e18, "Pre-split price not recorded correctly");
    }
    
    function testSplitDetectionLargePriceIncrease() public {
        // First set an initial price
        requestAndFulfillPrice(100e18, 110e18, 95e18, 105e18);
        
        // Now simulate a price shock (>45% increase) - should trigger split detection
        requestAndFulfillPrice(160e18, 170e18, 155e18, 165e18);
        
        // Verify split was detected
        assertTrue(assetOracle.splitDetected(), "Split should be detected");
        assertEq(assetOracle.preSplitPrice(), 105e18, "Pre-split price not recorded correctly");
    }
    
    function testNoSplitDetectionSmallPriceChange() public {
        // First set an initial price
        requestAndFulfillPrice(100e18, 110e18, 95e18, 105e18);
        
        // Now simulate a small price change (20%) - should not trigger split detection
        requestAndFulfillPrice(120e18, 130e18, 115e18, 125e18);
        
        // Verify split was not detected
        assertFalse(assetOracle.splitDetected(), "Split should not be detected");
    }
    
    function testVerifySplit() public {
        // First set an initial price
        requestAndFulfillPrice(100e18, 110e18, 95e18, 105e18);
        
        // Now simulate a price shock - 2:1 split (price halves)
        requestAndFulfillPrice(50e18, 55e18, 45e18, 52e18);
        
        // Verify a 2:1 split (should return true)
        assertTrue(assetOracle.verifySplit(2, 1), "Should verify as a 2:1 split");
        
        // Verify an incorrect split ratio (should return false)
        assertFalse(assetOracle.verifySplit(3, 1), "Should not verify as a 3:1 split");
    }
    
    function testVerifySplitReverseSplit() public {
        // First set an initial price
        requestAndFulfillPrice(100e18, 110e18, 95e18, 105e18);
        
        // Now simulate a reverse split - 1:2 split (price doubles)
        requestAndFulfillPrice(210e18, 220e18, 200e18, 210e18);
        
        // Verify a 1:2 split (should return true)
        assertTrue(assetOracle.verifySplit(1, 2), "Should verify as a 1:2 split");
        
        // Verify an incorrect split ratio (should return false)
        assertFalse(assetOracle.verifySplit(1, 3), "Should not verify as a 1:3 split");
    }
    
    function testResetSplitDetection() public {
        // Set initial price then trigger split detection
        requestAndFulfillPrice(100e18, 110e18, 95e18, 105e18);
        requestAndFulfillPrice(50e18, 55e18, 45e18, 52e18);
        
        // Verify split was detected
        assertTrue(assetOracle.splitDetected(), "Split should be detected");
        
        // Reset split detection
        assetOracle.resetSplitDetection();
        
        // Verify split detection was reset
        assertFalse(assetOracle.splitDetected(), "Split detection should be reset");
        assertEq(assetOracle.preSplitPrice(), 0, "Pre-split price should be reset to 0");
    }
    
    // ==================== HELPER FUNCTIONS ====================
    
    function requestAndFulfillPrice(
        uint256 openPrice,
        uint256 highPrice,
        uint256 lowPrice,
        uint256 closePrice
    ) internal {
        requestAndFulfillPriceWithTimestamp(
            openPrice,
            highPrice,
            lowPrice,
            closePrice,
            block.timestamp
        );
    }
    
    function requestAndFulfillPriceWithTimestamp(
        uint256 openPrice,
        uint256 highPrice,
        uint256 lowPrice,
        uint256 closePrice,
        uint256 timestamp
    ) internal {
        // Valid source code that matches the source hash
        string memory source = "console.log(JSON.stringify({price: 42069000000000000000000}));";
        
        // Request asset price
        assetOracle.requestAssetPrice(
            source,
            SUBSCRIPTION_ID,
            GAS_LIMIT,
            DON_ID
        );
        
        bytes32 requestId = assetOracle.s_lastRequestId();
        
        // Create response data with the provided timestamp
        bytes memory response = abi.encode(openPrice, highPrice, lowPrice, closePrice, timestamp);
        
        // Fulfill the request
        vm.prank(address(mockRouter));
        mockRouter.fulfillRequest(
            address(assetOracle),
            requestId,
            response,
            bytes("")
        );
    }

    function testRequestCooldown() public {
        // Set a cooldown period
        uint256 cooldownPeriod = 1 hours;
        vm.prank(owner);
        // Update the cooldown period
        assetOracle.updateRequestCooldown(cooldownPeriod);
        assertEq(assetOracle.REQUEST_COOLDOWN(), cooldownPeriod, "Cooldown period not set correctly");
        vm.stopPrank();

        // Make the first request
        string memory source = "console.log(JSON.stringify({price: 42069000000000000000000}));";

        // Attempt to make another request before the cooldown period has elapsed
        vm.expectRevert(IAssetOracle.RequestCooldownNotElapsed.selector);
        assetOracle.requestAssetPrice(
            source,
            SUBSCRIPTION_ID,
            GAS_LIMIT,
            DON_ID
        );

        // Advance time to surpass the cooldown period
        vm.warp(block.timestamp + cooldownPeriod);

        // Make another request after the cooldown period
        assetOracle.requestAssetPrice(
            source,
            SUBSCRIPTION_ID,
            GAS_LIMIT,
            DON_ID
        );

        // Verify that the request was successful
        assertNotEq(assetOracle.s_lastRequestId(), bytes32(0), "Request ID should be set");
    }

    function testUpdateRequestCooldownUnauthorized() public {
        // Attempt to update the cooldown period from a non-owner account
        uint256 newCooldown = 1 hours;
        vm.prank(user1); // Simulate a call from an unauthorized user
        vm.expectRevert("Not owner");
        assetOracle.updateRequestCooldown(newCooldown);
    }

}