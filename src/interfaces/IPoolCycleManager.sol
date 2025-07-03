// SPDX-License-Identifier: GPL-3.0-or-later
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IXToken} from "./IXToken.sol";
import {IPoolLiquidityManager} from "./IPoolLiquidityManager.sol";
import {IAssetOracle} from "./IAssetOracle.sol";
import {IAssetPool} from "./IAssetPool.sol";

/**
 * @title IPoolCycleManager
 * @notice Interface for the PoolCycleManager contract which manages the lifecycle of operational cycles
 * @dev Handles cycle transitions and LP rebalancing operations
 */
interface IPoolCycleManager {
    /**
     * @notice Enum representing the current state of the pool's operational cycle
     * @param POOL_ACTIVE Normal operation state where users can deposit and redeem
     * @param POOL_REBALANCING_OFFCHAIN State during which LPs adjust their asset positions offchain
     * @param POOL_REBALANCING_ONCHAIN State during which LPs rebalance the pool onchain
     * @param POOL_HALTED State when the pool is halted due to rebalance failure or other issues
     */
    enum CycleState {
        POOL_ACTIVE,
        POOL_REBALANCING_OFFCHAIN,
        POOL_REBALANCING_ONCHAIN,
        POOL_HALTED
    }

    // --------------------------------------------------------------------------------
    //                                     EVENTS
    // --------------------------------------------------------------------------------
    
    /**
     * @notice Emitted when an LP completes their rebalancing action
     * @param lp Address of the LP performing the rebalance
     * @param rebalancePrice Price at which the rebalance occurred
     * @param amount Amount of tokens involved in the rebalance
     * @param isDeposit True if LP is depositing, false if withdrawing
     * @param cycleIndex Current operational cycle index
     */
    event Rebalanced(address indexed lp, uint256 rebalancePrice, uint256 amount, bool isDeposit, uint256 indexed cycleIndex);

    /**
     * @notice Emitted when a new operational cycle begins
     * @param cycleIndex Index of the new cycle
     * @param timestamp Block timestamp when the cycle started
     */
    event CycleStarted(uint256 indexed cycleIndex, uint256 timestamp);

    /**
     * @notice Emitted when rebalance amount is transferred to an LP
     * @param lp Address of the LP
     * @param amount Amount of rebalance funds transferred
     * @param cycleIndex Index of the cycle
     */
    event RebalanceAmountTransferred(
        address indexed lp,
        uint256 indexed amount,
        uint256 indexed cycleIndex
    );

    /**
     * @notice Emitted when a rebalance period is initiated
     * @param cycleIndex Current operational cycle index
     * @param cycleState Current state of the cycle
     */
    event RebalanceInitiated(
        uint256 indexed cycleIndex,
        CycleState cycleState
    );

    /**
     * @notice Emitted when interest is accrued
     * @param interestAccrued Amount of interest accrued in this calculation
     * @param timestamp Timestamp when interest was accrued
     */
    event InterestAccrued(
        uint256 interestAccrued,
        uint256 timestamp
    );

    /**
     * @notice Emitted when the price deviation validity is updated
     * @param isPriceDeviationValid New price deviation validity status
     */
    event isPriceDeviationValidUpdated(
        bool isPriceDeviationValid
    );

    // --------------------------------------------------------------------------------
    //                                     ERRORS
    // --------------------------------------------------------------------------------

    /// @notice Thrown when a non-LP address attempts to perform LP actions
    error NotLP();
    /// @notice Thrown when an action is attempted in an invalid cycle state
    error InvalidCycleState();
    /// @notice Thrown when an LP attempts to rebalance multiple times in a cycle
    error AlreadyRebalanced();
    /// @notice Thrown when a rebalance action is attempted after the window has closed
    error RebalancingExpired();
    /// @notice Thrown when an LP has insufficient liquidity for an operation
    error InsufficientLPLiquidity();
    /// @notice Thrown when an LP has insufficient collateral for an operation
    error InsufficientLPCollateral();
    /// @notice Thrown when rebalance parameters don't match requirements
    error RebalanceMismatch();
    /// @notice Thrown when a user attempts to interact with an LP's rebalance
    error InvalidCycleRequest();
    /// @notice Thrown when an someone tries to start a onchain rebalance before offchain rebalance ends
    error OffChainRebalanceInProgress();
    /// @notice Thrown when an someone tries to settle before onchain rebalance ends
    error OnChainRebalancingInProgress();
    /// @notice Thrown when oracle price is not updated
    error OracleNotUpdated();
    /// @notice Thrown when the rebalance price is invalid
    error InvalidRebalancePrice();
    /// @notice Thrown when caller is not authorized
    error UnauthorizedCaller();
    /// @notice Thrown when an is zero address
    error ZeroAddress();
    /// @notice Thrown when the pool utilization exceeds the limit
    error PoolUtilizationExceeded();
    /// @notice Thrown when the market is closed
    error MarketClosed();
    /// @notice Thrown when the market is open
    error MarketOpen();
    /// @notice Thrown when the asset price deviation is too high
    error PriceDeviationHigh();
        /// @notice Thrown when the provided split ratio is invalid
    error InvalidSplit();

    // --------------------------------------------------------------------------------
    //                                  LP ACTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Initiates the off-chain rebalancing period for LPs
     */
    function initiateOffchainRebalance() external;

