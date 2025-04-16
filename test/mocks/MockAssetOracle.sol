// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

/**
 * @title MockAssetOracle
 * @notice Mock Asset Oracle for testing that allows direct price setting with full OHLC data
 */
contract MockAssetOracle {
    string public symbol;
    bytes32 public sourceCodeHash;
    bytes32 public s_lastRequestId;
    uint256 public assetPrice; // This is the close price for backward compatibility
    uint256 public lastUpdatedTimestamp;
    bool public isPriceStale;
    uint256 public minPriceDeviation;
    uint256 public maxPriceAge;
    bool private splitDetectedFlag;
    uint256 private preSplitPriceValue;

    uint256 private constant PRECISION = 1e18; // Precision for calculations
    
    // OHLC Data structure
    struct OHLCData {
        uint256 open;
        uint256 high;
        uint256 low;
        uint256 close;
        uint256 timestamp;
    }
    
    // Current OHLC data
    OHLCData public ohlcData;
    
    mapping(bytes32 => bool) public pendingRequests;
    
    event AssetPriceUpdated(uint256 price, uint256 timestamp);
    event AssetPriceRequested(bytes32 requestId);
    event OHLCDataUpdated(
        uint256 open,
        uint256 high,
        uint256 low,
        uint256 close,
        uint256 timestamp
    );
    
    constructor(string memory _symbol, bytes32 _sourceCodeHash) {
        symbol = _symbol;
        sourceCodeHash = _sourceCodeHash;
    }
    
    function requestAssetPrice(
        string calldata sourceCode,
        uint64 subscriptionId,
        uint32 gasLimit,
        bytes32 donId
    ) external {
        bytes32 requestId = keccak256(abi.encode(sourceCode, subscriptionId, gasLimit, donId, block.timestamp));
        s_lastRequestId = requestId;
        pendingRequests[requestId] = true;
        
        emit AssetPriceRequested(requestId);
    }
    
    function mockFulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) external {
        require(pendingRequests[requestId], "Request not found");
        
        if (err.length == 0) {
            // If response format is for full OHLC data
            if (response.length >= 160) { // 5 * 32 bytes (for open, high, low, close, timestamp)
                (
                    uint256 openPrice,
                    uint256 highPrice,
                    uint256 lowPrice,
                    uint256 closePrice,
                    uint256 dataTimestamp
                ) = abi.decode(response, (uint256, uint256, uint256, uint256, uint256));
                
                // Check if a split might have occurred (significant price deviation)
                if (assetPrice != 0 && _isPriceDeviationHigh(assetPrice, openPrice)) {
                    splitDetectedFlag = true;
                    preSplitPriceValue = assetPrice;
                }
                
                // Update OHLC data
                ohlcData = OHLCData({
                    open: openPrice,
                    high: highPrice,
                    low: lowPrice,
                    close: closePrice,
                    timestamp: dataTimestamp
                });
                
                // Update the asset price (close price) for backward compatibility
                assetPrice = closePrice;
                lastUpdatedTimestamp = block.timestamp;
                isPriceStale = false;
                
                emit OHLCDataUpdated(openPrice, highPrice, lowPrice, closePrice, dataTimestamp);
                emit AssetPriceUpdated(closePrice, block.timestamp);
            } 
            // Backward compatibility - single price response
            else {
                uint256 price = abi.decode(response, (uint256));
                assetPrice = price;
                
                // Update OHLC data with the same price for all values
                ohlcData = OHLCData({
                    open: price,
                    high: price,
                    low: price,
                    close: price,
                    timestamp: block.timestamp
                });
                
                lastUpdatedTimestamp = block.timestamp;
                isPriceStale = false;
                
                emit OHLCDataUpdated(price, price, price, price, block.timestamp);
                emit AssetPriceUpdated(price, block.timestamp);
            }
        }
        
        pendingRequests[requestId] = false;
    }
    
    /**
     * @notice Manually set the OHLC data for testing
     * @param openPrice The opening price
     * @param highPrice The highest price in the period
     * @param lowPrice The lowest price in the period
     * @param closePrice The closing price
     * @param dataTimestamp The timestamp for the OHLC data
     */
    function setOHLCData(
        uint256 openPrice,
        uint256 highPrice,
        uint256 lowPrice,
        uint256 closePrice,
        uint256 dataTimestamp
    ) external {
        // Check if a split might have occurred (significant price deviation)
        if (assetPrice != 0 && _isPriceDeviationHigh(assetPrice, openPrice)) {
            splitDetectedFlag = true;
            preSplitPriceValue = assetPrice;
        }
        
        ohlcData = OHLCData({
            open: openPrice,
            high: highPrice,
            low: lowPrice,
            close: closePrice,
            timestamp: dataTimestamp
        });
        
        // Update the asset price (close price) for backward compatibility
        assetPrice = closePrice;
        lastUpdatedTimestamp = block.timestamp;
        isPriceStale = false;
        
        emit OHLCDataUpdated(openPrice, highPrice, lowPrice, closePrice, dataTimestamp);
        emit AssetPriceUpdated(closePrice, block.timestamp);
    }
    
    /**
     * @notice Checks if price deviation is high (potentially indicating a stock split)
     * @param prevPrice Previous price
     * @param currentPrice Current price
     * @return True if price deviation exceeds threshold
     */
    function _isPriceDeviationHigh(uint256 prevPrice, uint256 currentPrice) internal pure returns (bool) {
        uint256 threshold = 45; // 45% threshold for price deviation
        if (prevPrice == 0 || currentPrice == 0) return false;
        
        // Calculate the absolute price difference
        uint256 priceDifference = currentPrice > prevPrice
            ? currentPrice - prevPrice
            : prevPrice - currentPrice;
        
        // Calculate the percentage deviation
        uint256 percentageDeviation = (priceDifference * 100) / prevPrice;
        
        return percentageDeviation > threshold;
    }
    
    function verifySplit(uint256 expectedRatio, uint256 expectedDenominator) external view returns (bool) {
        if (preSplitPriceValue == 0 || ohlcData.open == 0) return false;
        
        // Calculate the actual price ratio (scaled by PRECISION)
        uint256 priceRatio = (preSplitPriceValue * PRECISION) / ohlcData.open;
        
        // Calculate the expected price ratio
        uint256 expectedPriceRatio = (expectedRatio * PRECISION) / expectedDenominator;
        
        // Allow for some small deviation (perhaps within 5%)
        uint256 lowerBound = (expectedPriceRatio * 95) / 100;
        uint256 upperBound = (expectedPriceRatio * 105) / 100;
        
        return priceRatio >= lowerBound && priceRatio <= upperBound;
    }
    
    function getAssetPrice() external view returns (uint256) {
        return assetPrice;
    }
    
    function isPriceValid() external view returns (bool) {
        return !isPriceStale && (block.timestamp - lastUpdatedTimestamp <= maxPriceAge);
    }
    
    function getMinPriceDeviation() external view returns (uint256) {
        return minPriceDeviation;
    }
    
    function getSourceCodeHash() external view returns (bytes32) {
        return sourceCodeHash;
    }
    
    function getAssetSymbol() external view returns (string memory) {
        return symbol;
    }
    
    function assetSymbol() external view returns (string memory) {
        return symbol;
    }
    
    // Add market open state variable that can be controlled
    bool private marketOpen = true;
    
    function isMarketOpen() external view returns (bool) {
        return marketOpen;
    }
    
    function setMarketOpen(bool _isOpen) external {
        marketOpen = _isOpen;
    }
    
    function lastUpdated() external view returns (uint256) {
        return lastUpdatedTimestamp;
    }
    
    function preSplitPrice() external view returns (uint256) {
        return preSplitPriceValue;
    }
    
    function resetSplitDetection() external {
        splitDetectedFlag = false;
        preSplitPriceValue = 0;
    }
    
    function sourceHash() external view returns (bytes32) {
        return sourceCodeHash;
    }
    
    function splitDetected() external view returns (bool) {
        return splitDetectedFlag;
    }
    
    function setSplitDetected(bool _detected, uint256 _preSplitPrice) external {
        splitDetectedFlag = _detected;
        preSplitPriceValue = _preSplitPrice;
    }
    
    function updateAssetSymbol(string memory newAssetSymbol) external {
        symbol = newAssetSymbol;
    }
    
    function updateSourceHash(bytes32 newSourceHash) external {
        sourceCodeHash = newSourceHash;
    }
    
    function setMinPriceDeviation(uint256 _minPriceDeviation) external {
        minPriceDeviation = _minPriceDeviation;
    }
    
    function setMaxPriceAge(uint256 _maxPriceAge) external {
        maxPriceAge = _maxPriceAge;
    }
    
    function setPriceStale(bool _isPriceStale) external {
        isPriceStale = _isPriceStale;
    }
}