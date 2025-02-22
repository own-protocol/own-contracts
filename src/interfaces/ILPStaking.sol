// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

interface ILPStaking {
    /**
     * @notice LP's current staking information
     */
    struct StakeInfo {
        uint256 stakedAmount;      // Amount of reserve tokens staked
        uint256 assetsHeld;        // Amount of assets LP is responsible for
        uint256 lastRebalanceTime; // Last time LP submitted rebalance
    }

    /**
     * @notice Emitted when an LP stakes collateral
     */
    event Staked(address indexed lp, uint256 amount);

    /**
     * @notice Emitted when an LP withdraws collateral
     */
    event Withdrawn(address indexed lp, uint256 amount);

    /**
     * @notice Emitted when an LP's asset position is updated
     */
    event PositionUpdated(address indexed lp, uint256 newAssetAmount);

    /**
     * @notice Emitted when an LP submits a rebalance price
     */
    event RebalancePriceSubmitted(address indexed lp, uint256 price);

    /**
     * @notice Emitted when rebalance amount is deducted from LP's stake
     */
    event RebalanceDeducted(address indexed lp, uint256 amount);

    /**
     * @notice Emitted when LP's collateral ratio falls below threshold
     */
    event CollateralWarning(
        address indexed lp,
        uint256 currentRatio,
        uint256 requiredTopUp
    );

    /**
     * @notice Error when collateral would fall below minimum ratio
     */
    error InsufficientCollateral(uint256 current, uint256 minimum);

    /**
     * @notice Error when price deviates too much from oracle
     */
    error PriceDeviationTooHigh(uint256 submitted, uint256 oracle);

    /**
     * @notice Error when caller isn't authorized
     */
    error Unauthorized();

    /**
     * @notice Error when trying to stake 0
     */
    error ZeroAmount();

    /**
     * @notice Minimum required collateral ratio (50%)
     */
    function MIN_COLLATERAL_RATIO() external view returns (uint256);

    /**
     * @notice Warning threshold for collateral ratio (30%)
     */
    function COLLATERAL_THRESHOLD() external view returns (uint256);

    /**
     * @notice Get LP's current stake info
     */
    function getStakeInfo(address lp) external view returns (StakeInfo memory);

    /**
     * @notice Calculate required collateral for given asset amount
     */
    function getRequiredCollateral(uint256 assetAmount) external view returns (uint256);

    /**
     * @notice Calculate current collateral ratio for an LP
     */
    function getCurrentRatio(address lp) external view returns (uint256);

    /**
     * @notice Stake collateral
     */
    function stake(uint256 amount) external;

    /**
     * @notice Withdraw excess collateral
     */
    function withdraw(uint256 amount) external;

    /**
     * @notice Update LP's asset position from pool
     */
    function updateLPPosition(address lp, uint256 newAssetAmount) external;

    /**
     * @notice Submit rebalance price
     */
    function submitRebalancePrice(uint256 price) external;

    /**
     * @notice Deduct rebalance amount from stake
     */
    function deductRebalanceAmount(address lp, uint256 amount) external;
}