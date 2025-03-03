// SPDX-License-Identifier: GPL-3.0-or-later
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IXToken} from "./IXToken.sol";
import {IPoolLiquidityManager} from "./IPoolLiquidityManager.sol";
import {IAssetOracle} from "./IAssetOracle.sol";
import {IPoolCycleManager} from "./IPoolCycleManager.sol";

/**
 * @title IAssetPool
 * @notice Interface for the AssetPool contract which manages user positions and requests
 * @dev Handles user deposits, withdrawals, and position management
 */
interface IAssetPool {
    /**
     * @notice Structure to hold user's deposit or redemption request
     * @param amount Amount of tokens (reserve for deposit, asset for redemption)
     * @param isDeposit True for deposit, false for redemption
     * @param requestCycle Cycle when request was made
     */
    struct UserRequest {
        uint256 amount;
        bool isDeposit;
        uint256 requestCycle;
    }

    /**
     * @notice Structure to hold user's position data
     * @param collateralAmount Amount of collateral deposited
     * @param lastInterestCycle Last cycle when interest was charged
     */
    struct Position {
        uint256 collateralAmount;
        uint256 lastInterestCycle;
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

    /**
     * @notice Emitted when interest is charged
     * @param user Address of the user
     * @param amount Amount of interest charged
     * @param cycleIndex Cycle index when interest was charged
     */
    event InterestCharged(address indexed user, uint256 amount, uint256 indexed cycleIndex);

    /**
     * @notice Emitted when interest is distributed to LPs
     * @param amount Total interest amount distributed
     * @param cycleIndex Cycle index when the distribution occurred
     */
    event InterestDistributed(uint256 amount, uint256 indexed cycleIndex);

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

    // --------------------------------------------------------------------------------
    //                                USER ACTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Allows users to deposit reserve tokens into the pool
     * @param amount Amount of reserve tokens to deposit
     */
    function depositRequest(uint256 amount) external;

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
     * @notice Claim processed request
     */
    function claimRequest() external;

    /**
     * @notice Allows users to deposit collateral
     * @param amount Amount of collateral to deposit
     */
    function depositCollateral(uint256 amount) external;

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
    //                          INTEREST MANAGEMENT
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
    //                               VIEW FUNCTIONS
    // --------------------------------------------------------------------------------

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
     * @return isDeposit Whether it's a deposit or redemption
     * @return requestCycle Cycle when request was made
     */
    function userRequest(address user) external view returns (
        uint256 amount,
        bool isDeposit,
        uint256 requestCycle
    );

    /**
     * @notice Get the minimum collateral ratio
     * @return The minimum collateral ratio (scaled by 10000)
     */
    function getMinCollateralRatio() external view returns (uint256);

    /**
     * @notice Get the liquidation threshold
     * @return The liquidation threshold (scaled by 10000)
     */
    function getLiquidationThreshold() external view returns (uint256);

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
     * @notice Returns the interest rate strategy
     */
    function interestRateStrategy() external view returns (uint256);

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