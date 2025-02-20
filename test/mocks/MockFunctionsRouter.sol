// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {FunctionsClient} from "@chainlink/contracts/v0.8/functions/v1_0_0/FunctionsClient.sol";

/**
 * @title MockFunctionsRouter
 * @notice Mock implementation of the Chainlink Functions Router for testing
 */
contract MockFunctionsRouter {
    bytes32 private nextRequestId;
    
    event RequestSent(bytes32 indexed id, uint64 subscriptionId, bytes data, uint32 gasLimit, bytes32 donId);

    /**
     * @notice Sets the next request ID to be returned
     * @param requestId The ID to return for the next request
     */
    function setNextRequestId(bytes32 requestId) external {
        nextRequestId = requestId;
    }

    /**
     * @notice Mock implementation of the Chainlink Functions sendRequest method
     * @param subscriptionId The subscription ID
     * @param data The CBOR encoded request data
     * @param gasLimit The gas limit for callback
     * @param donId The DON ID
     * @return requestId The mocked request ID
     */
    function sendRequest(
        uint64 subscriptionId,
        bytes calldata data,
        uint32 gasLimit,
        bytes32 donId
    ) external returns (bytes32) {
        emit RequestSent(nextRequestId, subscriptionId, data, gasLimit, donId);
        return nextRequestId;
    }

    /**
     * @notice Simulate fulfilling a Functions request by calling handleOracleFulfillment
     * @param client The FunctionsClient contract to call
     * @param requestId The ID of the request being fulfilled
     * @param response The response data
     * @param err Any error message
     */
    function fulfillRequest(
        FunctionsClient client,
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) external {
        client.handleOracleFulfillment(requestId, response, err);
    }
}