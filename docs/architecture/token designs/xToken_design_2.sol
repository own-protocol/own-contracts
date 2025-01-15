// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham
// Token design where balance remains constant matching the initial reserve deposit

pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "../../../src/interfaces/IAssetOracle.sol";

/**
 * @title xToken Contract
 * @notice This contract implements a price-scaling token that tracks an underlying real-world asset.
 * @dev The token maintains scaled balances that adjust based on the underlying asset price.
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
    
    /// @notice Reference to the oracle providing asset price feeds
    IAssetOracle public immutable oracle;
    
    /// @notice Address of the pool contract that manages this token
    address public immutable pool;

    /// @notice Version identifier for the xToken implementation
    uint256 public constant XTOKEN_VERSION = 0x1;

    /// @notice Price precision constant
    uint256 private constant PRECISION = 1e18;

    /// @notice Mapping of scaled balances for each account
    mapping(address => uint256) private _scaledBalances;
    
    /// @notice Total supply in scaled balance terms
    uint256 private _totalScaledSupply;

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
     * @param _oracle The address of the asset price oracle
     */
    constructor(string memory name, string memory symbol, address _oracle) ERC20(name, symbol) ERC20Permit(name) {
        if (_oracle == address(0)) revert ZeroAddress();
        oracle = IAssetOracle(_oracle);
        pool = msg.sender;
    }

    /**
     * @notice Returns the scaled balance of an account
     * @dev This balance is independent of the asset price and represents the user's share of the pool
     * @param account The address of the account
     * @return The scaled balance of the account
     */
    function scaledBalanceOf(address account) public view returns (uint256) {
        return _scaledBalances[account];
    }

    /**
     * @notice Returns the total scaled supply
     * @return The total scaled supply of tokens
     */
    function scaledTotalSupply() public view returns (uint256) {
        return _totalScaledSupply;
    }

    /**
     * @notice Converts token amount to its scaled equivalent at the given price
     * @param amount The amount to convert (in 18 decimal precision)
     * @param price The asset price to use for conversion
     * @return The equivalent scaled amount
     */
    function _convertToScaledAmountWithPrice(uint256 amount, uint256 price) internal pure returns (uint256) {
        if (price == 0) revert InvalidPrice();
        return Math.mulDiv(amount, PRECISION, price);
    }

    /**
     * @notice Returns the market value of a user's tokens
     * @dev Converts the scaled balance to market value using current asset price
     * @param account The address of the account
     * @return The market value of user's tokens in 18 decimal precision
     */
    function marketValue(address account) public view returns (uint256) {
        uint256 price = oracle.assetPrice();
        if (price == 0) revert InvalidPrice();
        return _scaledBalances[account] * price;
    }

    /**
     * @notice Returns the total market value of all tokens
     * @dev Converts the total scaled supply to nominal terms using current asset price
     * @return The total market value in 18 decimal precision
     */
    function totalMarketValue() public view returns (uint256) {
        uint256 price = oracle.assetPrice();
        if (price == 0) revert InvalidPrice();
        return _totalScaledSupply * price;
    }

    /**
     * @notice Mints new tokens to an account
     * @dev Only callable by the pool contract
     * @param account The address receiving the minted tokens
     * @param amount The amount of tokens to mint (in 18 decimal precision)
     * @param price The asset price at which the minting is done
     */
    function mint(address account, uint256 amount, uint256 price) external onlyPool {
        uint256 scaledAmount = _convertToScaledAmountWithPrice(amount, price);
        _scaledBalances[account] += scaledAmount;
        _totalScaledSupply += scaledAmount;
        _mint(account, amount);
        emit Mint(account, amount, price);
    }

    /**
     * @notice Burns tokens from an account
     * @dev Only callable by the pool contract
     * @param account The address to burn tokens from
     * @param amount The amount of tokens to burn (in 18 decimal precision)
     */
    function burn(address account, uint256 amount) external onlyPool {
        uint256 balance = balanceOf(account);
        if (balance < amount) revert InsufficientBalance();
        uint256 scaledBalance = _scaledBalances[account];
        uint256 scaledBalanceToBurn = Math.mulDiv(scaledBalance, amount, balance);

        _scaledBalances[account] -= scaledBalanceToBurn;
        _totalScaledSupply -= scaledBalanceToBurn;
        _burn(account, amount);
        emit Burn(account, amount);
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

        uint256 scaledBalance = _scaledBalances[msg.sender];
        uint256 scaledBalanceToTransfer = Math.mulDiv(scaledBalance, amount, balance);
        
        _scaledBalances[msg.sender] -= scaledBalanceToTransfer;
        _scaledBalances[recipient] += scaledBalanceToTransfer;

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

        uint256 scaledBalance = _scaledBalances[sender];
        uint256 scaledBalanceToTransfer = scaledBalance * amount / balance;

        _scaledBalances[sender] -= scaledBalanceToTransfer;
        _scaledBalances[recipient] += scaledBalanceToTransfer;
        _approve(sender, msg.sender, currentAllowance - amount);

        _transfer(sender, recipient, amount);

        return true;
    }
}