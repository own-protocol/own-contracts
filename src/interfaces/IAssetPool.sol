// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IXToken} from "./IXToken.sol";
import {ILPRegistry} from "./ILPRegistry.sol";
import {IAssetOracle} from "./IAssetOracle.sol";

/**
 * @title IAssetPool
 * @notice Interface for the AssetPool contract which manages a decentralized pool of assets
 * @dev Handles deposits, minting, redemptions, and LP rebalancing operations
 */
interface IAssetPool {
    /**
     * @notice Enum representing the current state of the pool's operational cycle
     * @param ACTIVE Normal operation state where users can deposit and withdraw
     * @param REBALANCING State during which LPs adjust their reserve positions
     */
    enum CycleState {
        ACTIVE,
        REBALANCING
    }

    // --------------------------------------------------------------------------------
    //                                     EVENTS
    // --------------------------------------------------------------------------------
    
    /**
     * @notice Emitted when a user requests to deposit reserve tokens
     * @param user Address of the user making the deposit
     * @param amount Amount of reserve tokens being deposited
     * @param cycleIndex Current operational cycle index
     */
    event DepositRequested(address indexed user, uint256 amount, uint256 indexed cycleIndex);

    /**
     * @notice Emitted when a user cancels their deposit request
     * @param user Address of the user canceling the deposit
     * @param amount Amount of reserve tokens being returned
     * @param cycleIndex Current operational cycle index
     */
    event DepositCancelled(address indexed user, uint256 amount, uint256 indexed cycleIndex);

    /**
     * @notice Emitted when a user claims their minted asset tokens
     * @param user Address of the user claiming assets
     * @param amount Amount of asset tokens claimed
     * @param cycleIndex Cycle index when the claim was processed
     */
    event AssetClaimed(address indexed user, uint256 amount, uint256 indexed cycleIndex);

    /**
     * @notice Emitted when a user requests to burn their asset tokens
     * @param user Address of the user requesting the burn
     * @param xTokenAmount Amount of asset tokens to be burned
     * @param cycleIndex Current operational cycle index
     */
    event BurnRequested(address indexed user, uint256 xTokenAmount, uint256 indexed cycleIndex);

    /**
     * @notice Emitted when a user cancels their burn request
     * @param user Address of the user canceling the burn
     * @param amount Amount of asset tokens being returned
     * @param cycleIndex Current operational cycle index
     */
    event BurnCancelled(address indexed user, uint256 amount, uint256 indexed cycleIndex);

    /**
     * @notice Emitted when a user withdraws reserve tokens after burning
     * @param user Address of the user withdrawing reserves
     * @param amount Amount of reserve tokens withdrawn
     * @param cycleIndex Cycle index when the withdrawal was processed
     */
    event ReserveWithdrawn(address indexed user, uint256 amount, uint256 indexed cycleIndex);

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
     * @notice Emitted when the cycle duration is updated
     * @param newCycleTime New duration for operational cycles
     */
    event CycleTimeUpdated(uint256 newCycleTime);

    /**
     * @notice Emitted when the rebalance period duration is updated
     * @param newRebalanceTime New duration for rebalancing periods
     */
    event RebalanceTimeUpdated(uint256 newRebalanceTime);

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

    // --------------------------------------------------------------------------------
    //                                     ERRORS
    // --------------------------------------------------------------------------------

