// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

/**
 * @title MockFunctionsRouter
 * @notice Mock Chainlink Functions Router for testing
 */
contract MockFunctionsRouter {
    event RequestSent(bytes32 indexed requestId, uint64 subscriptionId);
    
    function sendRequest(
        uint64 subscriptionId,
        bytes calldata data,
        uint32 gasLimit,
        bytes32 donId
    ) external returns (bytes32) {
        bytes32 requestId = keccak256(abi.encode(subscriptionId, data, gasLimit, donId, block.timestamp));
        emit RequestSent(requestId, subscriptionId);
        return requestId;
    }
}