// SPDX-License-Identifier: GPL-3.0-or-later
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IAssetPool} from "./IAssetPool.sol";
import {IXToken} from "./IXToken.sol";
import {IPoolLiquidityManager} from "./IPoolLiquidityManager.sol";
import {IAssetOracle} from "./IAssetOracle.sol";
import {IPoolCycleManager} from "./IPoolCycleManager.sol";
import {IPoolStrategy} from "./IPoolStrategy.sol";

/**
 * @title IAssetPoolWithPoolStorage
 * @notice Extended interface for the AssetPool contract that includes access to PoolStorage variables
 * @dev Use this interface when needing access to both AssetPool operations and storage variables
 */
interface IAssetPoolWithPoolStorage is IAssetPool {
    // --------------------------------------------------------------------------------
    //                     POOL STORAGE VARIABLES
    // --------------------------------------------------------------------------------

    /**
     * @notice Reserve to asset decimal factor for conversion calculations
     */
    function reserveToAssetDecimalFactor() external view returns (uint256);

    // --------------------------------------------------------------------------------
    //                           CONTRACT REFERENCES
    // --------------------------------------------------------------------------------

    /**
     * @notice Returns the reserve token used for collateral (e.g., USDC)
     */
    function reserveToken() external view returns (IERC20Metadata);

    /**
     * @notice Returns the asset token representing the underlying asset
     */
    function assetToken() external view returns (IXToken);

    /**
     * @notice Returns the oracle providing asset price information
     */
    function assetOracle() external view returns (IAssetOracle);

    /**
     * @notice Returns the asset pool contract for user positions
     */
    function assetPool() external view returns (IAssetPool);

    /**
     * @notice Returns the pool liquidity manager contract
     */
    function poolLiquidityManager() external view returns (IPoolLiquidityManager);

    /**
     * @notice Returns the pool cycle manager contract
     */
    function poolCycleManager() external view returns (IPoolCycleManager);

    /**
     * @notice Returns the pool strategy contract
     */
    function poolStrategy() external view returns (IPoolStrategy);

}