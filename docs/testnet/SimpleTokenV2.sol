// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title SimpleToken
 * @dev A simple ERC20 token with configurable minting limits for non-owners
 */
contract SimpleToken is ERC20, Ownable {
    // Mapping to track how much each non-owner has minted
    mapping(address => uint256) private _nonOwnerMintedAmount;
    
    // Mapping to track how many times each non-owner has minted
    mapping(address => uint256) private _nonOwnerMintCount;
    
    // Maximum amount that a non-owner can mint (per address)
    uint256 public immutable nonOwnerMintLimit;
    
    // Maximum number of times a non-owner can mint
    uint256 public immutable maxMintTimes;
    
    // Maximum amount that can be minted in a single transaction (in token units, not wei)
    uint256 public immutable maxMintPerTransaction;
    
    // Token decimals
    uint8 private _decimals;

    /**
     * @dev Constructor that sets the token name, symbol, and non-owner mint limits
     * @param name_ The name of the token
     * @param symbol_ The symbol of the token
     * @param decimals_ The number of decimals the token uses
     * @param mintLimit_ The maximum amount of tokens a non-owner can mint (in token units)
     * @param maxMintPerTx_ The maximum amount of tokens that can be minted per transaction (in token units)
     * @param maxMintTimes_ The maximum number of times a non-owner can mint
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 mintLimit_,
        uint256 maxMintPerTx_,
        uint256 maxMintTimes_
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        _decimals = decimals_;
        nonOwnerMintLimit = mintLimit_ * (10 ** decimals_);
        maxMintPerTransaction = maxMintPerTx_ * (10 ** decimals_);
        maxMintTimes = maxMintTimes_;
    }

    /**
     * @dev Returns the number of decimals used by the token
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Allows anyone to mint tokens
     * - Owner can mint unlimited tokens
     * - Non-owners can mint up to the configured limit per address
     * - Non-owners can only mint a maximum of [maxMintTimes] times
     * - Non-owners can mint maximum [maxMintPerTransaction] tokens per transaction
     * @param amount The amount of tokens to mint
     */
    function mint(uint256 amount) external {
        if (owner() == _msgSender()) {
            // Owner can mint unlimited tokens
            _mint(_msgSender(), amount);
        } else {
            // Non-owners have multiple constraints
            
            // Check if user has exceeded maximum mint attempts
            require(_nonOwnerMintCount[_msgSender()] < maxMintTimes, "SimpleToken: Exceeded maximum mint attempts");
            
            // Check if amount exceeds per-transaction limit
            require(amount <= maxMintPerTransaction, "SimpleToken: Exceeds maximum mint per transaction");
            
            // Check if total minted would exceed the limit
            uint256 newTotal = _nonOwnerMintedAmount[_msgSender()] + amount;
            require(newTotal <= nonOwnerMintLimit, "SimpleToken: Exceeds non-owner mint limit");
            
            // Update tracking variables
            _nonOwnerMintedAmount[_msgSender()] = newTotal;
            _nonOwnerMintCount[_msgSender()]++;
            
            _mint(_msgSender(), amount);
        }
    }

    /**
     * @dev Returns how much a given address has minted so far (only relevant for non-owners)
     * @param account The address to check
     * @return The amount minted by this address
     */
    function mintedByAddress(address account) external view returns (uint256) {
        return _nonOwnerMintedAmount[account];
    }

    /**
     * @dev Returns how many times a given address has minted (only relevant for non-owners)
     * @param account The address to check
     * @return The number of times this address has minted
     */
    function mintCountByAddress(address account) external view returns (uint256) {
        return _nonOwnerMintCount[account];
    }

    /**
     * @dev Allows anyone to burn their own tokens
     * @param amount The amount of tokens to burn
     */
    function burn(uint256 amount) external {
        _burn(_msgSender(), amount);
    }
}