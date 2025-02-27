// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "../interfaces/IAssetPool.sol";

/**
 * @title IUserPositionManager
 * @notice Interface for managing user positions, collateral, and interest payments
 * @dev Handles deposit/redemption requests and positions lifecycle
 */
interface IUserPositionManager {
    // --------------------------------------------------------------------------------
    //                                     EVENTS
    // --------------------------------------------------------------------------------
    
    /**
     * @notice Emitted when a user deposits collateral
     * @param user Address of the user
     * @param amount Amount of collateral deposited
     */
    event CollateralDeposited(address indexed user, uint256 amount);
    
    /**
     * @notice Emitted when a user withdraws collateral
     * @param user Address of the user
     * @param amount Amount of collateral withdrawn
     */
    event CollateralWithdrawn(address indexed user, uint256 amount);
    
    /**
     * @notice Emitted when interest is charged to a user
     * @param user Address of the user
     * @param amount Amount of interest charged
     * @param cycle Cycle when interest was charged
     */
    event InterestCharged(address indexed user, uint256 amount, uint256 indexed cycle);
    
    /**
     * @notice Emitted when a user position is liquidated
     * @param user Address of the user whose position was liquidated
     * @param liquidator Address of the liquidator
     * @param reward Amount of reward paid to the liquidator
     */
    event PositionLiquidated(address indexed user, address indexed liquidator, uint256 reward);
    
    /**
     * @notice Emitted when a user requests a deposit
     * @param user Address of the user
     * @param amount Amount of tokens being deposited
     * @param cycleIndex Current cycle index
     */
    event DepositRequested(address indexed user, uint256 amount, uint256 indexed cycleIndex);
    
    /**
     * @notice Emitted when a user cancels a deposit request
     * @param user Address of the user
     * @param amount Amount of tokens returned
     * @param cycleIndex Current cycle index
     */
    event DepositCancelled(address indexed user, uint256 amount, uint256 indexed cycleIndex);
    
    /**
     * @notice Emitted when a user claims minted assets
     * @param user Address of the user
     * @param amount Amount of asset tokens claimed
     * @param cycleIndex Cycle index when claimed
     */
    event AssetClaimed(address indexed user, uint256 amount, uint256 indexed cycleIndex);
    
    /**
     * @notice Emitted when a user requests redemption
     * @param user Address of the user
     * @param amount Amount of asset tokens to redeem
     * @param cycleIndex Current cycle index
     */
    event RedemptionRequested(address indexed user, uint256 amount, uint256 indexed cycleIndex);
    
    /**
     * @notice Emitted when a user cancels a redemption request
     * @param user Address of the user
     * @param amount Amount of tokens returned
     * @param cycleIndex Current cycle index
     */
    event RedemptionCancelled(address indexed user, uint256 amount, uint256 indexed cycleIndex);
    
    /**
     * @notice Emitted when a user withdraws reserve tokens after redemption
     * @param user Address of the user
     * @param amount Amount of reserve tokens withdrawn
     * @param cycleIndex Cycle index when withdrawn
     */
    event ReserveWithdrawn(address indexed user, uint256 amount, uint256 indexed cycleIndex);

    /**
     * @notice Emitted when interest is distributed to LPs
     * @param amount Total amount of interest distributed
     * @param cycleIndex Cycle when distribution occurred
     */
    event InterestDistributed(uint256 amount, uint256 indexed cycleIndex);

    // --------------------------------------------------------------------------------
    //                                     ERRORS
    // --------------------------------------------------------------------------------
    
    /// @notice Thrown when an invalid amount is provided for an operation
    error InvalidAmount();
    /// @notice Thrown when a user has insufficient balance for an operation
    error InsufficientBalance();
    /// @notice Thrown when a user has insufficient collateral for an operation
    error InsufficientCollateral();
    /// @notice Thrown when a zero address is provided for a critical parameter
    error ZeroAddress();
    /// @notice Thrown when trying to liquidate a healthy position
    error PositionNotLiquidatable();
    /// @notice Thrown when user has no pending request to claim
    error NothingToClaim();
    /// @notice Thrown when user has no pending request to cancel
    error NothingToCancel();
    /// @notice Thrown when user already has a pending request
    error RequestPending();
    /// @notice Thrown when caller is not the asset pool
    error NotAssetPool();
    /// @notice Thrown when an operation is unauthorized
    error Unauthorized();
    /// @notice Thrown when a position is already being liquidated
    error AlreadyLiquidating();
    /// @notice Thrown when trying to withdraw more than available excess
    error ExcessiveWithdrawal();
    
