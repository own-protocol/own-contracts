// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "../interfaces/ILPRegistry.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract LPRegistry is ILPRegistry, Ownable {
    mapping(address => bool) public validPools;
    mapping(address => mapping(address => bool)) public poolLPs;
    mapping(address => uint256) public poolLPCount;
    
    // State variables for liquidity amounts
    mapping(address => mapping(address => uint256)) public lpLiquidityAmount;
    mapping(address => uint256) public totalLPLiquidity;

    constructor() Ownable(msg.sender) {}

    modifier onlyValidPool(address pool) {
        if (!validPools[pool]) revert PoolNotFound();
        _;
    }

    modifier onlyRegisteredLP(address pool, address lp) {
        if (!poolLPs[pool][lp]) revert NotRegistered();
        _;
    }

    function addPool(address pool) external onlyOwner {
        if (validPools[pool]) revert AlreadyRegistered();
        validPools[pool] = true;
        emit PoolAdded(pool);
    }

    function removePool(address pool) external onlyOwner {
        if (!validPools[pool]) revert PoolNotFound();
        // Only allow removal if no liquidity remains
        if (totalLPLiquidity[pool] > 0) revert("Pool has active liquidity");
        validPools[pool] = false;
        emit PoolRemoved(pool);
    }

    function registerLP(address pool, address lp, uint256 liquidityAmount) external onlyOwner onlyValidPool(pool) {
        if (poolLPs[pool][lp]) revert AlreadyRegistered();
        if (liquidityAmount == 0) revert InvalidAmount();
        
        poolLPs[pool][lp] = true;
        poolLPCount[pool]++;
        lpLiquidityAmount[pool][lp] = liquidityAmount;
        totalLPLiquidity[pool] += liquidityAmount;
        
        emit LPRegistered(pool, lp, liquidityAmount);
    }

    function removeLP(address pool, address lp) external onlyOwner onlyValidPool(pool) onlyRegisteredLP(pool, lp) {
        // Only allow removal if no liquidity remains
        if (lpLiquidityAmount[pool][lp] > 0) revert("LP has active liquidity");
        
        poolLPs[pool][lp] = false;
        poolLPCount[pool]--;
        emit LPRemoved(pool, lp);
    }

    function increaseLiquidity(address pool, uint256 amount) external onlyValidPool(pool) onlyRegisteredLP(pool, msg.sender) {
        if (amount == 0) revert InvalidAmount();
        
        lpLiquidityAmount[pool][msg.sender] += amount;
        totalLPLiquidity[pool] += amount;
        
        emit LiquidityIncreased(pool, msg.sender, lpLiquidityAmount[pool][msg.sender]);
    }

    function decreaseLiquidity(address pool, uint256 amount) external onlyValidPool(pool) onlyRegisteredLP(pool, msg.sender) {
        if (amount == 0) revert InvalidAmount();
        if (amount > lpLiquidityAmount[pool][msg.sender]) revert InsufficientLiquidity();
        
        lpLiquidityAmount[pool][msg.sender] -= amount;
        totalLPLiquidity[pool] -= amount;
        
        emit LiquidityDecreased(pool, msg.sender, amount);
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

    function getLPLiquidity(address pool, address lp) external view returns (uint256) {
        return lpLiquidityAmount[pool][lp];
    }

    function getTotalLPLiquidity(address pool) external view returns (uint256) {
        return totalLPLiquidity[pool];
    }
}