// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import 'openzeppelin-contracts/contracts/access/Ownable.sol';
import {ILPRegistry} from '../interfaces/ILPRegistry.sol';
import {IPoolFactory} from '../interfaces/IAssetPoolFactory.sol';
import {AssetPool} from './AssetPool.sol';

/**
 * @title PoolFactory
 * @dev Implementation of the IPoolFactory interface.
 * Responsible for creating and registering asset pools for liquidity provisioning.
 */
contract PoolFactory is IPoolFactory, Ownable {
    /// @notice Reference to the LP Registry contract.
    ILPRegistry public immutable lpRegistry;

    /**
     * @dev Constructor to initialize the PoolFactory contract.
     * @param _lpRegistry Address of the LP Registry contract.
     * Reverts if the address is zero.
     */
    constructor(address _lpRegistry) Ownable(msg.sender) {
        if (_lpRegistry == address(0)) revert ZeroAddress();
        lpRegistry = ILPRegistry(_lpRegistry);
    }

    /**
     * @dev Creates a new asset pool with the given parameters.
     * Only callable by the owner of the contract.
     * Reverts if:
     * - Any address parameter is zero.
     * - `cyclePeriod` is zero.
     * - `rebalancingPeriod` is greater than or equal to `cyclePeriod`.
     * 
     * @param assetSymbol Symbol of the asset.
     * @param assetTokenName Name of the token representing the asset.
     * @param assetTokenSymbol Symbol of the token representing the asset.
     * @param depositToken Address of the token used for deposits.
     * @param oracle Address of the oracle providing asset price feeds.
     * @param cyclePeriod Length of each investment cycle in seconds.
     * @param rebalancingPeriod Length of the rebalancing period within a cycle in seconds.
     * @return address The address of the newly created asset pool.
     */
    function createPool(
        string memory assetSymbol,
        string memory assetTokenName,
        string memory assetTokenSymbol,
        address depositToken,
        address oracle,
        uint256 cyclePeriod,
        uint256 rebalancingPeriod
    ) external onlyOwner returns (address) {
        if (
            depositToken == address(0) ||
            oracle == address(0) ||
            cyclePeriod == 0 ||
            rebalancingPeriod >= cyclePeriod
        ) revert InvalidParams();

        // Deploy a new AssetPool contract instance.
        AssetPool pool = new AssetPool(
            depositToken,
            assetTokenName,
            assetTokenSymbol,
            oracle,
            address(lpRegistry),
            cyclePeriod,
            rebalancingPeriod,
            msg.sender
        );

        // Register the newly created pool in the LP Registry.
        lpRegistry.addPool(address(pool));

        // Emit the PoolCreated event to notify listeners.
        emit PoolCreated(
            address(pool),
            assetSymbol,
            depositToken,
            oracle,
            cyclePeriod,
            rebalancingPeriod
        );

        return address(pool);
    }
}
