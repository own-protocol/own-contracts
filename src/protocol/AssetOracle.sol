// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import { FunctionsClient } from "@chainlink/contracts/v0.8/functions/v1_0_0/FunctionsClient.sol";
import { ConfirmedOwner } from "@chainlink/contracts/v0.8/shared/access/ConfirmedOwner.sol";
import { FunctionsRequest } from "@chainlink/contracts/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

contract AssetOracle is FunctionsClient, ConfirmedOwner {
     using FunctionsRequest for FunctionsRequest.Request;

    bytes32 public s_lastRequestId;
    bytes public lastResponse;
    bytes public lastError;
    bytes32 public sourceHash; // Hash of the valid source

    string public assetSymbol;  // Asset symbol (e.g., "TSLA")
    uint256 public assetPrice; // Price in cents
    uint256 public lastUpdated; // Timestamp of last update
    
    event AssetSymbolUpdated(string newAssetSymbol);
    event AssetPriceUpdated(uint256 price, uint256 timestamp);
    event SourceHashUpdated(bytes32 newSourceHash);

    error UnexpectedRequestID(bytes32 requestId);
    error InvalidSource();

    constructor(address router, string memory _assetSymbol, bytes32 _sourceHash)
        FunctionsClient(router)
        ConfirmedOwner(msg.sender)
    {
        assetSymbol = _assetSymbol;
        sourceHash = _sourceHash;
    }

    // Request new asset price data
    function requestAssetPrice(
        string memory source, 
        uint64 subscriptionId,
        uint32 gasLimit,
        bytes32 donID
    ) public {
        // Verify source integrity using its hash
        if (keccak256(abi.encodePacked(source)) != sourceHash) {
            revert InvalidSource();
        }
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);
        s_lastRequestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donID);
    }

    // Fulfill callback to update contract state
    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory error) internal override {
        if (requestId != s_lastRequestId) {
            revert UnexpectedRequestID(requestId);
        }
        lastResponse = response;
        lastError = error;
        assetPrice = abi.decode(response, (uint256));
        lastUpdated = block.timestamp;
        emit AssetPriceUpdated(assetPrice, block.timestamp);
    }

    // Update the source hash
    function updateSourceHash(bytes32 newSourceHash) external onlyOwner {
        sourceHash = newSourceHash;
        emit SourceHashUpdated(newSourceHash);
    }

    // Update the asset symbol
    function updateAssetSymbol(string memory newAssetSymbol) external onlyOwner {
        assetSymbol = newAssetSymbol;
        emit AssetSymbolUpdated(newAssetSymbol);
    }
}
