// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

interface ILPRegistry {
    event LPRegistered(address indexed pool, address indexed lp, uint256 liquidityAmount);
    event LPRemoved(address indexed pool, address indexed lp);
    event PoolAdded(address indexed pool);
    event PoolRemoved(address indexed pool);
    event LiquidityIncreased(address indexed pool, address indexed lp, uint256 amount);
    event LiquidityDecreased(address indexed pool, address indexed lp, uint256 amount);

    error NotAuthorized();
    error PoolNotFound();
    error AlreadyRegistered();
    error NotRegistered();
    error InsufficientLiquidity();
    error InvalidAmount();

    function registerLP(address pool, address lp, uint256 liquidityAmount) external;
    function removeLP(address pool, address lp) external;
    function addPool(address pool) external;
    function removePool(address pool) external;
    function increaseLiquidity(address pool, uint256 amount) external;
    function decreaseLiquidity(address pool, uint256 amount) external;
    function isLP(address pool, address lp) external view returns (bool);
    function getLPCount(address pool) external view returns (uint256);
    function isValidPool(address pool) external view returns (bool);
    function getLPLiquidity(address pool, address lp) external view returns (uint256);
    function getTotalLPLiquidity(address pool) external view returns (uint256);
}