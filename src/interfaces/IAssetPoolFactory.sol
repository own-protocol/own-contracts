// SPDX-License-Identifier: GPL-3.0-or-later
// author: bhargavaparoksham

pragma solidity ^0.8.20;

/**
 * @title IPoolFactory
 * @dev Interface defining the structure of the PoolFactory contract.
 * Responsible for creating and managing asset pools for liquidity provisioning.
 */
interface IAssetPoolFactory {
    /**
     * @dev Emitted when a new asset pool is created.
     * @param pool Address of the newly created pool.
     * @param assetSymbol Symbol representing the asset.
     * @param depositToken Address of the token used for deposits.
     * @param oracle Address of the oracle used for asset price feeds.
     * @param cycleLength Duration of a single investment cycle in seconds.
     * @param rebalanceLength Duration of the rebalancing period within a cycle in seconds.
     */
    event AssetPoolCreated(
        address indexed pool,
        string assetSymbol,
        address depositToken,
        address oracle,
        uint256 cycleLength,
        uint256 rebalanceLength
    );

    /**
     * @dev Reverts when provided parameters are invalid.
     */
    error InvalidParams();

    /**
     * @dev Reverts when a zero address is provided where a valid address is required.
     */
    error ZeroAddress();

    /**
     * @return address The address of the asset pool contract.
     */
    function assetPool() external view returns (address);

    /**
     * @return address The address of the pool cycle manager contract.
     */
    function poolCycleManager() external view returns (address);

    /**
     * @return address The address of the pool liquidity manager contract.
     */
    function poolLiquidityManager() external view returns (address);

    /**
     * @dev Creates a new asset pool with the specified parameters.
     * @param depositToken Address of the token used for deposits.
     * @param assetSymbol Symbol of the token representing the asset.
     * @param oracle Address of the oracle providing asset price feeds.
     * @param interestRateStrategy Address of the interest rate strategy contract.
     * @param cycleLength Length of each investment cycle in seconds.
     * @param rebalanceLength Rebalancing period length within a cycle in seconds.
     * @return address The address of the newly created asset pool.
     */
    function createPool(
        address depositToken,
        string memory assetSymbol,
        address oracle,
        address interestRateStrategy,
        uint256 cycleLength,
        uint256 rebalanceLength
    ) external returns (address);

}