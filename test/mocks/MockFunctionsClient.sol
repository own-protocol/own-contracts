// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../src/interfaces/IAssetOracle.sol";

/**
 * @title MockFunctionsClient
 * @notice A mock implementation of FunctionsClient for testing AssetOracle
 */
contract MockFunctionsClient {
    event RequestSent(bytes32 indexed requestId);
    
    address private immutable i_router;
    
    constructor(address router) {
        i_router = router;
    }
    
    function _sendRequest(
        bytes memory encodedRequest,
        uint64 subscriptionId,
        uint32 gasLimit,
        bytes32 donId
    ) internal returns (bytes32) {
        bytes32 requestId = keccak256(abi.encode(
            encodedRequest,
            subscriptionId,
            gasLimit,
            donId,
            block.timestamp
        ));
        
        emit RequestSent(requestId);
        
        return requestId;
    }
}

/**
 * @title MockFunctionsRouter
 * @notice Mock contract for Chainlink Functions Router
 */
contract MockFunctionsRouter {
    event RequestFulfilled(bytes32 indexed requestId, bytes response, bytes err);
    
    function fulfillRequest(
        address client,
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) external {
        // Call the handleOracleFulfillment function on the client contract
        (bool success, ) = client.call(
            abi.encodeWithSignature(
                "handleOracleFulfillment(bytes32,bytes,bytes)",
                requestId,
                response,
                err
            )
        );
        
        require(success, "Fulfillment call failed");
        
        emit RequestFulfilled(requestId, response, err);
    }
}

/**
 * @title MockConfirmedOwner
 * @notice A mock implementation of ConfirmedOwner for testing
 */
contract MockConfirmedOwner {
    address private s_owner;
    
    constructor(address initialOwner) {
        s_owner = initialOwner;
    }
    
    modifier onlyOwner() {
        require(msg.sender == s_owner, "Not owner");
        _;
    }
    
    function owner() public view returns (address) {
        return s_owner;
    }
}

/**
 * @title MockAssetOracle
 * @notice Mock implementation of AssetOracle for testing
 * @dev This implementation bypasses the Chainlink Functions infrastructure
 */
contract MockAssetOracle is MockFunctionsClient, MockConfirmedOwner, IAssetOracle {
    bytes32 public s_lastRequestId;
    bytes public lastResponse;
    bytes public lastError;
    bytes32 public sourceHash;
    string public assetSymbol;
    uint256 public assetPrice;
    bool public splitDetected;
    uint256 public preSplitPrice;
    uint256 public lastUpdated;
    
    struct OHLCData {
        uint256 open;
        uint256 high;
        uint256 low;
        uint256 close;
        uint256 timestamp;
    }
    
    OHLCData public ohlcData;
    
    uint256 private constant MARKET_OPEN_THRESHOLD = 300; // 300 seconds
    uint256 internal constant PRECISION = 1e18;
    uint256 public REQUEST_COOLDOWN;
    
    constructor(
        address router,
        string memory _assetSymbol,
        bytes32 _sourceHash,
        address _owner
    ) MockFunctionsClient(router) MockConfirmedOwner(_owner) {
        assetSymbol = _assetSymbol;
        sourceHash = _sourceHash;
        REQUEST_COOLDOWN = 0;
    }
    
    function requestAssetPrice(
        string memory source,
        uint64 subscriptionId,
        uint32 gasLimit,
        bytes32 donId
    ) external {
        if (keccak256(abi.encodePacked(source)) != sourceHash) {
            revert InvalidSource();
        }

        if(block.timestamp < lastUpdated + REQUEST_COOLDOWN) {
            revert RequestCooldownNotElapsed();
        }
        
        // Create a mock request
        bytes memory emptyBytes = new bytes(0);
        s_lastRequestId = _sendRequest(emptyBytes, subscriptionId, gasLimit, donId);
    }
    
    function handleOracleFulfillment(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) external {
        if (requestId != s_lastRequestId) {
            revert UnexpectedRequestID(requestId);
        }
        
        lastResponse = response;
        lastError = err;
        
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
                emit SplitDetected(assetPrice, block.timestamp);
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
    
    function updateSourceHash(bytes32 newSourceHash) external onlyOwner {
        sourceHash = newSourceHash;
        emit SourceHashUpdated(newSourceHash);
    }
    
    function updateAssetSymbol(string memory newAssetSymbol) external onlyOwner {
        assetSymbol = newAssetSymbol;
        emit AssetSymbolUpdated(newAssetSymbol);
    }
    
    function isMarketOpen() external view returns (bool) {
        if (lastUpdated == 0) {
            return false;
        }
        
        uint256 dataTimestamp = ohlcData.timestamp;
        
        return (lastUpdated - dataTimestamp) <= MARKET_OPEN_THRESHOLD;
    }
    
    function verifySplit(uint256 expectedRatio, uint256 expectedDenominator) external view returns (bool) {
        if (preSplitPrice == 0 || ohlcData.open == 0) return false;
        
        // Calculate the actual price ratio (scaled by PRECISION)
        uint256 priceRatio = (preSplitPrice * PRECISION) / ohlcData.open;
        
        // Calculate the expected price ratio
        uint256 expectedPriceRatio = (expectedRatio * PRECISION) / expectedDenominator;
        
        // Allow for some small deviation (perhaps within 5%)
        uint256 lowerBound = (expectedPriceRatio * 95) / 100;
        uint256 upperBound = (expectedPriceRatio * 105) / 100;
        
        return priceRatio >= lowerBound && priceRatio <= upperBound;
    }
    
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

    function setSplitDetected() external onlyOwner {
        splitDetected = true;
        preSplitPrice = assetPrice;
        emit SplitDetected(assetPrice, block.timestamp);
    }
    
    function resetSplitDetection() external onlyOwner {
        splitDetected = false;
        preSplitPrice = 0;
    }

    function updateRequestCooldown(uint256 newCooldown) external onlyOwner {
        // This function is a placeholder for updating the request cooldown
        // In a real implementation, you would update the cooldown logic here
        REQUEST_COOLDOWN = newCooldown;
    }
}