    /**
     * @notice Initiates the onchain rebalancing period for LPs
     */
    function initiateOnchainRebalance() external;

    /**
     * @notice Allows LPs to perform their rebalancing actions
     * @param lp Address of the LP performing the rebalance
     * @param rebalancePrice Price at which the rebalance is executed
     */
    function rebalancePool(address lp, uint256 rebalancePrice) external;

    /**
     * @notice Rebalance an lp if the rebalance window has expired and the LP has not rebalanced
     * @param lp Address of the LP to settle
     */
    function rebalanceLP(address lp) external;

    /**
     * @notice Force rebalance an lp if the pool halt threshold window has reached and the LP has not rebalanced
     * @dev This is also called the forced settlement step and once settled by all LPs, the pool is halted
     * @param lp Address of the LP to rebalance
     */
    function forceRebalanceLP(address lp) external;

    /**
     * @notice Resolves price deviation by executing a token split or validating the price
     * @param isTokenSplit True if the price shock was due to a stock split
     * @param splitRatio Only used if isTokenSplit is true - numerator of split ratio (e.g., 2 for 2:1 split)
     * @param splitDenominator Only used if isTokenSplit is true - denominator of split ratio (e.g., 1 for 2:1 split)
     */
    function resolvePriceDeviation(
        bool isTokenSplit,
        uint256 splitRatio,
        uint256 splitDenominator
    ) external;

    // --------------------------------------------------------------------------------
    //                               VIEW FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Calculates the expected rebalance amount for a specific LP at a given price
     * @dev This helper function allows LPs to determine how much they need to approve/have available
     * @param lp Address of the LP
     * @param rebalancePrice Price at which to calculate the rebalance
     * @return rebalanceAmount The amount the LP needs to contribute (positive) or will receive (negative)
     * @return isDeposit True if LP needs to deposit funds, false if LP will receive funds
     */
    function calculateLPRebalanceAmount(address lp, uint256 rebalancePrice) external view returns (uint256 rebalanceAmount, bool isDeposit);

    /**
     * @notice Returns information about the pool
     * @return _cycleState Current state of the pool
     * @return _cycleIndex Current operational cycle index
     * @return _assetPrice Last pool rebalance price of the asset
     * @return _lastCycleActionDateTime Timestamp of the last cycle action
     * @return _reserveBackingAsset Amount of reserve token backing the assets.
     * @return _assetBalance Asset token balance of the pool
     * @return _totalDepositRequests Total deposit requests for the cycle
     * @return _totalRedemptionRequests Total redemption requests for the cycle
     */
    function getPoolInfo() external view returns (
        CycleState _cycleState,
        uint256 _cycleIndex,
        uint256 _assetPrice,
        uint256 _lastCycleActionDateTime,
        uint256 _reserveBackingAsset,
        uint256 _assetBalance,
        uint256 _totalDepositRequests,
        uint256 _totalRedemptionRequests
    );

    // --------------------------------------------------------------------------------
    //                               STATE GETTERS
    // --------------------------------------------------------------------------------

    /**
     * @notice Returns the current cycle index
     */
    function cycleIndex() external view returns (uint256);

    /**
     * @notice Returns the current cycle state
     */
    function cycleState() external view returns (CycleState);

    /**
     * @notice Returns the timestamp of the last cycle action
     */
    function lastCycleActionDateTime() external view returns (uint256);

    /**
     * @notice Returns the number of LPs that have completed rebalancing
     */
    function rebalancedLPs() external view returns (uint256);

    /**
     * @notice Returns the last cycle an LP rebalanced
     * @param lp Address of the LP to check
     */
    function lastRebalancedCycle(address lp) external view returns (uint256);

    /**
     * @notice Returns the rebalance price for a specific cycle
     * @param cycle Cycle index to query
     */
    function cycleRebalancePrice(uint256 cycle) external view returns (uint256);

    /**
     * @notice Returns the cumulative pool interest paid per asset till the current cycle.
     * @param cycle Cycle index to query
     */
    function cumulativeInterestIndex(uint256 cycle) external view returns (uint256);

    /**
     * @notice Returns the cycle rebalance amount for the current cycle
     */
    function cycleRebalanceAmount() external view returns (int256);

    /**
     * @notice Returns the interest amount accrued in the current cycle (interms of asset)
     */
    function cycleInterestAmount() external view returns (uint256);

    /**
     * @notice Returns the timestamp of the last interest accrual
     */
    function lastInterestAccrualTimestamp() external view returns (uint256);

    /**
     * @notice Asset price high for the current cycle
     */
    function cyclePriceHigh() external view returns (uint256);

    /**
     * @notice Asset price low for the current cycle
     */
    function cyclePriceLow() external view returns (uint256);

    /**
     * @notice Returns the total number of LPs that need to rebalance in the current cycle
     */
    function cycleLPCount() external view returns (uint256);

    /**
     * @notice Check if the price deviation is valid
     * @return True if the price deviation is valid, false otherwise
     */
    function isPriceDeviationValid() external view returns (bool);

    /**
     * @notice Returns the pool split index, indicating how many splits have occurred
     */
    function poolSplitIndex() external view returns (uint256);

    /**
     * @notice Returns the cumulative split multiplier for a given split index
     * @param splitIndex Index of the split to query
     * @return The cumulative multiplier for the specified split index
     */
    function splitMultiplier(uint256 splitIndex) external view returns (uint256);
}