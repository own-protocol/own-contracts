// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.20;

import {IAssetPool} from './IAssetPool.sol';

/**
 * @title IInitializableXToken
 * @notice Interface for the initialize function on XToken
 * @author Own Protocol
 **/
interface IInitializableXToken {
  /**
   * @dev Emitted when an xToken is initialized
   * @param underlyingAsset The address of the underlying asset
   * @param pool The address of the associated asset pool
   * @param treasury The address of the treasury
   * @param incentivesController The address of the incentives controller for this xToken
   * @param xTokenDecimals the decimals of the underlying
   * @param xTokenName the name of the xToken
   * @param xTokenSymbol the symbol of the xToken
   * @param params A set of encoded parameters for additional initialization
   **/
  event Initialized(
    address indexed underlyingAsset,
    address indexed pool,
    address treasury,
    address incentivesController,
    uint8 xTokenDecimals,
    string xTokenName,
    string xTokenSymbol,
    bytes params
  );

  /**
   * @dev Initializes the xToken
   * @param pool The address of the asset pool where this xToken will be used
   * @param treasury The address of the Aave treasury, receiving the fees on this xToken
   * @param underlyingAsset The address of the underlying asset of this xToken
   * @param xTokenDecimals The decimals of the xToken, same as the underlying asset's
   * @param xTokenName The name of the xToken
   * @param xTokenSymbol The symbol of the xToken
   */
  function initialize(
    IAssetPool pool,
    address treasury,
    address underlyingAsset,
    uint8 xTokenDecimals,
    string calldata xTokenName,
    string calldata xTokenSymbol,
    bytes calldata params
  ) external;
}