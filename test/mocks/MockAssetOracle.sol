// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "../../src/interfaces/IAssetOracle.sol";

/**
 * @title MockAssetOracle
 * @notice Mock Asset Oracle for testing that allows direct price setting
 */
contract MockAssetOracle {
    string public symbol;
    bytes32 public sourceCodeHash;
    bytes32 public s_lastRequestId;
    uint256 public assetPrice;
    uint256 public lastUpdatedTimestamp;
    bool public isPriceStale;
    uint256 public minPriceDeviation;
    uint256 public maxPriceAge;
    
    mapping(bytes32 => bool) public pendingRequests;
    
    event AssetPriceUpdated(uint256 price, uint256 timestamp);
    event AssetPriceRequested(bytes32 requestId);
    
    constructor(string memory _symbol, bytes32 _sourceCodeHash) {
        symbol = _symbol;
        sourceCodeHash = _sourceCodeHash;
        assetPrice = 1e18; // Default price of 1
        lastUpdatedTimestamp = block.timestamp;
        minPriceDeviation = 300; // 3% in basis points
        maxPriceAge = 1 days;
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
            uint256 price = abi.decode(response, (uint256));
            assetPrice = price;
            lastUpdatedTimestamp = block.timestamp;
            isPriceStale = false;
            
            emit AssetPriceUpdated(price, block.timestamp);
        }
        
        pendingRequests[requestId] = false;
    }
    
    function verifySplit(uint256 splitRatio, uint256 splitDenominator) external pure returns (bool) {
        // Allow any split ratio for testing
        return splitRatio > 0 && splitDenominator > 0;
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
    
    // Additional functions to satisfy IAssetOracle interface
    function assetSymbol() external view returns (string memory) {
        return symbol;
    }
    
    function getOHLCData() external view returns (
        uint256 open,
        uint256 high,
        uint256 low,
        uint256 close,
        uint256 timestamp
    ) {
        return (assetPrice, assetPrice, assetPrice, assetPrice, lastUpdatedTimestamp);
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
        return assetPrice;
    }
    
    function resetSplitDetection() external {
        // No-op for testing
    }
    
    function sourceHash() external view returns (bytes32) {
        return sourceCodeHash;
    }
    
    function splitDetected() external pure returns (bool) {
        return false;
    }
    
    function updateAssetSymbol(string memory newAssetSymbol) external {
        symbol = newAssetSymbol;
    }
    
    function updateSourceCodeHash(bytes32 newSourceCodeHash) external {
        sourceCodeHash = newSourceCodeHash;
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