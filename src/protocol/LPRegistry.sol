// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "../interfaces/ILPRegistry.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract LPRegistry is ILPRegistry, Ownable {
    mapping(address => bool) public validPools;
    mapping(address => mapping(address => bool)) public poolLPs;
    mapping(address => uint256) public poolLPCount;

    constructor() Ownable(msg.sender) {}

    modifier onlyValidPool(address pool) {
        if (!validPools[pool]) revert PoolNotFound();
        _;
    }

    function addPool(address pool) external onlyOwner {
        if (validPools[pool]) revert AlreadyRegistered();
        validPools[pool] = true;
        emit PoolAdded(pool);
    }

    function removePool(address pool) external onlyOwner {
        if (!validPools[pool]) revert PoolNotFound();
        validPools[pool] = false;
        emit PoolRemoved(pool);
    }

    function registerLP(address pool, address lp) external onlyOwner onlyValidPool(pool) {
        if (poolLPs[pool][lp]) revert AlreadyRegistered();
        poolLPs[pool][lp] = true;
        poolLPCount[pool]++;
        emit LPRegistered(pool, lp);
    }

    function removeLP(address pool, address lp) external onlyOwner onlyValidPool(pool) {
        if (!poolLPs[pool][lp]) revert NotRegistered();
        poolLPs[pool][lp] = false;
        poolLPCount[pool]--;
        emit LPRemoved(pool, lp);
    }

    function isLP(address pool, address lp) external view returns (bool) {
        return poolLPs[pool][lp];
    }

    function getLPCount(address pool) external view returns (uint256) {
        return poolLPCount[pool];
    }

    function isValidPool(address pool) external view returns (bool) {
        return validPools[pool];
    }
}