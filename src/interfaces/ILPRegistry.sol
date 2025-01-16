// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

/**
 * @title ILPRegistry
 * @dev Interface for the Liquidity Provider (LP) Registry contract.
 *      This interface defines the events, errors, and function signatures
 *      for managing LPs, pools, and their associated liquidity.
 */
interface ILPRegistry {
    // Events
    event LPRegistered(address indexed pool, address indexed lp, uint256 liquidityAmount);
    event LPRemoved(address indexed pool, address indexed lp);
    event PoolAdded(address indexed pool);
    event PoolRemoved(address indexed pool);
    event LiquidityIncreased(address indexed pool, address indexed lp, uint256 amount);
    event LiquidityDecreased(address indexed pool, address indexed lp, uint256 amount);

    // Errors
    error NotAuthorized(); // Thrown when an unauthorized action is attempted.
    error PoolNotFound();  // Thrown when a pool is not found in the registry.
    error AlreadyRegistered(); // Thrown when an LP or pool is already registered.
    error NotRegistered(); // Thrown when an LP is not registered for a specific pool.
    error InsufficientLiquidity(); // Thrown when liquidity is insufficient for an operation.
    error InvalidAmount(); // Thrown when an invalid liquidity amount is provided.

    // Function signatures
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