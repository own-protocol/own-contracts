// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import 'openzeppelin-contracts/contracts/access/Ownable.sol';
import 'openzeppelin-contracts/contracts/proxy/Clones.sol';
import {IAssetPoolFactory} from '../interfaces/IAssetPoolFactory.sol';
import {IProtocolRegistry} from '../interfaces/IProtocolRegistry.sol';
import {AssetPool} from "../protocol/AssetPool.sol";
import {PoolLiquidityManager} from '../protocol/PoolLiquidityManager.sol';
import {PoolCycleManager} from '../protocol/PoolCycleManager.sol';
import {AssetOracle} from '../protocol/AssetOracle.sol';
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
    /// @notice Address of the protocol registry contract.
    address public protocolRegistry;

    /**
     * @dev Constructor to initialize the PoolFactory contract.
     * @param _assetPool Address of the AssetPool contract.
     * @param _poolCycleManager Address of the Pool Cycle Manager contract.
     * @param _poolLiquidityManager Address of the LP Registry contract.
     * @param _protocolRegistry Address of the Protocol Registry contract.
     */
    constructor(
        address _assetPool,
        address _poolCycleManager, 
        address _poolLiquidityManager,
        address _protocolRegistry
    ) Ownable(msg.sender) {
        if (_assetPool == address(0)) revert ZeroAddress();
        if (_poolCycleManager == address(0)) revert ZeroAddress();
        if (_poolLiquidityManager == address(0)) revert ZeroAddress();
        if (_protocolRegistry == address(0)) revert ZeroAddress();

        assetPool = _assetPool;
        poolCycleManager = _poolCycleManager;
        poolLiquidityManager = _poolLiquidityManager;
        protocolRegistry = _protocolRegistry;
    }

    /**
     * @dev Updates the protocol registry address
     * @param _protocolRegistry Address of the new protocol registry
     */
    function updateRegistry(address _protocolRegistry) external onlyOwner {
        if (_protocolRegistry == address(0)) revert ZeroAddress();
        
        address oldRegistry = protocolRegistry;
        protocolRegistry = _protocolRegistry;
        
        emit RegistryUpdated(oldRegistry, _protocolRegistry);
    }

    /**
     * @dev Creates a new asset pool with the given parameters.
     * Reverts if:
     * - Any address parameter is zero.
     * - The strategy is not verified in the registry.
     * 
     * @param depositToken Address of the token used for deposits.
     * @param assetSymbol Symbol of the token representing the asset.
     * @param oracle Address of the oracle providing asset price feeds.
     * @param poolStrategy Address of the pool strategy contract.
     * @return address The address of the newly created asset pool.
     */
    function createPool(
        address depositToken,
        string memory assetSymbol,
        address oracle,
        address poolStrategy
    ) external returns (address) {
        if (
            depositToken == address(0) ||
            oracle == address(0) ||
            poolStrategy == address(0) ||
            bytes(assetSymbol).length == 0
        ) revert InvalidParams();

        // Verify that the strategy is verified in the registry
        IProtocolRegistry registry = IProtocolRegistry(protocolRegistry);
        if (!registry.isStrategyVerified(poolStrategy)) revert NotVerified();
        // Verify that the oracle was created by the factory
        if (AssetOracle(oracle).owner() != owner()) revert NotVerified();

        // Clones a new AssetPool contract instance.
        address pool = Clones.clone(assetPool);
        // Clones a new pool cycle manager contract instance.
        address cycleManager = Clones.clone(poolCycleManager);
        // Clones a new pool liquidity manager contract instance.
        address liquidityManager = Clones.clone(poolLiquidityManager);

        address owner = owner();

        AssetPool(pool).initialize(
            depositToken,
            assetSymbol,
            oracle,
            pool,
            cycleManager,
            liquidityManager,
            poolStrategy
        );

        IXToken assetToken = AssetPool(pool).assetToken();

        PoolCycleManager(cycleManager).initialize(
            depositToken,
            address(assetToken),
            oracle,
            pool,
            cycleManager,
            liquidityManager,
            poolStrategy,
            owner
        );

        PoolLiquidityManager(liquidityManager).initialize(
            depositToken, 
            address(assetToken), 
            oracle, 
            pool, 
            cycleManager, 
            liquidityManager,
            poolStrategy
        );

        // Emit the AssetPoolCreated event to notify listeners.
        emit AssetPoolCreated(
            address(pool),
            assetSymbol,
            depositToken,
            oracle
        );

        return address(pool);
    }


    /**
     * @dev Creates a new asset oracle with the given parameters.
     * Reverts if:
     * - Any address parameter is zero.
     * - The asset symbol is empty.
     * 
     * @param assetSymbol Symbol of the token representing the asset.
     * @param sourceHash Hash of the valid source code.
     * @param router Address of the Chainlink Functions router contract.
     * @return address The address of the newly created asset oracle.
     */
    function createOracle(
        string memory assetSymbol,
        bytes32 sourceHash,
        address router
    ) external returns (address) {
        if (bytes(assetSymbol).length == 0 || router == address(0)) revert InvalidParams();
        
        // Create a new AssetOracle instance
        AssetOracle oracle = new AssetOracle(router, assetSymbol, sourceHash, owner());
        
        // Emit an event for oracle creation
        emit AssetOracleCreated(address(oracle), assetSymbol);
        
        return address(oracle);
    }

}
