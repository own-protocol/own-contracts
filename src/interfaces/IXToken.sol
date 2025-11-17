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
     * @dev Thrown when a caller is not the manager contract
     */
    error NotManager();

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
     * @dev Thrown when an invalid token split ratio is provided
     */
    error InvalidSplitRatio();

    /**
     * @dev Emitted after new tokens are minted
     * @param account The address receiving the minted tokens
     * @param value The amount of tokens minted (this is the visible amount after applying token split multiplier)
     **/
    event Mint(address indexed account, uint256 value);

    /**
     * @dev Emitted after tokens are burned
     * @param account The owner of the tokens that were burned
     * @param value The amount of tokens burned (this is the visible amount after applying token split multiplier)
     **/
    event Burn(address indexed account, uint256 value);

    /**
     * @dev Emitted when a token split is applied to adjust token balances
     * @param splitRatio Numerator of the split ratio (e.g., 2 for a 2:1 split where 1 token becomes 2)
     * @param splitDenominator Denominator of the split ratio (e.g., 1 for a 2:1 split)
     * @param newSplitMultiplier The new split multiplier value that will be applied to all balances
     **/
    event StockSplitApplied(uint256 splitRatio, uint256 splitDenominator, uint256 newSplitMultiplier);

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
     * @dev Returns the manager contract address that manages this token
     * @return The address of the manager contract
     **/
    function manager() external view returns (address);

    /**
     * @dev Returns the current split multiplier used to adjust balances for token splits
     * @return The current split multiplier value (scaled by PRECISION)
     * @dev A value of PRECISION (1e18) means no split adjustment
     * @dev A value of 2*PRECISION means all balances appear doubled (2:1 split) 
     * @dev A value of PRECISION/2 means all balances appear halved (1:2 reverse split)
     **/
    function splitMultiplier() external view returns (uint256);

    /**
     * @dev Returns the current split version counter
     * @return The current split version
     * @dev This increments with each token split to invalidate old permits
     **/
    function splitVersion() external view returns (uint256);

    /**
     * @dev Mints new tokens to the specified account
     * @param account The address that will receive the minted tokens
     * @param amount The amount of tokens to mint (visible amount, after applying split multiplier)
     * @dev Only the pool contract can call this function
     * @dev The actual storage amount will be calculated by dividing by the split multiplier
     */
    function mint(
        address account,
        uint256 amount
    ) external;

    /**
     * @dev Burns tokens from the specified account
     * @param account The address from which tokens will be burned
     * @param amount The amount of tokens to burn (visible amount, after applying split multiplier)
     * @dev Only the pool contract can call this function
     * @dev The actual storage amount will be calculated by dividing by the split multiplier
     **/
    function burn(
        address account,
        uint256 amount
    ) external;

    /**
     * @dev Applies a token split to adjust token balances
     * @param splitRatio Numerator of the split ratio (e.g., 2 for a 2:1 split where 1 token becomes 2)
     * @param splitDenominator Denominator of the split ratio (e.g., 1 for a 2:1 split)
     * @dev Only the pool contract can call this function
     * @dev This function updates the split multiplier which affects all balances without changing storage
     * @dev For a 2:1 split (1 token becomes 2): splitRatio=2, splitDenominator=1
     * @dev For a 1:2 reverse split (2 tokens become 1): splitRatio=1, splitDenominator=2
     */
    function applySplit(
        uint256 splitRatio,
        uint256 splitDenominator
    ) external;
}