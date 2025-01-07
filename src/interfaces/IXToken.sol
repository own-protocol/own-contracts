// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.20;

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IScaledBalanceToken} from './IScaledBalanceToken.sol';

interface IXToken is IERC20, IScaledBalanceToken {
  /**
   * @dev Emitted after the mint action
   * @param from The address performing the mint
   * @param value The amount being
   **/
  event Mint(address indexed from, uint256 value);

  /**
   * @dev Mints `amount` xTokens to `user`
   * @param user The address receiving the minted tokens
   * @param amount The amount of tokens getting minted
   */
  function mint(
    address user,
    uint256 amount
  ) external;

  /**
   * @dev Emitted after xTokens are burned
   * @param user The owner of the xTokens, getting them burned
   * @param value The amount being burned
   **/
  event Burn(address indexed user, uint256 value);

  /**
   * @dev Emitted during the transfer action
   * @param from The user whose tokens are being transferred
   * @param to The recipient
   * @param value The amount being transferred
   **/
  event xTokenTransfer(address indexed from, address indexed to, uint256 value);

  /**
   * @dev Burns xTokens from `user` and sends the equivalent amount of underlying to `receiverOfUnderlying`
   * @param user The owner of the xTokens, getting them burned
   * @param amount The amount being burned
   **/
  function burn(
    address user,
    uint256 amount
  ) external;


  /**
   * @dev Returns the address of the underlying asset of this xToken.
   **/
  function ASSET_ORACLE_ADDRESS() external view returns (address);
}