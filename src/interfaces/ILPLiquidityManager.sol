// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

interface ILPLiquidityManager{
    /**
     * @notice LP's current collateral information
     */
    struct CollateralInfo {
        uint256 collateralAmount;      // Amount of collateral deposited
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
     * @notice Emitted when LP's collateral ratio falls below threshold
     */
    event CollateralWarning(
        address indexed lp,
        uint256 currentRatio,
        uint256 requiredTopUp
    );

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
     * @notice Error when caller is not authorized
     */
    error Unauthorized();

    /**
     * @notice Error when zero address is provided
     */
    error ZeroAddress();

    /**
     * @notice Minimum required collateral ratio (50%)
     */
    function MIN_COLLATERAL_RATIO() external view returns (uint256);

    /**
     * @notice Warning threshold for collateral ratio (30%)
     */
    function COLLATERAL_THRESHOLD() external view returns (uint256);

    /**
     * @notice Get LP's current collateral info
     */
    function getCollateralInfo(address lp) external view returns (CollateralInfo memory);

    /**
     * @notice Calculate required collateral for an LP
     */
    function getRequiredCollateral(address lp) external view returns (uint256);

    /**
     * @notice Calculate current collateral ratio for an LP
     */
    function getCurrentRatio(address lp) external view returns (uint256);

    /**
     * @notice Check LP's collateral status
     */
    function checkCollateralStatus(address lp) external;

    /**
     * @notice Deposit collateral
     */
    function deposit(uint256 amount) external;

    /**
     * @notice Withdraw excess collateral
     */
    function withdraw(uint256 amount) external;

    /**
     * @notice Liquidate an LP below threshold
     */
    function liquidateLP(address lp) external;

    /**
     * @notice Deduct rebalance amount from LP's collateral
     */
    function deductRebalanceAmount(address lp, uint256 amount) external;

    /**
     * @notice Add rebalance amount to LP's collateral
     */
    function addToCollateral(address lp, uint256 amount) external;
}