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
     * @param ACTIVE Normal operation state where users can deposit and redeem
     * @param REBALANCING_OFFCHAIN State during which LPs adjust their asset positions offchain
     * @param REBALANCING_ONCHAIN State during which LPs rebalance the pool onchain
     */
    enum CycleState {
        ACTIVE,
        REBALANCING_OFFCHAIN,
        REBALANCING_ONCHAIN
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
     * @notice Emitted when a rebalance period is initiated
     * @param cycleIndex Current operational cycle index
     * @param assetPrice Current price of the asset
     * @param netReserveDelta Net change in reserves required
     * @param rebalanceAmount Total amount to be rebalanced
     */
    event RebalanceInitiated(
        uint256 indexed cycleIndex,
        uint256 assetPrice,
        int256 netReserveDelta,
        int256 rebalanceAmount
    );

    /**
     * @notice Emitted when interest is accrued
     * @param interestAccrued Amount of interest accrued in this calculation
     * @param cumulativeInterest Total cumulative interest after this accrual
     * @param timestamp Timestamp when interest was accrued
     */
    event InterestAccrued(
        uint256 interestAccrued,
        uint256 cumulativeInterest,
        uint256 timestamp
    );
    
    /**
     * @notice Emitted when interest is distributed to an LP
     * @param lp Address of the LP
     * @param amount Amount of interest distributed
     * @param cycleIndex Index of the cycle
     */
    event InterestDistributedToLP(
        address indexed lp,
        uint256 amount,
        uint256 indexed cycleIndex
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
    /// @notice Thrown when attempting operations during an active cycle
    error CycleInProgress();
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
    /// @notice Thrown when price deviation is too high
    error PriceDeviationTooHigh();
    /// @notice Thrown when caller is not authorized
    error UnauthorizedCaller();

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
     * @notice Settle the pool if the rebalance window has expired and pool is not fully rebalanced.
     */
    function settlePool() external;
        
    /**
     * @notice When there is nothing to rebalance, start the new cycle
     */
    function startNewCycle() external;

    // --------------------------------------------------------------------------------
    //                               VIEW FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Returns information about the pool
     * @return _cycleState Current state of the pool
     * @return _cycleIndex Current operational cycle index
     * @return _assetPrice Current price of the asset
     * @return _lastCycleActionDateTime Timestamp of the last cycle action
     * @return _reserveBalance Reserve token balance of the pool
     * @return _assetBalance Asset token balance of the pool
     * @return _totalDepositRequests Total deposit requests for the cycle
     * @return _totalRedemptionRequests Total redemption requests for the cycle
     * @return _netReserveDelta Net change in reserves after rebalance
     * @return _netAssetDelta Net change in assets after rebalance
     * @return _rebalanceAmount Total amount to be rebalanced
     */
    function getPoolInfo() external view returns (
        CycleState _cycleState,
        uint256 _cycleIndex,
        uint256 _assetPrice,
        uint256 _lastCycleActionDateTime,
        uint256 _reserveBalance,
        uint256 _assetBalance,
        uint256 _totalDepositRequests,
        uint256 _totalRedemptionRequests,
        int256 _netReserveDelta,
        int256 _netAssetDelta,
        int256 _rebalanceAmount
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
     * @notice Returns the duration of operational cycles
     */
    function cycleLength() external view returns (uint256);

    /**
     * @notice Returns the duration of rebalance periods
     */
    function rebalanceLength() external view returns (uint256);

    /**
     * @notice Returns reserve token balance of the pool (excluding new deposits).
     */
    function poolReserveBalance() external view returns (uint256);

    /**
     * @notice Returns the net change in reserves after rebalance
     */
    function netReserveDelta() external view returns (int256);

    /**
     * @notice Returns the asset token balance of the pool
     */
    function poolAssetBalance() external view returns (uint256);

    /**
     * @notice Returns the net change in assets after rebalance
     */
    function netAssetDelta() external view returns (int256);

    /**
     * @notice Returns the total amount to be rebalanced
     */
    function rebalanceAmount() external view returns (int256);

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
     * @notice Returns the cumulative interest percent accrued in the pool
     */
    function cumulativePoolInterest() external view returns (uint256);

    /**
     * @notice Returns the cumulative interest amount accrued
     */
    function cumulativeInterestAmount() external view returns (uint256);

    /**
     * @notice Returns the interest amount accrued in the current cycle
     */
    function cycleInterestAmount() external view returns (uint256);

    /**
     * @notice Returns the timestamp of the last interest accrual
     */
    function lastInterestAccrualTimestamp() external view returns (uint256);
}