// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/utils/math/Math.sol";
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

    /// @notice Indicates if a split has been detected
    bool public splitDetected;

    /// @notice Previous price of the asset before split in 18 decimal format
    uint256 public preSplitPrice;
    
    /// @notice Timestamp of the last price update
    uint256 public lastUpdated;

    /// @notice Maximum time difference (in seconds) to consider market open
    uint256 public constant MARKET_OPEN_THRESHOLD = 300; // 300 seconds

    /// @notice Cooldown period (in seconds) for price requests
    /// @dev Prevents spamming of requests
    uint256 public REQUEST_COOLDOWN;

    /// @notice Precision factor for price calculations
    uint256 internal constant PRECISION = 1e18;
    
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
     * @param _owner Address of the contract owner
     */
    constructor(
        address router,
        string memory _assetSymbol,
        bytes32 _sourceHash,
        address _owner
    ) FunctionsClient(router) ConfirmedOwner(_owner) {
        assetSymbol = _assetSymbol;
        sourceHash = _sourceHash;
        REQUEST_COOLDOWN = 0;
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
    ) external {
        if (keccak256(abi.encodePacked(source)) != sourceHash) {
            revert InvalidSource();
        }

        // Check cooldown period
        if (block.timestamp < lastUpdated + REQUEST_COOLDOWN) {
            revert RequestCooldownNotElapsed();
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

            // Validate that none of the price values are zero
            if (openPrice == 0 || highPrice == 0 || lowPrice == 0 || closePrice == 0) {
                revert InvalidPrice();
            }
            
            // Check if a split has occurred
            if (assetPrice != 0 && _isPriceDeviationHigh(assetPrice, openPrice)) {
                splitDetected = true;
                preSplitPrice = assetPrice;
                emit SplitDetected(assetPrice, openPrice, block.timestamp);
            }
    
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
     * @notice Checks if the market for the tracked asset is currently open
     * @dev Determines market status by comparing the data source timestamp with the oracle update time
     * @dev The market status is at the time of the last update. To get the current status, call this function after a new update
     * @return bool True if the market is open, false otherwise
     */
    function isMarketOpen() external view returns (bool) {
        // If oracle has never been updated, market is considered closed
        if (lastUpdated == 0) {
            return false;
        }
        
        uint256 dataTimestamp = ohlcData.timestamp;
        
        // Compare lastUpdated timestamp with the oracle's last update time
        // If the difference is less than threshold, market is considered open
        return (lastUpdated - dataTimestamp) <= MARKET_OPEN_THRESHOLD;
    }

    /**
     * @notice Checks if a split has likely occurred based on price change
     * @param expectedRatio Expected split ratio
     * @param expectedDenominator Expected split denominator
     * @return true if a split matching the expected ratio appears to have occurred
     */
    function verifySplit(uint256 expectedRatio, uint256 expectedDenominator) external view returns (bool) {
        if ( preSplitPrice == 0 || ohlcData.open == 0) return false;
        
        // Calculate the actual price ratio (scaled by PRECISION)
        uint256 priceRatio = Math.mulDiv(preSplitPrice, PRECISION, ohlcData.open);
        
        // Calculate the expected price ratio
        uint256 expectedPriceRatio = Math.mulDiv(expectedRatio, PRECISION, expectedDenominator);
        
        // Allow for some small deviation (perhaps within 5%)
        uint256 lowerBound = Math.mulDiv(expectedPriceRatio, 95, 100);
        uint256 upperBound = Math.mulDiv(expectedPriceRatio, 105, 100);
        
        return priceRatio >= lowerBound && priceRatio <= upperBound;
    }

    /**
     * @notice Checks if the price deviation is high
     * @param prevPrice The previous price of the asset
     * @param currentPrice The current price of the asset
     * @return bool True if the price deviation is above the threshold, false otherwise
     */
    function _isPriceDeviationHigh(uint256 prevPrice, uint256 currentPrice) internal pure returns (bool) {
        uint256 threshold = 45; // 45% threshold for price deviation
        if (prevPrice == 0 || currentPrice == 0) return false;
        
        // Calculate the absolute price difference
        uint256 priceDifference = currentPrice > prevPrice
            ? currentPrice - prevPrice
            : prevPrice - currentPrice;
        
        // Calculate the percentage deviation
        uint256 percentageDeviation = Math.mulDiv(priceDifference, 100, prevPrice);
        
        return percentageDeviation > threshold;
    }

    /**
     * @notice Resets the split detection state
     * @dev Can only be called by the contract owner
     */
    function resetSplitDetection() external onlyOwner {
        splitDetected = false;
        preSplitPrice = 0;
    }

    /**
     * @notice Updates the cooldown period for price requests
     * @param newCooldown The new cooldown period in seconds
     * @dev Can only be called by the contract owner
     */
    function updateRequestCooldown(uint256 newCooldown) external onlyOwner {
        uint256 oldCooldown = REQUEST_COOLDOWN;
        REQUEST_COOLDOWN = newCooldown;
        emit RequestCooldownUpdated(oldCooldown, newCooldown);
    }
}