// SPDX-License-Identifier: GPL-3.0-or-later
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IAssetOracle} from './IAssetOracle.sol';

interface IXToken is IERC20 {
    
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
     * @param reserve The amount of reserve tokens which is backing the minted xTokens
     **/
    event Mint(address indexed account, uint256 value, uint256 reserve);

    /**
     * @dev Emitted after xTokens are burned
     * @param account The owner of the xTokens, getting burned
     * @param value The amount being burned
     * @param reserve The amount of reserve tokens
     **/
    event Burn(address indexed account, uint256 value, uint256 reserve);

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
     * @dev Returns the reserve balance of the user that is backing the xTokens.
     * @param user The user whose balance is calculated
     * @return The reserve balance of the user
     **/
    function reserveBalanceOf(address user) external view returns (uint256);

    /**
     * @dev Returns the reserve total supply of the token.
     * @return The reserve total supply
     **/
    function totalReserveSupply() external view returns (uint256);

    /**
     * @dev Mints `amount` xTokens to `account`
     * @param account The address receiving the minted tokens
     * @param amount The amount of tokens getting minted
     * @param reserve The amount of reserve tokens which is backing the minted xTokens
     */
    function mint(
        address account,
        uint256 amount,
        uint256 reserve
    ) external;

    /**
     * @dev Burns xTokens from `account`
     * @param account The owner of the xTokens, getting burned
     * @param amount The amount being burned
     * @param reserve The amount of reserve tokens
     **/
    function burn(
        address account,
        uint256 amount,
        uint256 reserve
    ) external;
}