// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockYieldToken
 * @notice A mock implementation of a yield-bearing token (like aToken) for testing yield functionality
 * @dev Balances automatically increase at a fixed rate over time
 */
contract MockYieldToken is ERC20 {
    // Yield rate in basis points per day (e.g., 50 = 0.5% daily yield)
    uint256 public yieldRatePerDay;
    
    // Timestamp of last global yield calculation
    uint256 public lastYieldTimestamp;
    
    // Mapping for user deposit timestamps
    mapping(address => uint256) public userDepositTimestamps;
    
    // Basis points denominator
    uint256 private constant BPS = 10000;
    
    // Token decimals
    uint8 private _decimals;

    /**
     * @notice Constructor for MockYieldToken
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param decimals_ Token decimals
     * @param _yieldRatePerDay Daily yield rate in basis points (e.g., 50 = 0.5%)
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 _yieldRatePerDay
    ) ERC20(name_, symbol_) {
        _decimals = decimals_;
        yieldRatePerDay = _yieldRatePerDay;
        lastYieldTimestamp = block.timestamp;
    }
    
    /**
     * @notice Returns the number of decimals used for token
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Override of balanceOf to include accrued yield
     * @param account The address to check balance for
     * @return The balance including accrued yield
     */
    function balanceOf(address account) public view override returns (uint256) {
        uint256 rawBalance = super.balanceOf(account);
        if (rawBalance == 0) {
            return 0;
        }
        
        // Calculate time elapsed since last deposit or yield update
        uint256 userTimestamp = userDepositTimestamps[account] > 0 ? 
                                userDepositTimestamps[account] : lastYieldTimestamp;
        uint256 timeElapsed = block.timestamp - userTimestamp;
        
        // Calculate yield based on time elapsed
        uint256 daysElapsed = timeElapsed / 1 days;
        if (daysElapsed == 0) {
            return rawBalance;
        }
        
        // Calculate compound yield
        uint256 yield = 0;
        uint256 compoundedBalance = rawBalance;
        
        for (uint256 i = 0; i < daysElapsed; i++) {
            yield = (compoundedBalance * yieldRatePerDay) / BPS;
            compoundedBalance += yield;
        }
        
        return compoundedBalance;
    }

    /**
     * @notice Override transfer to account for yield before transferring
     * @param to Recipient address
     * @param amount Amount to transfer
     * @return bool True if successful
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        _updateYield(msg.sender);
        _updateYield(to);
        return super.transfer(to, amount);
    }

    /**
     * @notice Override transferFrom to account for yield before transferring
     * @param from Sender address
     * @param to Recipient address
     * @param amount Amount to transfer
     * @return bool True if successful
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _updateYield(from);
        _updateYield(to);
        return super.transferFrom(from, to, amount);
    }

    /**
     * @notice Mint tokens to an address
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) public {
        _updateYield(to);
        _mint(to, amount);
    }

    /**
     * @notice Updates a user's actual balance with accrued yield
     * @param account The user account to update
     */
    function _updateYield(address account) internal {
        uint256 currentBalance = super.balanceOf(account);
        if (currentBalance == 0) {
            userDepositTimestamps[account] = block.timestamp;
            return;
        }
        
        uint256 newBalance = balanceOf(account);
        if (newBalance > currentBalance) {
            uint256 yieldAmount = newBalance - currentBalance;
            
            // Update actual balance with yield by minting tokens
            _mint(account, yieldAmount);
        }
        
        // Update user's timestamp
        userDepositTimestamps[account] = block.timestamp;
    }

    /**
     * @notice External function to trigger yield update for a user
     * @param account The user account to update
     */
    function updateYield(address account) external {
        _updateYield(account);
    }

    /**
     * @notice Set a new yield rate
     * @param _yieldRatePerDay New daily yield rate in basis points
     */
    function setYieldRate(uint256 _yieldRatePerDay) external {
        yieldRatePerDay = _yieldRatePerDay;
        lastYieldTimestamp = block.timestamp;
    }
}