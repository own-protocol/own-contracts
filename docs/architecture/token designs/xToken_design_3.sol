// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham
// Token design where balance remains constant matching the asset supply

pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

/**
 * @title xToken Contract
 * @notice This contract implements a token that tracks an underlying real-world asset.
 * All amounts are expected to be in 18 decimal precision.
 * The asset price is assumed to be in 18 decimal precision.
 */
contract xToken is ERC20, ERC20Permit {

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
    
    /// @notice Address of the pool contract that manages this token
    address public immutable pool;

    /// @notice Version identifier for the xToken implementation
    uint256 public constant XTOKEN_VERSION = 0x1;

    /// @notice Price precision constant
    uint256 private constant PRECISION = 1e18;

    /// @notice Mapping of reserve balances for each account
    mapping(address => uint256) private _reserveBalances;
    
    /// @notice Total supply in reserve balance terms
    uint256 private _totalReserveSupply;

    /**
     * @notice Ensures the caller is the pool contract
     */
    modifier onlyPool() {
        if (msg.sender != pool) revert NotPool();
        _;
    }

    /**
     * @notice Constructs the xToken contract
     * @param name The name of the token
     * @param symbol The symbol of the token
     */
    constructor(string memory name, string memory symbol) ERC20(name, symbol) ERC20Permit(name) {
        pool = msg.sender;
    }

     /**
     * @notice Returns the reserve balance of an account
     * @dev This balance is independent of the asset price and represents the user's share of the reserve tokens in the pool
     * @param account The address of the account
     * @return The reserve balance of the account
     */
    function reserveBalanceOf(address account) public view returns (uint256) {
        return _reserveBalances[account];
    }

    /**
     * @notice Returns the total reserve supply
     * @return The total reserve supply of tokens
     */
    function totalReserveSupply() public view returns (uint256) {
        return _totalReserveSupply;
    }

    /**
     * @notice Mints new tokens to an account
     * @dev Only callable by the pool contract
     * @param account The address receiving the minted tokens
     * @param amount The amount of tokens to mint (in 18 decimal precision)
     * @param reserve The amount of reserve tokens which is backing the minted xTokens
     */
    function mint(address account, uint256 amount, uint256 reserve) external onlyPool {
        _reserveBalances[account] += reserve;
        _totalReserveSupply += reserve;
        _mint(account, amount);
        emit Mint(account, amount, reserve);
    }

    /**
     * @notice Burns tokens from an account
     * @dev Only callable by the pool contract
     * @param account The address to burn tokens from
     * @param amount The amount of tokens to burn (in 18 decimal precision)
     * @param reserve The amount of reserve tokens to burn
     */
    function burn(address account, uint256 amount, uint256 reserve) external onlyPool {
        uint256 balance = balanceOf(account);
        uint256 reserveBalance = _reserveBalances[account];
        if (balance < amount) revert InsufficientBalance();
        if (reserveBalance < reserve) revert InsufficientBalance();
        _reserveBalances[account] -= reserve;
        _totalReserveSupply -= reserve;
        _burn(account, amount);
        emit Burn(account, amount, reserve);
    }

    /**
     * @notice Transfers tokens to a recipient
     * @param recipient The address receiving the tokens 
     * @param amount The amount of tokens to transfer (in 18 decimal precision)
     * @return success True if the transfer succeeded
     */
    function transfer(address recipient, uint256 amount) public override(ERC20) returns (bool) {
        if (recipient == address(0)) revert ZeroAddress();
        uint256 balance = balanceOf(msg.sender);
        if (balance < amount) revert InsufficientBalance();

        uint256 reserveBalance = _reserveBalances[msg.sender];
        uint256 reserveBalanceToTransfer = Math.mulDiv(reserveBalance, amount, balance);
        
        _reserveBalances[msg.sender] -= reserveBalanceToTransfer;
        _reserveBalances[recipient] += reserveBalanceToTransfer;

        _transfer(msg.sender, recipient, amount);
        
        return true;
    }

    /**
     * @notice Transfers tokens from one address to another using the allowance mechanism
     * @param sender The address to transfer tokens from
     * @param recipient The address receiving the tokens
     * @param amount The amount of tokens to transfer (in 18 decimal precision)
     * @return success True if the transfer succeeded
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override(ERC20) returns (bool) {
        if (recipient == address(0)) revert ZeroAddress();
        uint256 currentAllowance = allowance(sender, msg.sender);
        if (currentAllowance < amount) revert InsufficientAllowance();

        uint256 balance = balanceOf(sender);
        if (balance < amount) revert InsufficientBalance();

        uint256 reserveBalance = _reserveBalances[sender];
        uint256 reserveBalanceToTransfer = Math.mulDiv(reserveBalance, amount, balance);

        _reserveBalances[sender] -= reserveBalanceToTransfer;
        _reserveBalances[recipient] += reserveBalanceToTransfer;
        _approve(sender, msg.sender, currentAllowance - amount);

        _transfer(sender, recipient, amount);

        return true;
    }
}