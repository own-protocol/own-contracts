// SPDX-License-Identifier: GPL-3.0-or-later
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "../interfaces/IAssetPool.sol";
import "../interfaces/IAssetOracle.sol";

/**
 * @title IPoolLiquidityManager
 * @notice Interface for the pool liquidity manager contract
 */
interface IPoolLiquidityManager {
    /**
     * @notice LP's current collateral and liquidity information
     */
    struct CollateralInfo {
        uint256 collateralAmount;      // Amount of collateral deposited
        uint256 liquidityAmount;       // Amount of liquidity provided
    }

    /**
     * @notice Emitted when an LP deposits collateral
     */
    event CollateralDeposited(address indexed lp, uint256 amount);

    /**
     * @notice Emitted when an LP withdraws collateral
     */
    event CollateralWithdrawn(address indexed lp, uint256 amount);

    /**
     * @notice Emitted when rebalance amount is added to LP's collateral
     */
    event RebalanceAdded(address indexed lp, uint256 amount);

    /**
     * @notice Emitted when rebalance amount is deducted from LP's collateral
     */
    event RebalanceDeducted(address indexed lp, uint256 amount);

    /**
     * @notice Emitted when LP's collateral is liquidated
     */
    event LPLiquidated(address indexed lp, address indexed liquidator, uint256 reward);

    /**
     * @notice Emitted when a new LP is registered
     */
    event LPRegistered(address indexed lp, uint256 liquidityAmount, uint256 collateralAmount);

    /**
     * @notice Emitted when an LP is removed
     */
    event LPRemoved(address indexed lp);

    /**
     * @notice Emitted when an LP increases their liquidity
     */
    event LiquidityIncreased(address indexed lp, uint256 amount);

    /**
     * @notice Emitted when an LP decreases their liquidity
     */
    event LiquidityDecreased(address indexed lp, uint256 amount);

    /**
     * @notice Error when zero amount is provided
     */
    error ZeroAmount();

    /**
     * @notice Error when caller is not a registered LP
     */
    error NotRegisteredLP();

    /**
     * @notice Error when withdrawal amount exceeds available collateral
     */
    error InvalidWithdrawalAmount();

    /**
     * @notice Error when collateral would fall below minimum ratio
     */
    error InsufficientCollateral();

    /**
     * @notice Error when LP is not eligible for liquidation
     */
    error NotEligibleForLiquidation();
    
    /**
     * @notice Error when LP is already registered
     */
    error AlreadyRegistered();

    /**
     * @notice Error when liquidation is invalid
     */
    error InvalidLiquidation();

    /**
     * @notice Error when LP has no liquidity to liquidate
     */
    error NoLiquidityToLiquidate();
    
    /**
     * @notice Error when trying to decrease liquidity more than available
     */
    error InsufficientLiquidity();

    /**
     * @notice Error when caller is not the pool cycle manager
     */
    error NotPoolCycleManager();

    /**
     * @notice Thrown when an is zero address
     */
    error ZeroAddress();
    
    /**
     * @notice Thrown when an amount is invalid
     */
    error InvalidAmount();
    
    /**
     * @notice Thrown when caller is not authorized
     */
    error Unauthorized();

    /**
     * @notice Total liquidity in the pool
     */
    function totalLPLiquidity() external view returns (uint256);
    
    /**
     * @notice Number of registered LPs
     */
    function lpCount() external view returns (uint256);

    /**
     * @notice Register as a liquidity provider
     * @param liquidityAmount The amount of liquidity to provide
     */
    function registerLP(uint256 liquidityAmount) external;

    /**
     * @notice Unregister LP from registry
     * @param lp The address of the LP
     */
    function unregisterLP(address lp) external;

    /**
     * @notice Increase your liquidity amount
     * @param amount The amount of liquidity to add
     */
    function increaseLiquidity(uint256 amount) external;

    /**
     * @notice Decrease your liquidity amount
     * @param amount The amount of liquidity to remove
     */
    function decreaseLiquidity(uint256 amount) external;

    /**
     * @notice Deposit additional collateral beyond the minimum
     * @param amount Amount of collateral to deposit
     */
    function deposit(uint256 amount) external;

    /**
     * @notice Withdraw excess collateral if above minimum requirements
     * @param amount Amount of collateral to withdraw
     */
    function withdraw(uint256 amount) external;

    /**
     * @notice Liquidate an LP below threshold
     * @param lp Address of the LP to liquidate
     */
    function liquidateLP(address lp) external;

    /**
     * @notice Deduct rebalance amount from LP's collateral
     * @param lp Address of the LP
     * @param amount Amount to deduct
     */
    function deductRebalanceAmount(address lp, uint256 amount) external;

    /**
     * @notice Add rebalance amount to LP's collateral
     * @param lp Address of the LP
     * @param amount Amount to add
     */
    function addToCollateral(address lp, uint256 amount) external;

    /**
     * @notice Get LP asset holdings value (in reserve token)
     * @param lp Address of the LP
     */
    function getLPAssetHoldingValue(address lp) external view returns (uint256);

    /**
     * @notice Get LP's current liquidity share of the pool
     * @param lp Address of the LP
     */
    function getLPLiquidityShare(address lp) external view returns (uint256);
    
    /**
     * @notice Get LP's current collateral and liquidity info
     * @param lp Address of the LP
     */
    function getLPInfo(address lp) external view returns (CollateralInfo memory);
    
    /**
     * @notice Check if an address is a registered LP
     * @param lp The address to check
     * @return bool True if the address is a registered LP
     */
    function isLP(address lp) external view returns (bool);
    
    /**
     * @notice Returns the number of LPs registered
     * @return uint256 The number of registered LPs
     */
    function getLPCount() external view returns (uint256);
    
    /**
     * @notice Returns the current liquidity amount for an LP
     * @param lp The address of the LP
     * @return uint256 The current liquidity amount
     */
    function getLPLiquidity(address lp) external view returns (uint256);
    
    /**
     * @notice Returns the total liquidity amount
     * @return uint256 The total liquidity amount
     */
    function getTotalLPLiquidity() external view returns (uint256);

    /**
     * @notice Returns the reserve to asset decimal factor
     */
    function getReserveToAssetDecimalFactor() external view returns (uint256);
}