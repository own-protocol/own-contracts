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
     */
    function requestAssetPrice(
        string memory source,
        uint64 subscriptionId,
        uint32 /* gasLimit */,
        bytes32 /* donID */
    ) external override {
        if (keccak256(abi.encodePacked(source)) != sourceHash) {
            revert InvalidSource();
        }
        
        // In the mock, we generate a predictable requestId
        // Real implementation would get this from Chainlink Functions
        s_lastRequestId = keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            msg.sender,
            subscriptionId
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
        
        // Only try to decode if we have response data
        if (response.length > 0) {
            assetPrice = abi.decode(response, (uint256));
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
}