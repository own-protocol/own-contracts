// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

interface ILPRegistry {
    event LPRegistered(address indexed pool, address indexed lp);
    event LPRemoved(address indexed pool, address indexed lp);
    event PoolAdded(address indexed pool);
    event PoolRemoved(address indexed pool);

    error NotAuthorized();
    error PoolNotFound();
    error AlreadyRegistered();
    error NotRegistered();

    function registerLP(address pool, address lp) external;
    function removeLP(address pool, address lp) external;
    function addPool(address pool) external;
    function removePool(address pool) external;
    function isLP(address pool, address lp) external view returns (bool);
    function getLPCount(address pool) external view returns (uint256);
    function isValidPool(address pool) external view returns (bool);
}