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
     */
    event AssetPoolCreated(
        address indexed pool,
        string assetSymbol,
        address depositToken,
        address oracle
    );

    /**
     * @dev Emitted when a new asset oracle is created.
     * @param oracle Address of the newly created oracle.
     * @param assetSymbol Symbol representing the asset.
     */
    event AssetOracleCreated(
        address indexed oracle,
        string assetSymbol
    );

    /**
     * @dev Emitted when the protocol registry is updated
     * @param oldRegistry Address of the old registry
     * @param newRegistry Address of the new registry
     */
    event RegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    /**
     * @dev Reverts when provided parameters are invalid.
     */
    error InvalidParams();

    /**
     * @dev Reverts when a zero address is provided where a valid address is required.
     */
    error ZeroAddress();

    /**
     * @dev Reverts when a strategy or oracle is not verified in the registry
     */
    error NotVerified();

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
     * @return address The address of the protocol registry contract.
     */
    function protocolRegistry() external view returns (address);

    /**
     * @dev Updates the protocol registry address
     * @param _registry Address of the new protocol registry
     */
    function updateRegistry(address _registry) external;

    /**
     * @dev Creates a new asset pool with the specified parameters.
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
    ) external returns (address);

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
    ) external returns (address);

}