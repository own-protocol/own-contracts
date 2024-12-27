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

    string public assetSymbol;  // Asset symbol (e.g., "TSLA")
    uint256 public assetPrice; // Price in cents
    uint256 public lastUpdated; // Timestamp of last update

    event AssetPriceUpdated(uint256 price, uint256 timestamp);
    error UnexpectedRequestID(bytes32 requestId);

    constructor(address router, string memory _assetSymbol)
        FunctionsClient(router)
        ConfirmedOwner(msg.sender)
    {
        assetSymbol = _assetSymbol;
    }

    // Request new asset price data
    function requestAssetPrice(
        string memory source, 
        uint64 subscriptionId,
        uint32 gasLimit,
        bytes32 donID
    ) public onlyOwner {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);
        string[] memory args = new string[](1);
        args[0] = assetSymbol;
        req.setArgs(args);
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
}
