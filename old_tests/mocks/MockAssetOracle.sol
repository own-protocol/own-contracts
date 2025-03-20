// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import {IAssetOracle} from "../../src/interfaces/IAssetOracle.sol";

/**
 * @title MockAssetOracle
 * @notice Mock implementation of AssetOracle for testing
 * @dev Simulates Chainlink Functions behavior without external dependencies
 */
contract MockAssetOracle is IAssetOracle {
    // State variables
    bytes32 public s_lastRequestId;
    bytes public lastResponse;
    bytes public lastError;
    bytes32 public sourceHash;
    string public assetSymbol;
    uint256 public assetPrice;
    uint256 public lastUpdated;
    address public owner;
    
    // OHLC data structure for the asset
    struct OHLCData {
        uint256 open;
        uint256 high;
        uint256 low;
        uint256 close;
        uint256 timestamp;
    }
    
    // Current OHLC data for the asset
    OHLCData public ohlcData;

    constructor(
        string memory _assetSymbol,
        bytes32 _sourceHash
    ) {
        assetSymbol = _assetSymbol;
        sourceHash = _sourceHash;
        owner = msg.sender;
    }

    /**
     * @notice Checks if sender is the owner
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Only callable by owner");
        _;
    }

    /**
     * @notice Initiates a request to fetch the current asset price
     * @param source The JavaScript source code to execute
     * @param subscriptionId The Chainlink Functions subscription ID (unused in mock)
     * @param gasLimit The gas limit for the request (unused in mock)
     * @param donID The Chainlink Functions DON ID (unused in mock)
     */
    function requestAssetPrice(
        string memory source,
        uint64 subscriptionId,
        uint32 gasLimit,
        bytes32 donID
    ) external override onlyOwner {
        if (keccak256(abi.encodePacked(source)) != sourceHash) {
            revert InvalidSource();
        }
        
        // In the mock, we generate a predictable requestId
        // Real implementation would get this from Chainlink Functions
        s_lastRequestId = keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            msg.sender,
            subscriptionId,
            gasLimit,
            donID
        ));
        
        // Additional logic would go here in a real implementation
    }

    /**
     * @notice Mock function to simulate fulfillment callback
     * @dev This simplifies testing by allowing direct price updates
     * @param requestId The ID of the request being fulfilled
     * @param response The response data
     * @param error Any error message
     */
    function mockFulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory error
    ) external {
        if (requestId != s_lastRequestId) {
            revert UnexpectedRequestID(requestId);
        }
        
        lastResponse = response;
        lastError = error;
        
        if (response.length > 0) {
            // Decode the ABI encoded response data to match the real contract
            (
                uint256 openPrice,
                uint256 highPrice,
                uint256 lowPrice,
                uint256 closePrice,
                uint256 dataTimestamp
            ) = abi.decode(response, (uint256, uint256, uint256, uint256, uint256));
            
            // Update asset price
            assetPrice = closePrice;
            
            // Update OHLC data
            ohlcData = OHLCData({
                open: openPrice,
                high: highPrice,
                low: lowPrice,
                close: closePrice,
                timestamp: dataTimestamp
            });
            
            // Update timestamp
            lastUpdated = block.timestamp;
            
            emit AssetPriceUpdated(assetPrice, block.timestamp);
        }
    }

    /**
     * @notice Updates the hash of the valid JavaScript source code
     * @param newSourceHash The new hash to validate source code against
     */
    function updateSourceHash(bytes32 newSourceHash) external override onlyOwner {
        sourceHash = newSourceHash;
        emit SourceHashUpdated(newSourceHash);
    }

    /**
     * @notice Updates the asset symbol
     * @param newAssetSymbol The new asset symbol
     */
    function updateAssetSymbol(string memory newAssetSymbol) external override onlyOwner {
        assetSymbol = newAssetSymbol;
        emit AssetSymbolUpdated(newAssetSymbol);
    }
    
    /**
     * @notice Returns the current OHLC data for the asset
     * @return open The opening price
     * @return high The highest price
     * @return low The lowest price
     * @return close The closing price
     * @return timestamp The timestamp of the OHLC data
     */
    function getOHLCData() external view override returns (
        uint256 open,
        uint256 high,
        uint256 low,
        uint256 close,
        uint256 timestamp
    ) {
        return (
            ohlcData.open,
            ohlcData.high,
            ohlcData.low,
            ohlcData.close,
            ohlcData.timestamp
        );
    }

    /**
     * @notice Checks if the market for the tracked asset is currently open
     * @dev Determines market status by comparing the data source timestamp with the oracle update time
     * @dev The market status is at the time of the last update. To get the current status, call this function after a new update
     * @return bool True if the market is open, false otherwise
     */
    function isMarketOpen() external view returns (bool) {
        return (lastUpdated - ohlcData.timestamp) < 60;
    }
    
    /**
     * @notice Helper function to directly set OHLC data for testing
     * @param open The opening price
     * @param high The highest price
     * @param low The lowest price
     * @param close The closing price
     * @param timestamp The timestamp of the OHLC data
     */
    function mockSetOHLCData(
        uint256 open,
        uint256 high,
        uint256 low,
        uint256 close,
        uint256 timestamp
    ) external onlyOwner {
        ohlcData = OHLCData({
            open: open,
            high: high,
            low: low,
            close: close,
            timestamp: timestamp
        });
        
        emit OHLCDataUpdated(open, high, low, close, timestamp);
    }
    
    /**
     * @notice Helper function to directly set asset price for testing
     * @param price The price to set
     */
    function mockSetAssetPrice(uint256 price) external onlyOwner {
        assetPrice = price;
        lastUpdated = block.timestamp;
        emit AssetPriceUpdated(price, block.timestamp);
    }
}