// SPDX-License-Identifier: GPL-3.0-or-later
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IXToken} from "./IXToken.sol";
import {IPoolLiquidityManager} from "./IPoolLiquidityManager.sol";
import {IAssetOracle} from "./IAssetOracle.sol";
import {IPoolCycleManager} from "./IPoolCycleManager.sol";
import {IPoolStrategy} from "./IPoolStrategy.sol";

/**
 * @title IAssetPool
 * @notice Interface for the AssetPool contract which manages user positions and requests
 * @dev Handles user deposits, withdrawals, and position management
 */
interface IAssetPool {

    /**
     * @notice Request type enum to track different kinds of User requests
     */
    enum RequestType {
        NONE,       // No active request
        DEPOSIT,    // Request to deposit
        REDEEM,     // Request to redeem
        LIQUIDATE   // Request for liquidation
    }

    /**
     * @notice User request for deposit or redemption
     * @param requestType Type of request
     * @param amount Amount of tokens in the request
     * @param collateralAmount Amount of collateral locked with the request
     * @param requestCycle Cycle when request was made
     */
    struct UserRequest {
        RequestType requestType;
        uint256 amount;
        uint256 collateralAmount;
        uint256 requestCycle;
    }

    /**
     * @notice User position in the protocol
     * @param assetAmount Amount of asset tokens held
     * @param collateralAmount Amount of collateral provided
     */
    struct UserPosition {
        uint256 assetAmount;
        uint256 collateralAmount;
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
     * @notice Emitted when a user claims their minted asset tokens
     * @param user Address of the user claiming assets
     * @param amount Amount of asset tokens claimed
     * @param cycleIndex Cycle index when the claim was processed
     */
    event AssetClaimed(address indexed user, uint256 amount, uint256 indexed cycleIndex);

    /**
     * @notice Emitted when a user makes a redemption request
     * @param user Address of the user requesting the burn
     * @param assetAmount Amount of asset tokens to be burned for reserves
     * @param cycleIndex Current operational cycle index
     */
    event RedemptionRequested(address indexed user, uint256 assetAmount, uint256 indexed cycleIndex);

    /**
     * @notice Emitted when a user withdraws reserve tokens after burning
     * @param user Address of the user withdrawing reserves
     * @param amount Amount of reserve tokens withdrawn
     * @param cycleIndex Cycle index when the withdrawal was processed
     */
    event ReserveWithdrawn(address indexed user, uint256 amount, uint256 indexed cycleIndex);

    /**
     * @notice Emitted when collateral is deposited
     * @param user Address of the user depositing collateral
     * @param amount Amount of collateral deposited
     */
    event CollateralDeposited(address indexed user, uint256 amount);

    /**
     * @notice Emitted when collateral is withdrawn
     * @param user Address of the user withdrawing collateral
     * @param amount Amount of collateral withdrawn
     */
    event CollateralWithdrawn(address indexed user, uint256 amount);

