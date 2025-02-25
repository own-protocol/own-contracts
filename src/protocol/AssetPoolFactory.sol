// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import 'openzeppelin-contracts/contracts/access/Ownable.sol';
import 'openzeppelin-contracts/contracts/proxy/Clones.sol';
import {IAssetPoolFactory} from '../interfaces/IAssetPoolFactory.sol';
import {AssetPool} from "../protocol/AssetPool.sol";
import {LPLiquidityManager} from '../protocol/LPLiquidityManager.sol';


/**
 * @title PoolFactory
 * @dev Implementation of the IAssetPoolFactory interface.
 * Responsible for creating and registering asset pools for liquidity provisioning.
 */
contract AssetPoolFactory is IAssetPoolFactory, Ownable {
    /// @notice Address to the LP liquidity manager contract.
    address public immutable lpLiquidityManager;
    /// @notice Address of the asset pool contract.
    address public immutable assetPool;

    /**
     * @dev Constructor to initialize the PoolFactory contract.
     * @param _lpLiquidityManager Address of the LP Registry contract.
     * Reverts if the address is zero.
     */
    constructor(address _lpLiquidityManager, address _assetPool) Ownable(msg.sender) {
        if (lpLiquidityManager == address(0)) revert ZeroAddress();
        if (assetPool == address(0)) revert ZeroAddress();
        lpLiquidityManager = _lpLiquidityManager;
        assetPool = _assetPool;
    }

    /**
     * @dev Creates a new asset pool with the given parameters.
     * Only callable by the owner of the contract.
     * Reverts if:
     * - Any address parameter is zero.
     * - `cycleLength` is zero.
     * - `rebalancingLength` is greater than or equal to `cycleLength`.
     * 
     * @param depositToken Address of the token used for deposits.
     * @param assetName Name of the token representing the asset.
     * @param assetSymbol Symbol of the token representing the asset.
     * @param oracle Address of the oracle providing asset price feeds.
     * @param cycleLength Length of each investment cycle in seconds.
     * @param rebalanceLength Length of the rebalancing period within a cycle in seconds.
     * @return address The address of the newly created asset pool.
     */
    function createPool(
        address depositToken,
        string memory assetName,
        string memory assetSymbol,
        address oracle,
        uint256 cycleLength,
        uint256 rebalanceLength
    ) external returns (address) {
        if (
            depositToken == address(0) ||
            oracle == address(0) ||
            cycleLength == 0 ||
            rebalanceLength >= cycleLength
        ) revert InvalidParams();

        address owner = owner();

        // Clones a new AssetPool contract instance.
        address pool = Clones.clone(assetPool);
        // Clones a new LP liquidity manager contract instance.
        address lpManager = Clones.clone(lpLiquidityManager);

        AssetPool(pool).initialize(
            depositToken,
            assetName,
            assetSymbol,
            oracle,
            lpManager,
            cycleLength,
            rebalanceLength,
            owner
        );

        LPLiquidityManager(lpManager).initialize(pool, oracle, depositToken, owner);

        // Emit the AssetPoolCreated event to notify listeners.
        emit AssetPoolCreated(
            address(pool),
            assetSymbol,
            depositToken,
            oracle,
            cycleLength,
            rebalanceLength
        );

        return address(pool);
    }

}
