// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {MockAssetOracle} from "./mocks/MockAssetOracle.sol";
import {IAssetOracle} from "../src/interfaces/IAssetOracle.sol";

contract MockAssetOracleTest is Test {
    // Main contract
    MockAssetOracle public oracle;

    // Test variables
    string constant ASSET_SYMBOL = "TSLA";
    bytes32 constant SOURCE_HASH = keccak256(abi.encodePacked("console.log(JSON.stringify({price: 42069000000000000000000}));"));
    string constant SOURCE_CODE = "console.log(JSON.stringify({price: 42069000000000000000000}));";
    uint64 constant SUBSCRIPTION_ID = 123;
    uint32 constant GAS_LIMIT = 300000;
    bytes32 constant DON_ID = bytes32("don1");
    address constant OWNER = address(0x1);
    address constant NON_OWNER = address(0x2);

    // Events to test
    event AssetPriceUpdated(uint256 price, uint256 timestamp);
    event SourceHashUpdated(bytes32 newSourceHash);
    event AssetSymbolUpdated(string newAssetSymbol);
    
    function setUp() public {
        vm.startPrank(OWNER);
        oracle = new MockAssetOracle(ASSET_SYMBOL, SOURCE_HASH);
        vm.stopPrank();
    }

    function test_Constructor() public view {
        assertEq(oracle.assetSymbol(), ASSET_SYMBOL);
        assertEq(oracle.sourceHash(), SOURCE_HASH);
        assertEq(oracle.owner(), OWNER);
        assertEq(oracle.assetPrice(), 0);
        assertEq(oracle.lastUpdated(), 0);
    }

    function test_RequestAssetPrice() public {
        vm.startPrank(OWNER);
        
        bytes32 initialRequestId = oracle.s_lastRequestId();
        
        oracle.requestAssetPrice(
            SOURCE_CODE,
            SUBSCRIPTION_ID,
            GAS_LIMIT,
            DON_ID
        );
        
        bytes32 newRequestId = oracle.s_lastRequestId();
        
        // Verify a new request ID was generated
        assertTrue(initialRequestId != newRequestId, "Request ID should change");
        
        vm.stopPrank();
    }

    function test_RequestAssetPrice_InvalidSource() public {
        vm.startPrank(OWNER);
        
        string memory invalidSource = "console.log('malicious code');";
        
        vm.expectRevert(IAssetOracle.InvalidSource.selector);
        oracle.requestAssetPrice(
            invalidSource,
            SUBSCRIPTION_ID,
            GAS_LIMIT,
            DON_ID
        );
        
        vm.stopPrank();
    }

    function test_FulfillRequest() public {
        vm.startPrank(OWNER);
        
        // First send a request
        oracle.requestAssetPrice(
            SOURCE_CODE,
            SUBSCRIPTION_ID,
            GAS_LIMIT,
            DON_ID
        );
        
        bytes32 requestId = oracle.s_lastRequestId();
        
        vm.stopPrank();
        
        // Prepare response data - price of 42069 with 18 decimals
        uint256 expectedPrice = 42069 * 10**18;
        bytes memory response = abi.encode(expectedPrice);
        bytes memory error = "";
        
        // Mock the timestamp
        uint256 timestamp = 1677858000;
        vm.warp(timestamp);
        
        // Expect the price update event
        vm.expectEmit(true, true, true, true);
        emit AssetPriceUpdated(expectedPrice, timestamp);
        
        // Fulfill the request
        oracle.mockFulfillRequest(
            requestId,
            response,
            error
        );
        
        // Verify the state changes
        assertEq(oracle.assetPrice(), expectedPrice);
        assertEq(oracle.lastUpdated(), timestamp);
        assertEq(oracle.lastResponse(), response);
        assertEq(oracle.lastError(), error);
    }

    function test_FulfillRequest_UnexpectedId() public {
        vm.startPrank(OWNER);
        
        // First send a request
        oracle.requestAssetPrice(
            SOURCE_CODE,
            SUBSCRIPTION_ID,
            GAS_LIMIT,
            DON_ID
        );
        
        vm.stopPrank();
        
        // Prepare response data
        uint256 price = 42069 * 10**18;
        bytes memory response = abi.encode(price);
        bytes memory error = "";
        
        // Try to fulfill with wrong request ID
        bytes32 wrongRequestId = bytes32("wrong_id");
        
        vm.expectRevert(abi.encodeWithSelector(IAssetOracle.UnexpectedRequestID.selector, wrongRequestId));
        oracle.mockFulfillRequest(
            wrongRequestId,
            response,
            error
        );
    }

    function test_UpdateSourceHash() public {
        vm.startPrank(OWNER);
        
        bytes32 newSourceHash = keccak256(abi.encodePacked("new source code"));
        
        vm.expectEmit(true, true, true, true);
        emit SourceHashUpdated(newSourceHash);
        
        oracle.updateSourceHash(newSourceHash);
        assertEq(oracle.sourceHash(), newSourceHash);
        
        vm.stopPrank();
    }

    function test_UpdateSourceHash_NotOwner() public {
        vm.startPrank(NON_OWNER);
        
        bytes32 newSourceHash = keccak256(abi.encodePacked("new source code"));
        
        vm.expectRevert("Only callable by owner");
        oracle.updateSourceHash(newSourceHash);
        
        vm.stopPrank();
    }

    function test_UpdateAssetSymbol() public {
        vm.startPrank(OWNER);
        
        string memory newSymbol = "AAPL";
        
        vm.expectEmit(true, true, true, true);
        emit AssetSymbolUpdated(newSymbol);
        
        oracle.updateAssetSymbol(newSymbol);
        assertEq(oracle.assetSymbol(), newSymbol);
        
        vm.stopPrank();
    }

    function test_UpdateAssetSymbol_NotOwner() public {
        vm.startPrank(NON_OWNER);
        
        string memory newSymbol = "AAPL";
        
        vm.expectRevert("Only callable by owner");
        oracle.updateAssetSymbol(newSymbol);
        
        vm.stopPrank();
    }

    function test_FulfillRequest_WithPartialError() public {
        // First send a request
        vm.startPrank(OWNER);
        
        oracle.requestAssetPrice(
            SOURCE_CODE,
            SUBSCRIPTION_ID,
            GAS_LIMIT,
            DON_ID
        );
        
        bytes32 requestId = oracle.s_lastRequestId();
        
        vm.stopPrank();
        
        // Prepare partial success response - has both response and error
        uint256 newPrice = 50000 * 10**18;
        bytes memory response = abi.encode(newPrice);
        bytes memory error = bytes("Warning: API responded with partial data");
        
        uint256 timestamp = 1678001000;
        vm.warp(timestamp);
        
        // Expect price update even with warning
        vm.expectEmit(true, true, true, true);
        emit AssetPriceUpdated(newPrice, timestamp);
        
        oracle.mockFulfillRequest(
            requestId,
            response,
            error
        );
        
        // Verify both response and error are stored, and price is updated
        assertEq(oracle.lastError(), error);
        assertEq(oracle.lastResponse(), response);
        assertEq(oracle.assetPrice(), newPrice);
        assertEq(oracle.lastUpdated(), timestamp);
    }
    
    function test_FulfillRequest_EmptyResponse() public {
        // First send a request
        vm.startPrank(OWNER);
        
        oracle.requestAssetPrice(
            SOURCE_CODE,
            SUBSCRIPTION_ID,
            GAS_LIMIT,
            DON_ID
        );
        
        bytes32 requestId = oracle.s_lastRequestId();
        
        vm.stopPrank();
        
        // Set initial price to verify it doesn't change
        bytes memory initialResponse = abi.encode(1000 * 10**18);
        oracle.mockFulfillRequest(
            requestId,
            initialResponse,
            new bytes(0)
        );
        
        uint256 initialPrice = oracle.assetPrice();
        uint256 initialTimestamp = oracle.lastUpdated();
        
        // Send a new request
        vm.prank(OWNER);
        oracle.requestAssetPrice(
            SOURCE_CODE,
            SUBSCRIPTION_ID,
            GAS_LIMIT,
            DON_ID
        );
        
        requestId = oracle.s_lastRequestId();
        
        // Now try with empty response
        bytes memory emptyResponse = new bytes(0);
        bytes memory criticalError = bytes("Gateway timeout: no response from API");
        
        // This should not update the price
        oracle.mockFulfillRequest(
            requestId,
            emptyResponse, 
            criticalError
        );
        
        // Price should remain unchanged
        assertEq(oracle.assetPrice(), initialPrice);
        assertEq(oracle.lastUpdated(), initialTimestamp);
        
        // But error should be updated
        assertEq(oracle.lastError(), criticalError);
        assertEq(oracle.lastResponse(), emptyResponse);
    }

    function test_MultipleUpdates() public {
        bytes32[] memory requestIds = new bytes32[](3);
        uint256[] memory prices = new uint256[](3);
        prices[0] = 70000 * 10**18;  // $70,000
        prices[1] = 71500 * 10**18;  // $71,500
        prices[2] = 69800 * 10**18;  // $69,800
        
        uint256[] memory timestamps = new uint256[](3);
        timestamps[0] = 1678100000;
        timestamps[1] = 1678186400;  // +1 day
        timestamps[2] = 1678272800;  // +2 days
        
        for (uint i = 0; i < 3; i++) {
            // Request price update
            vm.startPrank(OWNER);
            oracle.requestAssetPrice(
                SOURCE_CODE,
                SUBSCRIPTION_ID,
                GAS_LIMIT,
                DON_ID
            );
            
            requestIds[i] = oracle.s_lastRequestId();
            vm.stopPrank();
            
            // Warp to next timestamp
            vm.warp(timestamps[i]);
            
            // Fulfill request
            bytes memory response = abi.encode(prices[i]);
            bytes memory error = "";
            
            vm.expectEmit(true, true, true, true);
            emit AssetPriceUpdated(prices[i], timestamps[i]);
            
            oracle.mockFulfillRequest(
                requestIds[i],
                response,
                error
            );
            
            // Verify state after update
            assertEq(oracle.assetPrice(), prices[i]);
            assertEq(oracle.lastUpdated(), timestamps[i]);
        }
        
        // Final price should be the last update
        assertEq(oracle.assetPrice(), prices[2]);
        assertEq(oracle.lastUpdated(), timestamps[2]);
    }

    function test_EndToEnd_PriceUpdateFlow() public {
        // Step 1: Request a price update as owner
        vm.startPrank(OWNER);
        oracle.requestAssetPrice(
            SOURCE_CODE,
            SUBSCRIPTION_ID,
            GAS_LIMIT,
            DON_ID
        );
        
        bytes32 requestId = oracle.s_lastRequestId();
        vm.stopPrank();
        
        // Verify initial state
        assertEq(oracle.assetPrice(), 0);
        assertEq(oracle.lastUpdated(), 0);
        
        // Step 2: Fulfill with price data
        uint256 expectedPrice = 75000 * 10**18; // $75,000 with 18 decimals
        bytes memory response = abi.encode(expectedPrice);
        bytes memory error = "";
        
        uint256 responseTime = 1678000000;
        vm.warp(responseTime);
        
        vm.expectEmit(true, true, true, true);
        emit AssetPriceUpdated(expectedPrice, responseTime);
        
        oracle.mockFulfillRequest(
            requestId,
            response,
            error
        );
        
        // Step 3: Verify state after update
        assertEq(oracle.assetPrice(), expectedPrice);
        assertEq(oracle.lastUpdated(), responseTime);
        assertEq(oracle.assetSymbol(), ASSET_SYMBOL);
        
        // Step 4: Update asset symbol as owner
        vm.prank(OWNER);
        string memory newSymbol = "TSLA-USD";
        oracle.updateAssetSymbol(newSymbol);
        assertEq(oracle.assetSymbol(), newSymbol);
    }
}