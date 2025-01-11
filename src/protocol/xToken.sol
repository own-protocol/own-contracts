// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "../interfaces/IAssetOracle.sol";
import "../interfaces/IXToken.sol";

/**
 * @title xToken Contract
 * @notice This contract implements a price-scaling token that tracks an underlying real-world asset.
 * @dev The token maintains scaled balances that adjust based on the underlying asset price.
 * All user-facing amounts are in standard token decimals, while internal accounting uses scaled balances.
 * The asset price is assumed to be in cents (1/100 of a dollar).
 */
contract xToken is IXToken, ERC20 {
    /// @notice Reference to the oracle providing asset price feeds
    IAssetOracle public immutable oracle;
    
    /// @notice Address of the pool contract that manages this token
    address public immutable pool;

    /// @notice Version identifier for the xToken implementation
    uint256 public constant XTOKEN_VERSION = 0x1;

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
    constructor(string memory name, string memory symbol, address _oracle) ERC20(name, symbol) {
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
     * @notice Converts a nominal token amount to its scaled equivalent
     * @dev Uses the current asset price for conversion
     * @param amount The amount to convert
     * @return The equivalent scaled amount
     */
    function _convertToScaledAmount(uint256 amount) internal view returns (uint256) {
        uint256 price = oracle.assetPrice();
        if (price == 0) revert InvalidPrice();
        return Math.mulDiv(amount, 1e18, price);
    }

    /**
     * @notice Returns the market value of a user's tokens
     * @dev Converts the scaled balance to market value using current asset price
     * @param account The address of the account
     * @return The market value of a user's tokens
     */
    function marketValue(address account) public view returns (uint256) {
        uint256 price = oracle.assetPrice();
        if (price == 0) revert InvalidPrice();
        return Math.mulDiv(_scaledBalances[account], price, 1e18);
    }

    /**
     * @notice Returns the total market vaule of all the tokens
     * @dev Converts the total scaled supply to nominal terms using current asset price
     * @return The total market value of all the tokens
     */
    function totalMarketValue() public view returns (uint256) {
        uint256 price = oracle.assetPrice();
        if (price == 0) revert InvalidPrice();
        return Math.mulDiv(_totalScaledSupply, price, 1e18);
    }

    /**
     * @notice Mints new tokens to an account
     * @dev Only callable by the pool contract
     * @param account The address receiving the minted tokens
     * @param amount The amount of tokens to mint (in nominal terms)
     */
    function mint(address account, uint256 amount) external onlyPool {
        uint256 scaledAmount = _convertToScaledAmount(amount);
        _scaledBalances[account] += scaledAmount;
        _totalScaledSupply += scaledAmount;
        _mint(account, amount);
        emit Mint(account, amount);
    }

    /**
     * @notice Burns tokens from an account
     * @dev Only callable by the pool contract
     * @param account The address to burn tokens from
     * @param amount The amount of tokens to burn (in nominal terms)
     */
    function burn(address account, uint256 amount) external onlyPool {
        uint256 scaledAmount = _convertToScaledAmount(amount);
        if (_scaledBalances[account] < scaledAmount) revert InsufficientBalance();
        _scaledBalances[account] -= scaledAmount;
        _totalScaledSupply -= scaledAmount;
        _burn(account, amount);
        emit Burn(account, amount);
    }

    /**
     * @notice Transfers tokens to a recipient
     * @param recipient The address receiving the tokens
     * @param amount The amount of tokens to transfer (in nominal terms)
     * @return success True if the transfer succeeded
     */
    function transfer(address recipient, uint256 amount) public override(ERC20, IERC20) returns (bool) {
        if (recipient == address(0)) revert ZeroAddress();
        uint256 scaledAmount = _convertToScaledAmount(amount);
        if (_scaledBalances[msg.sender] < scaledAmount) revert InsufficientBalance();
        
        _scaledBalances[msg.sender] -= scaledAmount;
        _scaledBalances[recipient] += scaledAmount;

        _transfer(msg.sender, recipient, amount);
        
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    /**
     * @notice Transfers tokens from one address to another using the allowance mechanism
     * @param sender The address to transfer tokens from
     * @param recipient The address receiving the tokens
     * @param amount The amount of tokens to transfer (in nominal terms)
     * @return success True if the transfer succeeded
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override(ERC20, IERC20) returns (bool) {
        if (recipient == address(0)) revert ZeroAddress();
        uint256 currentAllowance = allowance(sender, msg.sender);
        if (currentAllowance < amount) revert InsufficientAllowance();

        uint256 scaledAmount = _convertToScaledAmount(amount);
        if (_scaledBalances[sender] < scaledAmount) revert InsufficientBalance();

        _scaledBalances[sender] -= scaledAmount;
        _scaledBalances[recipient] += scaledAmount;
        _approve(sender, msg.sender, currentAllowance - amount);

        _transfer(sender, recipient, amount);

        emit Transfer(sender, recipient, amount);
        return true;
    }
}