    /// @notice Thrown when an invalid amount is provided for an operation
    error InvalidAmount();
    /// @notice Thrown when a user has insufficient balance for an operation
    error InsufficientBalance();
    /// @notice Thrown when a non-LP address attempts to perform LP actions
    error NotLP();
    /// @notice Thrown when an action is attempted in an invalid cycle state
    error InvalidCycleState();
    /// @notice Thrown when an LP attempts to rebalance multiple times in a cycle
    error AlreadyRebalanced();
    /// @notice Thrown when a rebalance action is attempted after the window has closed
    error RebalancingExpired();
    /// @notice Thrown when a zero address is provided for a critical parameter
    error ZeroAddress();
    /// @notice Thrown when attempting to claim with no pending claims
    error NothingToClaim();
    /// @notice Thrown when attempting to cancel with no pending requests
    error NothingToCancel();
    /// @notice Thrown when user has a pending mint or burn request
    error MintOrBurnPending();
    /// @notice Thrown when attempting operations during an active cycle
    error CycleInProgress();
    /// @notice Thrown when an LP has insufficient liquidity for an operation
    error InsufficientLPLiquidity();
    /// @notice Thrown when rebalance parameters don't match requirements
    error RebalanceMismatch();
    /// @notice Thrown when a user attempts to interact with an LP's rebalance
    error InvalidCycleRequest();
    /// @notice Thrown when an LP tries to settle a rebalance before the rebalance ends
    error RebalancingInProgress();

    // --------------------------------------------------------------------------------
    //                                USER ACTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Allows users to deposit reserve tokens into the pool
     * @param amount Amount of reserve tokens to deposit
     */
    function depositReserve(uint256 amount) external;

    /**
     * @notice Allows users to cancel their pending deposit request
     */
    function cancelDeposit() external;

    /**
     * @notice Mints asset tokens for a user based on their processed deposit
     * @param user Address of the user to mint assets for
     */
    function mintAsset(address user) external;

    /**
     * @notice Burns asset tokens and creates a redemption request
     * @param assetAmount Amount of asset tokens to burn
     */
    function burnAsset(uint256 assetAmount) external;

    /**
     * @notice Allows users to cancel their pending burn request
     */
    function cancelBurn() external;

    /**
     * @notice Allows users to withdraw reserve tokens after burning assets
     * @param user Address of the user to process withdrawal for
     */
    function withdrawReserve(address user) external;

    // --------------------------------------------------------------------------------
    //                                  LP ACTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Initiates the rebalancing period for LPs
     */
    function initiateRebalance() external;

    /**
     * @notice Allows LPs to perform their rebalancing actions
     * @param lp Address of the LP performing the rebalance
     * @param rebalancePrice Price at which the rebalance is executed
     * @param amount Amount of tokens involved in the rebalance
     * @param isDeposit True if depositing, false if withdrawing
     */
    function rebalancePool(address lp, uint256 rebalancePrice, uint256 amount, bool isDeposit) external;

    /**
     * @notice Settle the pool if the rebalance window has expired and pool is not fully rebalanced.
     */
    function settlePool() external;
        
    /**
     * @notice When there is nothing to rebalance, start the new cycle
     */
    function startNewCycle() external;

    // --------------------------------------------------------------------------------
    //                              GOVERNANCE ACTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Updates the duration of operational cycles
     * @param newCycleTime New cycle duration in seconds
     */
    function updateCycleTime(uint256 newCycleTime) external;

    /**
     * @notice Updates the duration of rebalancing periods
     * @param newRebalanceTime New rebalance period duration in seconds
     */
    function updateRebalanceTime(uint256 newRebalanceTime) external;

    /**
     * @notice Pauses all pool operations
     */
    function pausePool() external;

    /**
     * @notice Resumes all pool operations
     */
    function unpausePool() external;

    // --------------------------------------------------------------------------------
    //                               VIEW FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Returns general information about the pool's state
     * @return _xTokenSupply Total supply of asset tokens
     * @return _cycleState Current state of the pool
     * @return _cycleIndex Current operational cycle index
     * @return _nextRebalanceStartDate Start time of next rebalance
     * @return _nextRebalanceEndDate End time of next rebalance
     * @return _assetPrice Current price of the asset
     */
    function getGeneralInfo() external view returns (
        uint256 _xTokenSupply,
        CycleState _cycleState,
        uint256 _cycleIndex,
        uint256 _nextRebalanceStartDate,
        uint256 _nextRebalanceEndDate,
        uint256 _assetPrice
    );

