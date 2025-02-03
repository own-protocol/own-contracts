// SPDX-License-Identifier: GPL-3.0-or-later
// author: bhargavaparoksham

pragma solidity ^0.8.20;

/**
 * @title ILPRegistry
 * @dev Interface for the Liquidity Provider (LP) Registry contract.
 *      This interface defines the events, errors, and function signatures
 *      for managing LPs, pools, and their associated liquidity.
 */
interface ILPRegistry {
    /**
     * @dev Emitted when a new LP is registered for a pool
     * @param pool The address of the pool where LP is registered
     * @param lp The address of the registered LP
     * @param liquidityAmount The initial liquidity amount provided by the LP
     */
    event LPRegistered(address indexed pool, address indexed lp, uint256 liquidityAmount);

    /**
     * @dev Emitted when an LP is removed from a pool
     * @param pool The address of the pool from which LP is removed
     * @param lp The address of the removed LP
     */
    event LPRemoved(address indexed pool, address indexed lp);

    /**
     * @dev Emitted when a new pool is added to the registry
     * @param pool The address of the newly added pool
     */
    event PoolAdded(address indexed pool);

    /**
     * @dev Emitted when a pool is removed from the registry
     * @param pool The address of the removed pool
     */
    event PoolRemoved(address indexed pool);

    /**
     * @dev Emitted when an LP increases their liquidity in a pool
     * @param pool The address of the pool where liquidity is increased
     * @param lp The address of the LP increasing liquidity
     * @param amount The amount of liquidity added
     */
    event LiquidityIncreased(address indexed pool, address indexed lp, uint256 amount);

    /**
     * @dev Emitted when an LP decreases their liquidity in a pool
     * @param pool The address of the pool where liquidity is decreased
     * @param lp The address of the LP decreasing liquidity
     * @param amount The amount of liquidity removed
     */
    event LiquidityDecreased(address indexed pool, address indexed lp, uint256 amount);

    /**
     * @dev Error thrown when a caller attempts an action they are not authorized to perform
     */
    error NotAuthorized();

    /**
     * @dev Error thrown when attempting to interact with a pool that is not registered
     */
    error PoolNotFound();

    /**
     * @dev Error thrown when attempting to register an LP or pool that is already registered
     */
    error AlreadyRegistered();

    /**
     * @dev Error thrown when attempting to interact with an LP that is not registered for a specific pool
     */
    error NotRegistered();

    /**
     * @dev Error thrown when attempting to decrease liquidity by an amount greater than available
     */
    error InsufficientLiquidity();

    /**
     * @dev Error thrown when attempting to operate with an invalid liquidity amount (e.g., zero)
     */
    error InvalidAmount();

    /**
     * @dev Registers a new LP for a specific pool with initial liquidity
     * @param pool The address of the pool where the LP will be registered
     * @param lp The address of the LP to register
     * @param liquidityAmount The initial amount of liquidity to be provided
     */
    function registerLP(address pool, address lp, uint256 liquidityAmount) external;

    /**
     * @dev Removes an LP from a specific pool
     * @param pool The address of the pool from which to remove the LP
     * @param lp The address of the LP to remove
     */
    function removeLP(address pool, address lp) external;

    /**
     * @dev Adds a new pool to the registry
     * @param pool The address of the pool to add
     */
    function addPool(address pool) external;

    /**
     * @dev Removes a pool from the registry
     * @param pool The address of the pool to remove
     */
    function removePool(address pool) external;

    /**
     * @dev Increases the liquidity amount for an LP in a specific pool
     * @param pool The address of the pool where liquidity will be increased
     * @param amount The amount of liquidity to add
     */
    function increaseLiquidity(address pool, uint256 amount) external;

    /**
     * @dev Decreases the liquidity amount for an LP in a specific pool
     * @param pool The address of the pool where liquidity will be decreased
     * @param amount The amount of liquidity to remove
     */
    function decreaseLiquidity(address pool, uint256 amount) external;

    /**
     * @dev Checks if an address is a registered LP for a specific pool
     * @param pool The address of the pool to check
     * @param lp The address to check
     * @return bool True if the address is a registered LP, false otherwise
     */
    function isLP(address pool, address lp) external view returns (bool);

    /**
     * @dev Returns the number of LPs registered for a specific pool
     * @param pool The address of the pool to query
     * @return uint256 The number of registered LPs
     */
    function getLPCount(address pool) external view returns (uint256);

    /**
     * @dev Checks if a pool is registered in the registry
     * @param pool The address of the pool to check
     * @return bool True if the pool is registered, false otherwise
     */
    function isValidPool(address pool) external view returns (bool);

    /**
     * @dev Returns the current liquidity amount for an LP in a specific pool
     * @param pool The address of the pool to query
     * @param lp The address of the LP
     * @return uint256 The current liquidity amount
     */
    function getLPLiquidity(address pool, address lp) external view returns (uint256);

    /**
     * @dev Returns the total liquidity amount for a specific pool
     * @param pool The address of the pool to query
     * @return uint256 The total liquidity amount
     */
    function getTotalLPLiquidity(address pool) external view returns (uint256);
}