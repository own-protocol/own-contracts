// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import 'openzeppelin-contracts/contracts/access/Ownable.sol';
import 'openzeppelin-contracts/contracts/proxy/Clones.sol';
import {IAssetPoolFactory} from '../interfaces/IAssetPoolFactory.sol';
import {AssetPool} from "../protocol/AssetPool.sol";
import {PoolLiquidityManager} from '../protocol/PoolLiquidityManager.sol';
import {PoolCycleManager} from '../protocol/PoolCycleManager.sol';
import {IXToken} from '../interfaces/IXToken.sol';


/**
 * @title PoolFactory
 * @dev Implementation of the IAssetPoolFactory interface.
 * Responsible for creating and registering asset pools for liquidity provisioning.
 */
contract AssetPoolFactory is IAssetPoolFactory, Ownable {
    /// @notice Address of the asset pool contract.
    address public assetPool;
    /// @notice Address of the pool cycle manager contract.
    address public poolCycleManager;
    /// @notice Address to the pool liquidity manager contract.
    address public poolLiquidityManager;

    /**
     * @dev Constructor to initialize the PoolFactory contract.
     * @param _assetPool Address of the AssetPool contract.
     * @param _poolCycleManager Address of the Pool Cycle Manager contract.
     * @param _poolLiquidityManager Address of the LP Registry contract.
     */
    constructor(address _assetPool, address _poolCycleManager, address _poolLiquidityManager) Ownable(msg.sender) {
        if (_assetPool == address(0)) revert ZeroAddress();
        if (_poolCycleManager == address(0)) revert ZeroAddress();
        if (_poolLiquidityManager == address(0)) revert ZeroAddress();

        assetPool = _assetPool;
        poolCycleManager = _poolCycleManager;
        poolLiquidityManager = _poolLiquidityManager;
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
     * @param assetSymbol Symbol of the token representing the asset.
     * @param oracle Address of the oracle providing asset price feeds.
     * @param poolStrategy Address of the pool strategy contract.
     * @param cycleLength Length of each investment cycle in seconds.
     * @param rebalanceLength Length of the rebalancing period within a cycle in seconds.
     * @return address The address of the newly created asset pool.
     */
    function createPool(
        address depositToken,
        string memory assetSymbol,
        address oracle,
        address poolStrategy,
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
        // Clones a new pool cycle manager contract instance.
        address cycleManager = Clones.clone(poolCycleManager);
        // Clones a new pool liquidity manager contract instance.
        address liquidityManager = Clones.clone(poolLiquidityManager);

        AssetPool(pool).initialize(
            depositToken,
            assetSymbol,
            oracle,
            cycleManager,
            liquidityManager,
            poolStrategy,
            owner
        );

        IXToken assetToken = AssetPool(pool).assetToken();

        PoolCycleManager(cycleManager).initialize(
            depositToken,
            address(assetToken),
            oracle,
            pool,
            liquidityManager,
            poolStrategy,
            cycleLength,
            rebalanceLength
        );

        PoolLiquidityManager(liquidityManager).initialize(
            depositToken, 
            address(assetToken), 
            oracle, 
            pool, 
            cycleManager, 
            poolStrategy,
            owner
        );

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
