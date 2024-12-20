// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.20;

import {IAssetPoolAddressesProvider} from './IAssetPoolAddressesProvider.sol';

interface IAssetPool {
  /**
   * @dev Emitted on deposit()
   * @param user The address initiating the deposit
   * @param onBehalfOf The beneficiary of the deposit, receiving the aTokens
   * @param amount The amount deposited
   **/
  event Deposit(
    address user,
    address indexed onBehalfOf,
    uint256 amount
  );

  /**
   * @dev Emitted on withdraw()
   * @param user The address initiating the withdrawal, owner of xTokens
   * @param to Address that will receive the underlying
   * @param amount The amount to be withdrawn
   **/
  event Withdraw(address indexed user, address indexed to, uint256 amount);


  /**
   * @dev Emitted when the pause is triggered.
   */
  event Paused();

  /**
   * @dev Emitted when the pause is lifted.
   */
  event Unpaused();

  /**
   * @dev Deposits an `amount` of stable asset, receiving in return overlying xTokens.
   * - E.g. User deposits 100 USDC and gets in return 100 xAsset
   * @param amount The amount to be deposited
   * @param onBehalfOf The address that will receive the aTokens, same as msg.sender if the user
   *   wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
   *   is a different wallet
   **/
  function deposit(
    uint256 amount,
    address onBehalfOf
  ) external;

  /**
   * @dev Withdraws an `amount` of stable asset, burning the equivalent xTokens owned
   * E.g. User has 100 xAsset, calls withdraw() and receives 100 USDC, burning the 100 xAsset
   * @param amount The underlying amount to be withdrawn
   *   - Send the value type(uint256).max in order to withdraw the whole xToken balance
   * @param to Address that will receive the underlying, same as msg.sender if the user
   *   wants to receive it on his own wallet, or a different address if the beneficiary is a
   *   different wallet
   * @return The final amount withdrawn
   **/

  function withdraw(
    uint256 amount,
    address to
  ) external returns (uint256);

  function getAddressesProvider() external view returns (IAssetPoolAddressesProvider);

  function setPause(bool val) external;

  function paused() external view returns (bool);
}