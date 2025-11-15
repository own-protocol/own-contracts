// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "../interfaces/IXToken.sol";

/**
 * @title xToken Contract
 * @notice This contract implements a token that tracks an underlying real-world asset.
 * All amounts are expected to be in 18 decimal precision.
 * The asset price is assumed to be in 18 decimal precision.
 */
contract xToken is IXToken, ERC20, ERC20Permit {
    
    /// @notice Address of the pool contract that manages this token
    address public immutable pool;

    /// @notice Address of the manager contract that manages this token
    address public immutable manager;

    /// @notice Version identifier for the xToken implementation
    uint256 public constant XTOKEN_VERSION = 0x1;

    /// @notice Price precision constant
    uint256 private constant PRECISION = 1e18;

    /// @notice Split multiplier to adjust balances for token splits
    uint256 private _splitMultiplier = PRECISION; // Start at 1.0 (scaled by PRECISION)

    /// @notice Split version counter - increments on every split to invalidate old permits
    uint256 public splitVersion;

    /// @notice Stores the struct hash for permit with split version
    bytes32 private constant _PERMIT_TYPEHASH_WITH_SPLIT = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline,uint256 splitVersion)"
    );
        

    /**
     * @notice Ensures the caller is a pool contract
     */
    modifier onlyPool() {
        if (msg.sender != pool) revert NotPool();
        _;
    }

    /**
     * @notice Ensures the caller is the manager contract
     */
    modifier onlyManager() {
        if (msg.sender != manager) revert NotManager();
        _;
    }

    /**
     * @notice Constructs the xToken contract
     * @param name The name of the token
     * @param symbol The symbol of the token
     */
    constructor(string memory name, string memory symbol, address _manager) ERC20(name, symbol) ERC20Permit(name) {
        pool = msg.sender;
        manager = _manager;
    }

    /**
     * @notice Returns the current split multiplier used to adjust balances for token splits
     * @return The current split multiplier value (scaled by PRECISION)
     * @dev A value of PRECISION (1e18) means no split adjustment
     * @dev A value of 2*PRECISION means all balances appear doubled (2:1 split)
     * @dev A value of PRECISION/2 means all balances appear halved (1:2 reverse split)
     */
    function splitMultiplier() public view returns (uint256) {
        return _splitMultiplier;
    }



    /**
     * @notice Override of balanceOf to apply the split multiplier
     * @param account The address to query the balance of
     * @return The balance adjusted by the split multiplier
     * @dev The raw storage value is multiplied by the split multiplier to get the displayed balance
     * @dev This allows all balances to be adjusted during a token split without updating storage
     */
    function balanceOf(address account) public view override(ERC20, IERC20) returns (uint256) {
        return Math.mulDiv(super.balanceOf(account), _splitMultiplier, PRECISION);
    }

    /**
     * @notice Override of totalSupply to apply the split multiplier
     * @return The total supply adjusted by the split multiplier
     * @dev The raw storage value is multiplied by the split multiplier to get the displayed total supply
     * @dev This allows the total supply to be adjusted during a token split without updating storage
     */
    function totalSupply() public view override(ERC20, IERC20) returns (uint256) {
        return Math.mulDiv(super.totalSupply(), _splitMultiplier, PRECISION);
    }

    /**
     * @notice Override of allowance to apply the split multiplier
     * @param owner The address that owns the tokens
     * @param spender The address that is approved to spend the tokens
     * @return The allowance adjusted by the split multiplier
     * @dev The raw storage value is multiplied by the split multiplier to get the displayed allowance
     * @dev This ensures allowances are adjusted proportionally during token splits
     */
    function allowance(address owner, address spender) public view override(ERC20, IERC20) returns (uint256) {
        // Handle infinite approval case
        if (super.allowance(owner, spender) == type(uint256).max) {
            return type(uint256).max;
        }
        return Math.mulDiv(super.allowance(owner, spender), _splitMultiplier, PRECISION);
    }

    /**
     * @notice Mints new tokens to an account
     * @dev Only callable by the pool contract
     * @param account The address receiving the minted tokens
     * @param amount The amount of tokens to mint (visible amount with split multiplier applied)
     * @dev The actual storage amount is calculated by dividing the visible amount by the split multiplier
     * @dev Example: If amount=100 and splitMultiplier=2*PRECISION (2:1 split), 50 tokens are stored
     */
    function mint(address account, uint256 amount) external onlyPool {
        // Convert the visible amount to raw storage amount
        uint256 rawAmount = Math.mulDiv(amount, PRECISION, _splitMultiplier);
        
        _mint(account, rawAmount);
        emit Mint(account, amount);
    }

    /**
     * @notice Burns tokens from an account
     * @dev Only callable by the pool contract
     * @param account The address to burn tokens from
     * @param amount The amount of tokens to burn (visible amount with split multiplier applied)
     * @dev The actual storage amount is calculated by dividing the visible amount by the split multiplier
     * @dev Example: If amount=100 and splitMultiplier=2*PRECISION (2:1 split), 50 tokens are burned from storage
     */
    function burn(address account, uint256 amount) external onlyPool {
        // Convert the visible amount to raw storage amount
        uint256 rawAmount = Math.mulDiv(amount, PRECISION, _splitMultiplier);
        
        uint256 balance = super.balanceOf(account);
        if (balance < rawAmount) revert InsufficientBalance();
        
        _burn(account, rawAmount);
        emit Burn(account, amount);
    }

    /**
     * @notice Applies a split to adjust token balances
     * @param splitRatio Numerator of the split ratio (e.g., 2 for a 2:1 split where 1 token becomes 2)
     * @param splitDenominator Denominator of the split ratio (e.g., 1 for a 2:1 split)
     * @dev Only callable by the manager contract
     * @dev Updates the split multiplier to affect all balances without changing storage values
     * @dev For a 2:1 split (1 token becomes 2): splitRatio=2, splitDenominator=1
     * @dev For a 1:2 reverse split (2 tokens become 1): splitRatio=1, splitDenominator=2
     */
    function applySplit(uint256 splitRatio, uint256 splitDenominator) external onlyManager {
        if (splitRatio == 0 || splitDenominator == 0) revert InvalidSplitRatio();
        
        // Update the split multiplier
        uint256 adjustmentRatio = Math.mulDiv(splitRatio, PRECISION, splitDenominator);
        _splitMultiplier = Math.mulDiv(_splitMultiplier, adjustmentRatio, PRECISION);

        // Increment split version to invalidate all outstanding permits
        unchecked {
            ++splitVersion;
        }
            
        emit StockSplitApplied(splitRatio, splitDenominator, _splitMultiplier);
    }

    /**
     * @notice Transfers tokens to a recipient
     * @param recipient The address receiving the tokens 
     * @param amount The amount of tokens to transfer (visible amount with split multiplier applied)
     * @return success True if the transfer succeeded
     * @dev The actual storage amount transferred is calculated by dividing the visible amount by the split multiplier
     * @dev Example: If amount=100 and splitMultiplier=2*PRECISION (2:1 split), 50 tokens are transferred in storage
     */
    function transfer(address recipient, uint256 amount) public override(ERC20, IERC20) returns (bool) {
        if (recipient == address(0)) revert ZeroAddress();

        // Convert the visible amount to raw storage amount
        uint256 rawAmount = Math.mulDiv(amount, PRECISION, _splitMultiplier);

        uint256 balance = super.balanceOf(msg.sender);
        if (balance < rawAmount) revert InsufficientBalance();

        // Call the parent implementation with the raw amount
        // This will handle the balance and allowance checks correctly
        return super.transfer(recipient, rawAmount);
    }

    /**
     * @notice Transfers tokens from one address to another using the allowance mechanism
     * @param sender The address to transfer tokens from
     * @param recipient The address receiving the tokens
     * @param amount The amount of tokens to transfer (visible amount with split multiplier applied)
     * @return success True if the transfer succeeded
     * @dev The actual storage amount transferred is calculated by dividing the visible amount by the split multiplier
     * @dev The allowance is also decreased by the raw storage amount, not the visible amount
     * @dev Example: If amount=100 and splitMultiplier=2*PRECISION, 50 tokens are transferred and 50 deducted from allowance
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override(ERC20, IERC20) returns (bool) {
        
        if (recipient == address(0)) revert ZeroAddress();
        
        // Convert the visible amount to raw storage amount
        uint256 rawAmount = Math.mulDiv(amount, PRECISION, _splitMultiplier);
        
        uint256 currentAllowance = super.allowance(sender, msg.sender);
        if (currentAllowance < rawAmount) revert InsufficientAllowance();

        uint256 balance = super.balanceOf(sender);
        if (balance < rawAmount) revert InsufficientBalance();
        
        if (currentAllowance == type(uint256).max) {
            // Infinite allowance, no need to update
            _transfer(sender, recipient, rawAmount);
            return true;
        }
        // Update allowance with raw amount
        _approve(sender, msg.sender, currentAllowance - rawAmount);

        _transfer(sender, recipient, rawAmount);

        return true;
    }

    /**
     * @notice Approves the spender to spend a specified amount of tokens
     * @param spender The address that will be allowed to spend the tokens
     * @param amount The amount of tokens to approve (visible amount with split multiplier applied)
     * @return success True if the approval succeeded
     * @dev The actual storage amount approved is calculated by dividing the visible amount by the split multiplier
     * @dev Example: If amount=100 and splitMultiplier=2*PRECISION (2:1 split), an allowance of 50 tokens is stored
     */
    function approve(address spender, uint256 amount) public override(ERC20, IERC20) returns (bool) {
        // Handle infinite approval case
        if (amount == type(uint256).max) {
            return super.approve(spender, amount);
        }
        // Convert the visible amount to raw storage amount
        uint256 rawAmount = Math.mulDiv(amount, PRECISION, _splitMultiplier);
        return super.approve(spender, rawAmount);
    }

    /**
     * @notice Override the permit function to convert the amount parameter
     * @dev Users sign the visible amount, but we need to store the raw amount
     * @param owner The address of the token owner
     * @param spender The address of the spender
     * @param value The amount of tokens to approve (visible amount)
     * @param deadline The deadline timestamp for the signature
     * @param v The recovery ID for the signature
     * @param r The R component of the signature
     * @param s The S component of the signature
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override {
        require(block.timestamp <= deadline, "ERC20Permit: expired deadline");

        // Build the struct hash with the value that was actually signed
        bytes32 structHash = keccak256(
            abi.encode(
                _PERMIT_TYPEHASH_WITH_SPLIT,
                owner,
                spender,
                value,
                _useNonce(owner),
                deadline,
                splitVersion
            )
        );

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSA.recover(hash, v, r, s);
        require(signer == owner, "ERC20Permit: invalid signature");

        // Convert to raw storage units for allowance
        uint256 rawValue;
        if (value == type(uint256).max) {
            // Preserve infinite-approval semantics
            rawValue = type(uint256).max;
        } else {
            rawValue = Math.mulDiv(value, PRECISION, _splitMultiplier);
        }
        _approve(owner, spender, rawValue);
    }

}