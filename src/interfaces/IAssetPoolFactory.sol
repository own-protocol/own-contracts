// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import {ILPRegistry} from './ILPRegistry.sol';

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
     * @param rebalancingPeriod Duration of the rebalancing period within a cycle in seconds.
     */
    event AssetPoolCreated(
        address indexed pool,
        string assetSymbol,
        address depositToken,
        address oracle,
        uint256 cycleLength,
        uint256 rebalancingPeriod
    );

    /**
     * @dev Emitted when the LP Registry contract address is updated.
     * @param lpRegistry Address of the old LP Registry contract.
     * @param newLPRegistry Address of the new LP Registry contract.
     */
    event LPRegistryUpdated(address lpRegistry, address newLPRegistry);

    /**
     * @dev Reverts when provided parameters are invalid.
     */
    error InvalidParams();

    /**
     * @dev Reverts when a zero address is provided where a valid address is required.
     */
    error ZeroAddress();

    /**
     * @return ILPRegistry The address of the LP Registry contract.
     */
    function lpRegistry() external view returns (ILPRegistry);

    /**
     * @dev Creates a new asset pool with the specified parameters.
     * @param depositToken Address of the token used for deposits.
     * @param assetName Name of the token representing the asset.
     * @param assetSymbol Symbol of the token representing the asset.
     * @param oracle Address of the oracle providing asset price feeds.
     * @param cycleLength Length of each investment cycle in seconds.
     * @param rebalancingPeriod Rebalancing period length within a cycle in seconds.
     * @return address The address of the newly created asset pool.
     */
    function createPool(
        address depositToken,
        string memory assetName,
        string memory assetSymbol,
        address oracle,
        uint256 cycleLength,
        uint256 rebalancingPeriod
    ) external returns (address);

    /**
    * @dev Updates the LP Registry contract address.
    * Only callable by the owner of the contract.
    * Reverts if the new address is zero.
    * 
    * @param newLPRegistry Address of the new LP Registry contract.
    */
    function updateLPRegistry(address newLPRegistry) external;
}