    /**
     * @notice Returns LP-specific information about the pool
     * @return _totalDepositRequests Total pending deposits
     * @return _totalRedemptionRequests Total pending redemptions
     * @return _netReserveDelta Net change in reserves
     * @return _rebalanceAmount Amount to be rebalanced
     */
    function getLPInfo() external view returns (
        uint256 _totalDepositRequests,
        uint256 _totalRedemptionRequests,
        int256 _netReserveDelta,
        int256 _rebalanceAmount
    );

    // --------------------------------------------------------------------------------
    //                               STATE GETTERS
    // --------------------------------------------------------------------------------

    /**
     * @notice Returns the reserve token contract
     */
    function reserveToken() external view returns (IERC20);

    /**
     * @notice Returns the asset token contract
     */
    function assetToken() external view returns (IXToken);

    /**
     * @notice Returns the LP registry contract
     */
    function lpRegistry() external view returns (ILPRegistry);

    /**
     * @notice Returns the asset oracle contract
     */
    function assetOracle() external view returns (IAssetOracle);

    /**
     * @notice Returns the current cycle index
     */
    function cycleIndex() external view returns (uint256);

    /**
     * @notice Returns the current cycle state
     */
    function cycleState() external view returns (CycleState);

    /**
     * @notice Returns the start time of the next rebalance
     */
    function nextRebalanceStartDate() external view returns (uint256);

    /**
     * @notice Returns the end time of the next rebalance
     */
    function nextRebalanceEndDate() external view returns (uint256);

    /**
     * @notice Returns the duration of operational cycles
     */
    function cycleTime() external view returns (uint256);

    /**
     * @notice Returns the duration of rebalance periods
     */
    function rebalanceTime() external view returns (uint256);

    /**
     * @notice Returns the total balance of reserve tokens
     */
    function totalReserveBalance() external view returns (uint256);

    /**
     * @notice Returns the new supply of reserve tokens after rebalance
     */
    function newReserveSupply() external view returns (uint256);

    /**
     * @notice Returns the new supply of asset tokens after rebalance
     */
    function newAssetSupply() external view returns (uint256);

    /**
     * @notice Returns the net change in reserves after rebalance
     */
    function netReserveDelta() external view returns (int256);

    /**
     * @notice Returns the total amount to be rebalanced
     */
    function rebalanceAmount() external view returns (int256);

    /**
     * @notice Returns the number of LPs that have completed rebalancing
     */
    function rebalancedLPs() external view returns (uint256);

    /**
     * @notice Checks if an LP has completed their rebalancing
     * @param lp Address of the LP to check
     */
    function hasRebalanced(address lp) external view returns (bool);

    /**
     * @notice Returns total deposit requests for a specific cycle
     * @param cycle Cycle index to query
     */
    function cycleTotalDepositRequests(uint256 cycle) external view returns (uint256);

    /**
     * @notice Returns total redemption requests for a specific cycle
     * @param cycle Cycle index to query
     */
    function cycleTotalRedemptionRequests(uint256 cycle) external view returns (uint256);

    /**
     * @notice Returns deposit requests for a specific user in a cycle
     * @param cycle Cycle index to query
     * @param user Address of the user to query
     */
    function cycleDepositRequests(uint256 cycle, address user) external view returns (uint256);

    /**
     * @notice Returns redemption requests for a specific user in a cycle
     * @param cycle Cycle index to query
     * @param user Address of the user to query
     */
    function cycleRedemptionRequests(uint256 cycle, address user) external view returns (uint256);

    /**
     * @notice Returns the last cycle index a user interacted with
     * @param user Address of the user to query
     */
    function lastActionCycle(address user) external view returns (uint256);

    /**
     * @notice Returns the rebalance price for a specific cycle
     * @param cycle Cycle index to query
     */
    function cycleRebalancePrice(uint256 cycle) external view returns (uint256);
}