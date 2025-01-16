// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "../interfaces/ILPRegistry.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title LPRegistry
 * @dev Implementation of the ILPRegistry interface.
 *      Manages the registration of liquidity providers (LPs), pools, and their associated liquidity.
 *      Restricted to owner-controlled operations for pool and LP management.
 */
contract LPRegistry is ILPRegistry, Ownable {
    // Mapping to track valid pools
    mapping(address => bool) public validPools;
    
    // Nested mapping to track registered LPs for each pool
    mapping(address => mapping(address => bool)) public poolLPs;
    
    // Tracks the number of LPs registered for each pool
    mapping(address => uint256) public poolLPCount;

    // Mapping to store liquidity amounts per LP for each pool
    mapping(address => mapping(address => uint256)) public lpLiquidityAmount;
    
    // Tracks total liquidity for each pool
    mapping(address => uint256) public totalLPLiquidity;

    /**
     * @dev Initializes the contract, setting the deployer as the initial owner.
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Modifier to ensure a pool is valid.
     * @param pool The address of the pool to check.
     */
    modifier onlyValidPool(address pool) {
        if (!validPools[pool]) revert PoolNotFound();
        _;
    }

    /**
     * @dev Modifier to ensure an LP is registered for a given pool.
     * @param pool The address of the pool.
     * @param lp The address of the LP.
     */
    modifier onlyRegisteredLP(address pool, address lp) {
        if (!poolLPs[pool][lp]) revert NotRegistered();
        _;
    }

    /**
     * @notice Adds a new pool to the registry.
     * @param pool The address of the pool to add.
     * @dev Only callable by the contract owner.
     */
    function addPool(address pool) external onlyOwner {
        if (validPools[pool]) revert AlreadyRegistered();
        validPools[pool] = true;
        emit PoolAdded(pool);
    }

    /**
     * @notice Removes a pool from the registry.
     * @param pool The address of the pool to remove.
     * @dev Only callable by the contract owner. Pool must have no active liquidity.
     */
    function removePool(address pool) external onlyOwner {
        if (!validPools[pool]) revert PoolNotFound();
        if (totalLPLiquidity[pool] > 0) revert("Pool has active liquidity");
        validPools[pool] = false;
        emit PoolRemoved(pool);
    }

    /**
     * @notice Registers an LP for a pool with an initial liquidity amount.
     * @param pool The address of the pool.
     * @param lp The address of the LP.
     * @param liquidityAmount The initial liquidity amount.
     * @dev Only callable by the contract owner. Pool must be valid.
     */
    function registerLP(address pool, address lp, uint256 liquidityAmount) 
        external 
        onlyOwner 
        onlyValidPool(pool) 
    {
        if (poolLPs[pool][lp]) revert AlreadyRegistered();
        if (liquidityAmount == 0) revert InvalidAmount();
        
        poolLPs[pool][lp] = true;
        poolLPCount[pool]++;
        lpLiquidityAmount[pool][lp] = liquidityAmount;
        totalLPLiquidity[pool] += liquidityAmount;
        
        emit LPRegistered(pool, lp, liquidityAmount);
    }

    /**
     * @notice Removes an LP from a pool.
     * @param pool The address of the pool.
     * @param lp The address of the LP.
     * @dev Only callable by the contract owner. LP must have no active liquidity.
     */
    function removeLP(address pool, address lp) 
        external 
        onlyOwner 
        onlyValidPool(pool) 
        onlyRegisteredLP(pool, lp) 
    {
        if (lpLiquidityAmount[pool][lp] > 0) revert("LP has active liquidity");
        
        poolLPs[pool][lp] = false;
        poolLPCount[pool]--;
        emit LPRemoved(pool, lp);
    }

    /**
     * @notice Increases the liquidity for an LP in a pool.
     * @param pool The address of the pool.
     * @param amount The amount of liquidity to add.
     * @dev Only callable by the LP itself.
     */
    function increaseLiquidity(address pool, uint256 amount) 
        external 
        onlyValidPool(pool) 
        onlyRegisteredLP(pool, msg.sender) 
    {
        if (amount == 0) revert InvalidAmount();
        
        lpLiquidityAmount[pool][msg.sender] += amount;
        totalLPLiquidity[pool] += amount;
        
        emit LiquidityIncreased(pool, msg.sender, amount);
    }

    /**
     * @notice Decreases the liquidity for an LP in a pool.
     * @param pool The address of the pool.
     * @param amount The amount of liquidity to remove.
     * @dev Only callable by the LP itself. Cannot remove more liquidity than available.
     */
    function decreaseLiquidity(address pool, uint256 amount) 
        external 
        onlyValidPool(pool) 
        onlyRegisteredLP(pool, msg.sender) 
    {
        if (amount == 0) revert InvalidAmount();
        if (amount > lpLiquidityAmount[pool][msg.sender]) revert InsufficientLiquidity();
        
        lpLiquidityAmount[pool][msg.sender] -= amount;
        totalLPLiquidity[pool] -= amount;
        
        emit LiquidityDecreased(pool, msg.sender, amount);
    }

    /**
     * @notice Checks if an address is a registered LP for a pool.
     * @param pool The address of the pool.
     * @param lp The address of the LP.
     * @return True if the address is a registered LP for the pool, false otherwise.
     */
    function isLP(address pool, address lp) external view returns (bool) {
        return poolLPs[pool][lp];
    }

    /**
     * @notice Gets the number of LPs registered for a pool.
     * @param pool The address of the pool.
     * @return The number of registered LPs.
     */
    function getLPCount(address pool) external view returns (uint256) {
        return poolLPCount[pool];
    }

    /**
     * @notice Checks if a pool is valid.
     * @param pool The address of the pool.
     * @return True if the pool is valid, false otherwise.
     */
    function isValidPool(address pool) external view returns (bool) {
        return validPools[pool];
    }

    /**
     * @notice Gets the liquidity amount for an LP in a pool.
     * @param pool The address of the pool.
     * @param lp The address of the LP.
     * @return The liquidity amount.
     */
    function getLPLiquidity(address pool, address lp) external view returns (uint256) {
        return lpLiquidityAmount[pool][lp];
    }

    /**
     * @notice Gets the total liquidity for a pool.
     * @param pool The address of the pool.
     * @return The total liquidity amount.
     */
    function getTotalLPLiquidity(address pool) external view returns (uint256) {
        return totalLPLiquidity[pool];
    }
}