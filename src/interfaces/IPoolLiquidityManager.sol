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
     * @notice LP position in the protocol
     * @param liquidityCommitment Amount of liquidity committed
     * @param collateralAmount Amount of collateral
     * @param interestAccrued Interest accrued on the position
     */
    struct LPPosition {
        uint256 liquidityCommitment;
        uint256 collateralAmount;
        uint256 interestAccrued;
    }

    /**
     * @notice Request type enum to track different kinds of LP requests
     */
    enum RequestType {
        NONE,           // No active request
        ADD_LIQUIDITY,  // Request to add liquidity
        REDUCE_LIQUIDITY, // Request to reduce liquidity
        LIQUIDATE       // Request for liquidation
    }

    /**
     * @notice LP request struct to track LP requests
     * @param requestType Type of request
     * @param requestAmount Amount involved in the request
     * @param requestCycle Cycle when request was made
     */
    struct LPRequest {
        RequestType requestType;      // Type of request
        uint256 requestAmount;        // Amount involved in the request
        uint256 requestCycle;         // Cycle when request was made
    }

    /**
     * @notice Emitted when an LP deposits collateral
     */
    event CollateralAdded(address indexed lp, uint256 amount);

    /**
     * @notice Emitted when an LP withdraws collateral
     */
    event CollateralReduced(address indexed lp, uint256 amount);

    /**
     * @notice Emitted when interest is claimed by an LP
     */
    event InterestClaimed(address indexed lp, uint256 amount);

    /**
     * @notice Emitted when LP's liquidity is requested to be liquidated
     */
    event LPLiquidationRequested(address indexed lp, uint256 cycle, uint256 amount);

    /**
     * @notice Emitted when LP's liquidity is liquidated
     */
    event LPLiquidationExecuted(address indexed lp, address indexed liquidator, uint256 amount, uint256 reward);

    /**
     * @notice Emitted when an LP adds liquidity
     */
    event LiquidityAdded(address indexed lp, uint256 amount);

    /**
     * @notice Emitted when an LP reduced liquidity
     */
    event LiquidityReduced(address indexed lp, uint256 amount);

    /**
     * @notice Emitted when an LP request to add liquidity is made
     */
    event LiquidityAdditionRequested(address indexed lp, uint256 amount, uint256 cycle);

    /**
     * @notice Emitted when an LP request to reduce liquidity is made
     */
    event LiquidityReductionRequested(address indexed lp, uint256 amount, uint256 cycle);

    /**
     * @notice Emitted when an LP request to liquidate is cancelled
     */
    event LiquidationCancelled(address indexed lp);

    /**
     * @notice Emitted when an LP is added
     */
    event LPAdded(address indexed lp, uint256 amount, uint256 collateral);

    /**
     * @notice Emitted when an LP is removed
     */
    event LPRemoved(address indexed lp);

    /**
     * @notice Emitted when fee is deducted from user
     * @param user Address of the user
     * @param amount Amount of fee deducted
     */
    event FeeDeducted(address indexed user, uint256 amount);

    /**
     * @notice Error when zero amount is provided
     */
    error ZeroAmount();

    /**
     * @notice Error when caller is not a registered LP
     */
    error NotRegisteredLP();

    /**
     * @notice Error when withdrawal amount exceeds available liquidity
     */
    error InvalidWithdrawalAmount();

    /**
     * @notice Error when collateral amount is insufficient
     */
    error InsufficientCollateral();

    /**
     * @notice Error when LP is not eligible for liquidation
     */
    error NotEligibleForLiquidation();

    /**
     * @notice Error when liquidation is invalid
     */
    error InvalidLiquidation();

    /**
     * @notice Error when LP has no interest accrued
     */
    error NoInterestAccrued();

    /**
     * @notice Error when LP has no liquidity to liquidate
     */
    error NoLiquidityToLiquidate();

    /**
     * @notice Error when caller is not the pool cycle manager
     */
    error NotPoolCycleManager();

    /**
     * @notice Error when caller is not the asset pool
     */
    error NotAssetPool();

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
     * @notice Error when pool utilization is too high for requested operation
     */
    error UtilizationTooHighForOperation();

    /**
    * @notice Error when a cycle is not in the required state
    */
    error InvalidCycleState();
    
    /**
     * @notice Error when a request is already pending
     */
    error RequestPending();

    /**
     * @notice Error when operation would exceed available liquidity
     */
    error OperationExceedsAvailableLiquidity(uint256 requested, uint256 available);

    /**
     * @notice Error when collateral health is insufficient
     */
    error InsufficientCollateralHealth(uint256 cuurentHealth);

    /**
     * @notice Total liquidity committed by LPs
     */
    function totalLPLiquidityCommited() external view returns (uint256);

    /**
     * @notice Total lp collateral
     */
    function totalLPCollateral() external view returns (uint256);

    /**
     * @notice Combined reserve balance of the liquidity manager (including collateral and interest)
     */
    function aggregatePoolReserves() external view returns (uint256);
    
    /**
     * @notice Number of registered LPs
     */
    function lpCount() external view returns (uint256);

    /**
     * @notice Add lp liquidity
     * @param amount The amount of liquidity to add
     */
    function addLiquidity(uint256 amount) external;

    /**
     * @notice reduce lp liquidity
     * @param amount The amount of liquidity to reduce
     */
    function reduceLiquidity(uint256 amount) external;

    /**
     * @notice Deposit additional collateral beyond the minimum
     * @param lp Address of the LP
     * @param amount Amount of collateral to add
     */
    function addCollateral(address lp, uint256 amount) external;

    /**
     * @notice Withdraw excess collateral if above minimum requirements
     * @param amount Amount of collateral to reduce
     */
    function reduceCollateral(uint256 amount) external;

    /**
     * @notice Claim interest accrued on LP position
     */
    function claimInterest() external;

    /**
     * @notice Liquidate an LP below threshold
     * @param lp Address of the LP to liquidate\
     * @param liquidationAmount Amount of liquidity to liquidate
     */
    function liquidateLP(address lp, uint256 liquidationAmount) external;

    /**
     * @notice When the pool is halted exit pool
     */
    function exitPool() external;

    /**
     * @notice Add interest amount to LP's position
     * @dev Can be called only by the asset pool contract
     * @param lp Address of the LP
     * @param amount Amount to add
     */
    function addToInterest(address lp, uint256 amount) external;

    /**
     * @notice Add rebalance amount to LP's position
     * @dev During settle pool, we use this to add the rebalance amount to LP's position
     * @dev Can be called only by the asset pool contract
     * @param lp Address of the LP
     * @param amount Amount to add
     */
    function addToCollateral(address lp, uint256 amount) external;

    /**
     * @notice Deduct collateral from LP's position
     * @dev This is used to deduct collateral during lp settlement
     * @param lp Address of the LP
     * @param amount Amount to deduct
     */
    function deductFromCollateral(address lp, uint256 amount) external;

    /**
     * @notice Resolves an LP request after a rebalance cycle
     * @dev This should be called after a rebalance to clear pending request flags
     * @param lp Address of the LP
     */
    function resolveRequest(address lp) external;

    /**
     * @notice Update cycle data at the end of a cycle
     */
    function updateCycleData() external;

    /**
     * @notice Get the total nett liquidity committed by LPs (including cycle changes)
     * @return uint256 Total liquidity committed
     */
    function getCycleTotalLiquidityCommited() external view returns (uint256);

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
     * @notice Get LP's current asset share of the pool
     * @param lp Address of the LP
     */
    function getLPAssetShare(address lp) external view returns (uint256);

    /**
     * @notice Get LP's projected asset share after the current cycle completes based on expected rebalance price
     * @param lp Address of the LP
     * @param expectedRebalancePrice The expected rebalance price provided by the LP
     * @return LP's projected share of the asset supply after cycle completion
     */
    function getLPCycleAssetShare(address lp, uint256 expectedRebalancePrice) external view returns (uint256);
    
    /**
     * @notice Get LP's projected asset share after the current cycle completes based on current oracle price
     * @param lp Address of the LP
     * @return LP's projected share of the asset supply after cycle completion
     */
    function getLPCycleAssetShare(address lp) external view returns (uint256);

    /**
     * @notice Get LP's current liquidity and liquidity info
     * @param lp Address of the LP
     */
    function getLPPosition(address lp) external view returns (LPPosition memory);

    /**
     * @notice Get LP's current collateral amount
     * @param lp Address of the LP
     */
    function getLPCollateral(address lp) external view returns (uint256);

    /**
     * @notice Yield accrued  by the pool reserve tokens (if isYieldBearing)
     */
    function reserveYieldAccrued() external view returns (uint256);

    /**
     * @notice Get LP's current request
     * @param lp Address of the LP
     */
    function getLPRequest(address lp) external view returns (LPRequest memory);

    /**
     * @notice Get LP's current liquidation initiator
     * @param lp Address of the LP
     */
    function getLPLiquidationIntiator(address lp) external view returns (address);
    
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
     * @notice Returns the total amount of liquidity added in the current cycle
     * @return uint256 The total amount of liquidity added
     */
    function cycleTotalAddLiquidityAmount() external view returns (uint256);

    /**
     * @notice Returns the total amount of liquidity reduced in the current cycle
     * @return uint256 The total amount of liquidity reduced
     */
    function cycleTotalReduceLiquidityAmount() external view returns (uint256);
    
    /**
     * @notice Returns the current liquidity commitment of an LP
     * @param lp The address of the LP
     * @return uint256 The current liquidity amount
     */
    function getLPLiquidityCommitment(address lp) external view returns (uint256);

    /**
     * @notice Calculate available liquidity for operations based on current utilization
     * @return availableLiquidity Maximum amount of liquidity available for operations
    */
    function calculateAvailableLiquidity() external view returns (uint256 availableLiquidity);
}