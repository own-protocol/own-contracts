// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import { FunctionsClient } from "@chainlink/contracts/v0.8/functions/v1_0_0/FunctionsClient.sol";
import { ConfirmedOwner } from "@chainlink/contracts/v0.8/shared/access/ConfirmedOwner.sol";
import { FunctionsRequest } from "@chainlink/contracts/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import { IAssetOracle } from "../interfaces/IAssetOracle.sol";

/**
 * @title AssetOracle
 * @notice Oracle contract that fetches and stores real-world asset prices using Chainlink Functions
 * @dev Implements Chainlink Functions to execute off-chain JavaScript code for price fetching
 */
contract AssetOracle is IAssetOracle, FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;

    /// @notice ID of the last Chainlink Functions request
    bytes32 public s_lastRequestId;
    
    /// @notice Raw response from the last Chainlink Functions request
    bytes public lastResponse;
    
    /// @notice Error message from the last Chainlink Functions request, if any
    bytes public lastError;
    
    /// @notice Hash of the valid JavaScript source code
    bytes32 public sourceHash;

    /// @notice Symbol of the asset being tracked (e.g., "TSLA")
    string public assetSymbol;
    
    /// @notice Current price of the asset in 18 decimal format
    uint256 public assetPrice;
    
    /// @notice Timestamp of the last price update
    uint256 public lastUpdated;
    
    /// @notice OHLC data structure for the asset
    struct OHLCData {
        uint256 open;
        uint256 high;
        uint256 low;
        uint256 close;
        uint256 timestamp;
    }
    
    /// @notice Current OHLC data for the asset
    OHLCData public ohlcData;

    /**
     * @notice Constructs the AssetOracle contract
     * @param router Address of the Chainlink Functions Router
     * @param _assetSymbol Symbol of the asset to track
     * @param _sourceHash Hash of the valid JavaScript source code
     */
    constructor(
        address router,
        string memory _assetSymbol,
        bytes32 _sourceHash
    ) FunctionsClient(router) ConfirmedOwner(msg.sender) {
        assetSymbol = _assetSymbol;
        sourceHash = _sourceHash;
    }

    /**
     * @notice Initiates a request to fetch the current asset price
     * @param source The JavaScript source code to execute
     * @param subscriptionId The Chainlink Functions subscription ID
     * @param gasLimit The gas limit for the request
     * @param donID The Chainlink Functions DON ID
     */
    function requestAssetPrice(
        string memory source,
        uint64 subscriptionId,
        uint32 gasLimit,
        bytes32 donID
    ) external onlyOwner {
        if (keccak256(abi.encodePacked(source)) != sourceHash) {
            revert InvalidSource();
        }
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);
        s_lastRequestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            gasLimit,
            donID
        );
    }

    /**
     * @notice Callback function for Chainlink Functions to return the result
     * @dev This function is called by the Chainlink Functions Router when the request is fulfilled
     * @param requestId The ID of the request being fulfilled
     * @param response The response data from the JavaScript execution
     * @param error Any error message from the JavaScript execution
     */
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory error
    ) internal override {
        if (requestId != s_lastRequestId) {
            revert UnexpectedRequestID(requestId);
        }
        
        lastResponse = response;
        lastError = error;
        
        if (response.length > 0) {
            // Decode the ABI encoded response data
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
    function updateSourceHash(bytes32 newSourceHash) external onlyOwner {
        sourceHash = newSourceHash;
        emit SourceHashUpdated(newSourceHash);
    }

    /**
     * @notice Updates the asset symbol
     * @param newAssetSymbol The new asset symbol
     */
    function updateAssetSymbol(string memory newAssetSymbol) external onlyOwner {
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
    function getOHLCData() external view returns (
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
}