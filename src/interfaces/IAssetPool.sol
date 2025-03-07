// SPDX-License-Identifier: GPL-3.0-or-later
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IXToken} from "./IXToken.sol";
import {IPoolLiquidityManager} from "./IPoolLiquidityManager.sol";
import {IAssetOracle} from "./IAssetOracle.sol";
import {IPoolCycleManager} from "./IPoolCycleManager.sol";
import {IInterestRateStrategy} from "./IInterestRateStrategy.sol";

/**
 * @title IAssetPool
 * @notice Interface for the AssetPool contract which manages user positions and requests
 * @dev Handles user deposits, withdrawals, and position management
 */
interface IAssetPool {
    /**
     * @notice User request for deposit or redemption
     * @param amount Amount of tokens in the request
     * @param collateralAmount Amount of collateral locked with the request
     * @param isDeposit Whether it's a deposit (true) or redemption (false)
     * @param requestCycle Cycle when request was made
     */
    struct UserRequest {
        uint256 amount;
        uint256 collateralAmount;
        bool isDeposit;
        uint256 requestCycle;
    }

    /**
     * @notice User position in the protocol
     * @param collateralAmount Amount of collateral provided
     * @param scaledInterest User's scaled interest value for debt calculation
     */
    struct Position {
        uint256 collateralAmount;
        uint256 scaledInterest;
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
     * @notice Emitted when a user makes a redemption request
     * @param user Address of the user requesting the burn
     * @param assetAmount Amount of asset tokens to be burned for reserves
     * @param cycleIndex Current operational cycle index
     */
    event RedemptionRequested(address indexed user, uint256 assetAmount, uint256 indexed cycleIndex);

    /**
     * @notice Emitted when a user cancels their redemption request
     * @param user Address of the user canceling the redemption
     * @param amount Amount of asset tokens being returned
     * @param cycleIndex Current operational cycle index
     */
    event RedemptionCancelled(address indexed user, uint256 amount, uint256 indexed cycleIndex);

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
     * @notice Emitted when a position is liquidated
     * @param user Address of the user whose position was liquidated
     * @param liquidator Address of the liquidator
     * @param reward Amount of collateral given as reward
     */
    event PositionLiquidated(address indexed user, address indexed liquidator, uint256 reward);

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
     * @notice Allows users to cancel their pending request
     */
    function cancelRequest() external;

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
     * @notice Liquidate an undercollateralized position
     * @param user Address of the user whose position to liquidate
     */
    function liquidatePosition(address user) external;

    // --------------------------------------------------------------------------------
    //                               EXTERNAL FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
    * @notice Deducts interest from the pool and transfers it to the liquidity manager
    * @param amount Amount of interest to deduct
    */
    function deductInterest(uint256 amount) external;


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
     * @notice Check collateral health status of a user
     * @param user User address
     * @return health 3 = Healthy, 2 = Warning, 1 = Liquidatable
     */
    function getCollateralHealth(address user) external view returns (uint8 health);

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
     * @return requiredCollateral Minimum required collateral
     * @return isLiquidatable Whether position can be liquidated
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
     * @return collateralAmount Collateral locked in the request
     * @return isDeposit Whether it's a deposit or redemption
     * @return requestCycle Cycle when request was made
     */
    function userRequest(address user) external view returns (
        uint256 amount,
        uint256 collateralAmount,
        bool isDeposit,
        uint256 requestCycle
    );

    /**
     * @notice Get healthy collateral ratio
     * @return The healthy collateral ratio (scaled by 10000)
     */
    function healthyCollateralRatio() external view returns (uint256);

    /**
     * @notice Get the liquidation threshold
     * @return The liquidation threshold (scaled by 10000)
     */
    function liquidationThreshold() external view returns (uint256);

    /**
     * @notice Get the liquidation reward
     * @return The liquidation reward (scaled by 10000)
     */
    function liquidationReward() external view returns (uint256);

    /**
     * @notice Get total pending deposit requests for the current cycle
     * @return Total amount of pending deposits
     */
    function cycleTotalDepositRequests() external view returns (uint256);

    /**
     * @notice Get total pending redemption requests for the current cycle
     * @return Total amount of pending redemptions
     */
    function cycleTotalRedemptionRequests() external view returns (uint256);

    /**
     * @notice Total user collateral in the pool
     */
    function totalUserCollateral() external view returns (uint256);

    /**
     * @notice Returns the interest rate strategy
     */
    function interestRateStrategy() external view returns (IInterestRateStrategy);

    /**
     * @notice Calculate current interest rate based on pool utilization
     * @return rate Current interest rate (scaled by 10000)
     */
    function getCurrentInterestRate() external view returns (uint256 rate);

    /**
     * @notice Calculate pool utilization ratio
     * @return utilization Pool utilization as a percentage (scaled by 10000)
     */
    function getPoolUtilization() external view returns (uint256 utilization);

    /**
     * @notice Calculate required collateral for a user
     * @param user Address of the user
     * @return requiredCollateral Required collateral amount
     */
    function calculateRequiredCollateral(address user) external view returns (uint256 requiredCollateral);

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
     * @notice Returns the asset oracle contract
     */
    function getAssetOracle() external view returns (IAssetOracle);

    /**
     * @notice Returns the reserve to asset decimal factor
     */
    function getReserveToAssetDecimalFactor() external view returns (uint256);
}