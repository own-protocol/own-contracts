// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import 'openzeppelin-contracts/contracts/access/Ownable.sol';
import 'openzeppelin-contracts/contracts/proxy/Clones.sol';
import {ILPRegistry} from '../interfaces/ILPRegistry.sol';
import {IAssetPoolFactory} from '../interfaces/IAssetPoolFactory.sol';
import {AssetPoolImplementation} from "../protocol/AssetPoolImplementation.sol";


/**
 * @title PoolFactory
 * @dev Implementation of the IAssetPoolFactory interface.
 * Responsible for creating and registering asset pools for liquidity provisioning.
 */
contract AssetPoolFactory is IAssetPoolFactory, Ownable {
    /// @notice Reference to the LP Registry contract.
    ILPRegistry public lpRegistry;
    /// @notice Address of the asset pool implementation contract.
    address public immutable assetPoolImplementation;

    /**
     * @dev Constructor to initialize the PoolFactory contract.
     * @param _lpRegistry Address of the LP Registry contract.
     * Reverts if the address is zero.
     */
    constructor(address _lpRegistry, address _assetPoolImplementation) Ownable(msg.sender) {
        if (_lpRegistry == address(0)) revert ZeroAddress();
        lpRegistry = ILPRegistry(_lpRegistry);
        assetPoolImplementation = _assetPoolImplementation;
    }

    /**
     * @dev Creates a new asset pool with the given parameters.
     * Only callable by the owner of the contract.
     * Reverts if:
     * - Any address parameter is zero.
     * - `cyclePeriod` is zero.
     * - `rebalancingPeriod` is greater than or equal to `cyclePeriod`.
     * 
     * @param depositToken Address of the token used for deposits.
     * @param assetName Name of the token representing the asset.
     * @param assetSymbol Symbol of the token representing the asset.
     * @param oracle Address of the oracle providing asset price feeds.
     * @param cyclePeriod Length of each investment cycle in seconds.
     * @param rebalancingPeriod Length of the rebalancing period within a cycle in seconds.
     * @return address The address of the newly created asset pool.
     */
    function createPool(
        address depositToken,
        string memory assetName,
        string memory assetSymbol,
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

        // Clones a new AssetPool contract instance.
        address pool = Clones.clone(assetPoolImplementation);
        AssetPoolImplementation(pool).initialize(
            depositToken,
            assetName,
            assetSymbol,
            oracle,
            address(lpRegistry),
            cyclePeriod,
            rebalancingPeriod,
            msg.sender
        );

        // Emit the AssetPoolCreated event to notify listeners.
        emit AssetPoolCreated(
            address(pool),
            assetSymbol,
            depositToken,
            oracle,
            cyclePeriod,
            rebalancingPeriod
        );

        return address(pool);
    }

    /**
    * @dev Updates the LP Registry contract address.
    * Only callable by the owner of the contract.
    * Reverts if the new address is zero.
    * 
    * @param newLPRegistry Address of the new LP Registry contract.
    */
    function updateLPRegistry(address newLPRegistry) external onlyOwner {
        if (newLPRegistry == address(0)) revert ZeroAddress();
        address oldRegistry = address(lpRegistry);
        lpRegistry = ILPRegistry(newLPRegistry);
        emit LPRegistryUpdated(oldRegistry, newLPRegistry);
    }
}