    /**
     * @notice Emitted when fee is deducted from user
     * @param user Address of the user
     * @param amount Amount of fee deducted
     */
    event FeeDeducted(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a position is liquidated
     * @param user Address of the user whose position was liquidated
     * @param liquidator Address of the liquidator
     * @param reward Amount of collateral given as reward
     */
    event PositionLiquidated(address indexed user, address indexed liquidator, uint256 reward);

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
     * @notice Emitted when interest is distributed to an LP
     * @param lp Address of the LP
     * @param amount Amount of interest distributed
     * @param cycleIndex Index of the cycle
     */
    event InterestDistributedToLP(
        address indexed lp,
        uint256 indexed amount,
        uint256 indexed cycleIndex
    );

    /**
     * @notice Emitted when a liquidation is requested
     * @param user Address of the user being liquidated
     * @param liquidator Address of the liquidator
     * @param amount Amount of tokens being liquidated
     * @param cycleIndex Cycle index when the request was made
     */
    event LiquidationRequested(
        address indexed user, 
        address liquidator, 
        uint256 indexed amount, 
        uint256 indexed cycleIndex
    );

    /**
     * @notice Emitted when a liquidation is cancelled
     * @param user Address of the user
     * @param liquidator Address of the liquidator
     * @param amount Amount of tokens returned to liquidator
     */
    event LiquidationCancelled(
        address indexed user, 
        address indexed liquidator, 
        uint256 amount
    );

    /**
     * @notice Emitted when a liquidation is claimed
     * @param user Address of the user
     * @param liquidator Address of the liquidator
     * @param amount Amount of tokens liquidated
     * @param redemptionAmount Amount of reserve tokens for redemption
     * @param rewardAmount Amount of reward tokens
     */
    event LiquidationClaimed(
        address indexed user, 
        address indexed liquidator, 
        uint256 amount, 
        uint256 redemptionAmount, 
        uint256 rewardAmount
    );

    // --------------------------------------------------------------------------------
    //                                     ERRORS
    // --------------------------------------------------------------------------------

    /// @notice Thrown when a user has insufficient balance for an operation
    error InsufficientBalance();
    /// @notice Thrown when a function is called by an address that is not the PoolCycleManager
    error NotPoolCycleManager();
    /// @notice Thrown when attempting to claim with no pending claims
    error NothingToClaim();
    /// @notice Thrown when attempting to cancel with no pending requests
    error NothingToCancel();
    /// @notice Thrown when user has a pending mint or burn request
    error RequestPending();
    /// @notice Thrown when a user attempts to withdraw more collateral than allowed
    error ExcessiveWithdrawal();
    /// @notice Thrown when trying to liquidate a position that isn't eligible
    error PositionNotLiquidatable();
    /// @notice Thrown when a user has insufficient collateral to make a deposit
    error InsufficientCollateral();
    /// @notice Thrown when an is zero address
    error ZeroAddress();
    /// @notice Thrown when the amount is invalid
    error InvalidAmount();
    /// @notice Thrown when the caller is unauthorized
    error Unauthorized();
    /// @notice Thrown when the pool utilization exceeds the limit
    error PoolUtilizationExceeded();
    /// @notice Thrown when redemption request is invalid
    error InvalidRedemptionRequest();
    /// @notice Thrown when pool has insufficient liquidity
    error InsufficientLiquidity();
    /// @notice Thrown when liquidation request is invalid
    error InvalidLiquidationRequest();
    /// @notice Thrown when liquidation amount exceeds the limit
    error ExcessiveLiquidationAmount(uint256 amount, uint256 maxLiquidationAmount);
    /// @notice Thrown when a better liquidation request exists
    error BetterLiquidationRequestExists();

    // --------------------------------------------------------------------------------
    //                                USER ACTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Make a deposit request
     * @param amount Amount of reserve tokens to deposit
     * @param collateralAmount Amount of collateral to provide
     */
    function depositRequest(uint256 amount, uint256 collateralAmount) external;

    /**
     * @notice Creates a redemption request for the user
     * @param amount Amount of asset tokens to burn
     */
    function redemptionRequest(uint256 amount) external;

    /**
     * @notice Claim processed request for the user
     */
    function claimRequest(address user) external;

    /**
     * @notice Allows users to deposit additional collateral
     * @param amount Amount of collateral to deposit
     */
    function addCollateral(uint256 amount) external;

    /**
     * @notice Allows users to withdraw excess collateral
     * @param amount Amount of collateral to withdraw
     */
    function withdrawCollateral(uint256 amount) external;

    /**
     * @notice Initiates a liquidation request for an underwater position
     * @param user Address of the user whose position is to be liquidated
     * @param amount Amount of asset to liquidate (must be <= 30% of user's position)
     */
    function requestLiquidation(address user, uint256 amount) external;

    /**
     * @notice Process a liquidation claim after the cycle is completed
     * @param user Address of the user whose position was liquidated
     */
    function claimLiquidation(address user) external;

    // --------------------------------------------------------------------------------
    //                      EXTERNAL FUNCTIONS (POOL CYCLE MANAGER)
    // --------------------------------------------------------------------------------

    /**
     * @notice Transfers rebalance amount from the pool to the LP during negative rebalance
     * @param lp Address of the LP to whom rebalance amount is owed
     * @param amount Amount of reserve tokens to transfer to the LP
     */
    function transferRebalanceAmount(address lp, uint256 amount) external;

    /**
    * @notice Deducts interest from the pool and transfers it to the liquidity manager
    * @param lp Address of the LP to whom interest is owed
    * @param amount Amount of interest to deduct
    */
    function deductInterest(address lp, uint256 amount) external;

    /**
     * @notice Update cycle data at the end of a cycle
     */
    function updateCycleData(uint256 rebalancePrice, int256 rebalanceAmount) external;

    // --------------------------------------------------------------------------------
    //                               VIEW FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Calculate interest debt for a user
     * @param user User address
     * @return interestDebt Amount of interest debt in reserve tokens
     */
    function getInterestDebt(address user) external view returns (uint256 interestDebt);

    /**
     * @notice Get a user's collateral amount
     * @param user Address of the user
     * @return amount User's collateral amount
     */
    function userCollateral(address user) external view returns (uint256 amount);

    /**
     * @notice Get a user's position details
     * @param user Address of the user
     * @return assetAmount Amount of asset tokens in position
     * @return collateralAmount Amount of collateral in position
     * @return interestDebt Amount of interest debt in reserve tokens
     */
    function userPosition(address user) external view returns (
        uint256 assetAmount,
        uint256 collateralAmount,
        uint256 interestDebt
    );

    /**
     * @notice Get a user's pending request
     * @param user Address of the user
     * @return requestType Type of request
     * @return amount Amount involved in the request
     * @return collateralAmount Collateral locked in the request
     * @return requestCycle Cycle when request was made
     */
    function userRequest(address user) external view returns (
        RequestType requestType,
        uint256 amount,
        uint256 collateralAmount,
        uint256 requestCycle
    );

    /**
     * @notice Get users's current liquidation initiator
     * @param user Address of the user
     */
    function getUserLiquidationIntiator(address user) external view returns (address);

    /**
     * @notice Get total pending deposits for the current cycle
     * @return Total amount of pending deposits
     */
    function cycleTotalDeposits() external view returns (uint256);

    /**
     * @notice Get total pending redemptions for the current cycle
     * @return Total amount of pending redemptions
     */
    function cycleTotalRedemptions() external view returns (uint256);

    /**
     * @notice Returns reserve token balance of the pool (excluding new deposits).
     */
    function poolReserveBalance() external view returns (uint256);

    /**
     * @notice Calculate current interest rate based on pool utilization
     * @return rate Current interest rate (scaled by 10000)
     */
    function getCurrentInterestRate() external view returns (uint256 rate);

    /**
     * @notice Calculate interest rate based on pool utilization (including cycle changes)
     * @dev This function gives the expected interest rate for the next cycle
     * @dev It takes into account the new deposits, redemptions & liquidity changes in the cycle
     * @return rate interest rate (scaled by 10000)
     */
    function getCycleInterestRate() external view returns (uint256 rate);

    /**
     * @notice Calculate pool utilization ratio
     * @return utilization Pool utilization as a percentage (scaled by 10000)
     */
    function getPoolUtilization() external view returns (uint256 utilization);

    /**
     * @notice Calculate pool utilization ratio (including cycle changes)
     * @dev This function gives the expected utilization for the next cycle
     * @dev It takes into account the new deposits, redemptions & liquidity changes in the cycle
     * @return utilization Pool utilization as a percentage (scaled by 10000)
     */    
    function getCyclePoolUtilization() external view returns (uint256 utilization);

    /**
     * @notice Calculate utilised liquidity in the pool
     * @return utilisedLiquidity Total utilised liquidity in reserve tokens
     */
    function getUtilisedLiquidity() external view returns (uint256);

    /**
     * @notice Calculate utilised liquidity in the pool (including cycle changes)
     * @dev This function gives the expected utilised liquidity for the next cycle
     * @dev It takes into account the new deposits, redemptions & liquidity changes in the cycle
     * @return utilisedLiquidity Total utilised liquidity in reserve tokens
     */
    function getCycleUtilisedLiquidity() external view returns (uint256);

     /**
     * @notice Calculate pool value
     * @return value Pool value in reserve tokens
     */
    function getPoolValue() external view returns (uint256 value);

    // --------------------------------------------------------------------------------
    //                               DEPENDENCIES
    // --------------------------------------------------------------------------------

    /**
     * @notice Returns the reserve token contract
     */
    function getReserveToken() external view returns (IERC20Metadata);

    /**
     * @notice Returns the asset token contract
     */
    function getAssetToken() external view returns (IXToken);

    /**
     * @notice Returns the pool cycle manager contract
     */
    function getPoolCycleManager() external view returns (IPoolCycleManager);

    /**
     * @notice Returns the pool liquidity manager contract
     */
    function getPoolLiquidityManager() external view returns (IPoolLiquidityManager);

    /**
     * @notice Returns the pool strategy contract
     */
    function getPoolStrategy() external view returns (IPoolStrategy);

    /**
     * @notice Returns the asset oracle contract
     */
    function getAssetOracle() external view returns (IAssetOracle);

    /**
     * @notice Returns the reserve to asset decimal factor
     */
    function getReserveToAssetDecimalFactor() external view returns (uint256);
}