    // --------------------------------------------------------------------------------
    //                           USER COLLATERAL FUNCTIONS
    // --------------------------------------------------------------------------------
    
    /**
     * @notice Deposit collateral into the user's position
     * @param amount Amount of collateral to deposit
     */
    function depositCollateral(uint256 amount) external;
    
    /**
     * @notice Withdraw excess collateral from the user's position
     * @param amount Amount of collateral to withdraw
     */
    function withdrawCollateral(uint256 amount) external;
    
    /**
     * @notice Liquidate a user's position if undercollateralized
     * @param user Address of the user whose position to liquidate
     */
    function liquidatePosition(address user) external;
    
    // --------------------------------------------------------------------------------
    //                           USER REQUEST FUNCTIONS
    // --------------------------------------------------------------------------------
    
    /**
     * @notice Make a deposit request to mint asset tokens
     * @param amount Amount of reserve tokens to deposit
     */
    function depositRequest(uint256 amount) external;
    
    /**
     * @notice Make a redemption request to burn asset tokens for reserves
     * @param amount Amount of asset tokens to redeem
     */
    function redemptionRequest(uint256 amount) external;
    
    /**
     * @notice Cancel a pending deposit or redemption request
     */
    function cancelRequest() external;
    
    /**
     * @notice Claim assets or reserves from a processed request
     */
    function claimRequest() external;
    
    // --------------------------------------------------------------------------------
    //                           INTEREST MANAGEMENT
    // --------------------------------------------------------------------------------
    
    /**
     * @notice Calculate and charge interest to all users with positions
     * @return totalInterest Total interest collected in the cycle
     */
    function chargeInterestForCycle() external returns (uint256 totalInterest);
    
    /**
     * @notice Distribute collected interest to LPs
     */
    function distributeInterestToLPs() external;
    
    // --------------------------------------------------------------------------------
    //                            VIEW FUNCTIONS
    // --------------------------------------------------------------------------------
    
    /**
     * @notice Get a user's total collateral amount
     * @param user Address of the user
     * @return amount The user's total collateral
     */
    function userCollateral(address user) external view returns (uint256 amount);
    
    /**
     * @notice Get a user's current position
     * @param user Address of the user
     * @return assetAmount Amount of asset tokens in the position
     * @return requiredCollateral Minimum collateral required
     * @return isLiquidatable Whether the position can be liquidated
     */
    function userPosition(address user) external view returns (
        uint256 assetAmount,
        uint256 requiredCollateral,
        bool isLiquidatable
    );
    
    /**
     * @notice Get a user's pending request
     * @param user Address of the user
     * @return amount Amount involved in the request
     * @return isDeposit Whether it's a deposit (true) or redemption (false)
     * @return requestCycle Cycle when the request was made
     */
    function userRequest(address user) external view returns (
        uint256 amount,
        bool isDeposit,
        uint256 requestCycle
    );
    
    /**
     * @notice Calculate the current interest rate based on pool utilization
     * @return rate The current interest rate (scaled by 10000, e.g., 500 = 5%)
     */
    function getCurrentInterestRate() external view returns (uint256 rate);
    
    /**
     * @notice Calculate the minimum collateral ratio required for positions
     * @return ratio The minimum collateral ratio (scaled by 10000, e.g., 12000 = 120%)
     */
    function getMinCollateralRatio() external view returns (uint256 ratio);
    
    /**
     * @notice Calculate the liquidation threshold ratio for positions
     * @return ratio The liquidation threshold ratio (scaled by 10000, e.g., 11000 = 110%)
     */
    function getLiquidationThreshold() external view returns (uint256 ratio);
    
    /**
     * @notice Get total pending deposit requests for the current cycle
     * @return amount Total amount of pending deposits
     */
    function cycleTotalDepositRequests() external view returns (uint256 amount);
    
    /**
     * @notice Get total pending redemption requests for the current cycle
     * @return amount Total amount of pending redemptions
     */
    function cycleTotalRedemptionRequests() external view returns (uint256 amount);
}