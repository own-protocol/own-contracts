// SPDX-License-Identifier: GPL-3.0-or-later
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import {IERC20Metadata} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';

interface IXToken is IERC20Metadata {
    
    /**
     * @dev Thrown when a caller is not the pool contract
     */
    error NotPool();

    /**
     * @dev Thrown when zero address is provided where it's not allowed
     */
    error ZeroAddress();

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
     **/
    event Mint(address indexed account, uint256 value);

    /**
     * @dev Emitted after xTokens are burned
     * @param account The owner of the xTokens, getting burned
     * @param value The amount being burned
     **/
    event Burn(address indexed account, uint256 value);

    /**
     * @dev Returns the version of the xToken implementation
     * @return The version number
     **/
    function XTOKEN_VERSION() external view returns (uint256);

    /**
     * @dev Returns the pool contract address that manages this token
     * @return The address of the pool contract
     **/
    function pool() external view returns (address);

    /**
     * @dev Mints `amount` xTokens to `account`
     * @param account The address receiving the minted tokens
     * @param amount The amount of tokens getting minted
     */
    function mint(
        address account,
        uint256 amount
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