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
    //                     POOL STORAGE CONSTANTS & VARIABLES
    // --------------------------------------------------------------------------------

    /**
     * @notice Precision factor for calculations
     */
    function PRECISION() external view returns (uint256);

    /**
     * @notice Basis points scaling factor (100% = 10000)
     */
    function BPS() external view returns (uint256);

    /**
     * @notice Seconds in a year, used for interest calculations
     */
    function SECONDS_PER_YEAR() external view returns (uint256);

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

    // --------------------------------------------------------------------------------
    //                            CONVERSION FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Converts asset amount to reserve amount based on the asset price
     * @param assetAmount The amount of asset to convert
     * @param price The price of the asset in reserve terms
     * @return Equivalent amount in reserve tokens
     */
    function convertAssetToReserve(uint256 assetAmount, uint256 price) external view returns (uint256);

    /**
     * @notice Converts reserve amount to asset amount based on the asset price
     * @param reserveAmount The amount of reserve to convert
     * @param price The price of the asset in reserve terms
     * @return Equivalent amount in asset tokens
     */
    function convertReserveToAsset(uint256 reserveAmount, uint256 price) external view returns (uint256);
}