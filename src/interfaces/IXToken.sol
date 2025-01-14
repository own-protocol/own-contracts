// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC20Permit} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol';
import {IAssetOracle} from './IAssetOracle.sol';

interface IXToken is IERC20, IERC20Permit {
   /**
     * @dev Thrown when a caller is not the pool contract
     */
    error NotPool();

    /**
     * @dev Thrown when zero address is provided where it's not allowed
     */
    error ZeroAddress();

    /**
     * @dev Thrown when asset price is invalid (zero)
     */
    error InvalidPrice();

    /**
     * @dev Thrown when account has insufficient balance for an operation
     */
    error InsufficientBalance();

    /**
     * @dev Thrown when spender has insufficient allowance
     */
    error InsufficientAllowance();

    /**
     * @dev Emitted after the mint action
     * @param account The address receiving the minted tokens
     * @param value The amount being minted
     * @param price The price at which the tokens are minted
     **/
    event Mint(address indexed account, uint256 value, uint256 price);

    /**
     * @dev Emitted after xTokens are burned
     * @param account The owner of the xTokens, getting burned
     * @param value The amount being burned
     **/
    event Burn(address indexed account, uint256 value);

    /**
     * @dev Returns the scaled balance of the user. The scaled balance represents the user's balance
     * normalized by the underlying asset price, maintaining constant purchasing power.
     * @param user The user whose balance is calculated
     * @return The scaled balance of the user
     **/
    function scaledBalanceOf(address user) external view returns (uint256);

    /**
     * @dev Returns the scaled total supply of the token. Represents the total supply
     * normalized by the asset price.
     * @return The scaled total supply
     **/
    function scaledTotalSupply() external view returns (uint256);

    /**
     * @dev Returns the market value of a user's tokens.
     * @param user The user whose balance is calculated
     * @return The market value of a user's tokens
     **/
    function marketValue(address user) external view returns (uint256);

    /**
     * @dev Returns the total market value of all the tokens.
     * @return The total market value of all the tokens
     **/
    function totalMarketValue() external view returns (uint256);

    /**
     * @dev Returns the version of the xToken implementation
     * @return The version number
     **/
    function XTOKEN_VERSION() external view returns (uint256);

    /**
     * @dev Returns the oracle contract address used for price feeds
     * @return The address of the oracle contract
     **/
    function oracle() external view returns (IAssetOracle);

    /**
     * @dev Returns the pool contract address that manages this token
     * @return The address of the pool contract
     **/
    function pool() external view returns (address);

    /**
     * @dev Mints `amount` xTokens to `account`
     * @param account The address receiving the minted tokens
     * @param amount The amount of tokens getting minted
     * @param price The price at which the tokens are minted
     */
    function mint(
        address account,
        uint256 amount,
        uint256 price
    ) external;

    /**
     * @dev Burns xTokens from `account`
     * @param account The owner of the xTokens, getting burned
     * @param amount The amount being burned
     **/
    function burn(
        address account,
        uint256 amount
    ) external;
}