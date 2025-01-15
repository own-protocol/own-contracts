// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IXToken} from "./IXToken.sol";
import {ILPRegistry} from "./ILPRegistry.sol";
import {IAssetOracle} from "./IAssetOracle.sol";

interface IAssetPool {
    enum CycleState {
        ACTIVE,         // Normal operation
        REBALANCING     // LPs rebalancing reserves
    }

    // --------------------------------------------------------------------------------
    //                                     EVENTS
    // --------------------------------------------------------------------------------
    event DepositRequested(address indexed user, uint256 amount, uint256 indexed cycleIndex);
    event DepositCancelled(address indexed user, uint256 amount, uint256 indexed cycleIndex);
    event AssetClaimed(address indexed user, uint256 amount, uint256 indexed cycleIndex);
    event BurnRequested(address indexed user, uint256 xTokenAmount, uint256 indexed cycleIndex);
    event BurnCancelled(address indexed user, uint256 amount, uint256 indexed cycleIndex);
    event ReserveWithdrawn(address indexed user, uint256 amount, uint256 indexed cycleIndex);
    event Rebalanced(address indexed lp, uint256 amount, bool isDeposit, uint256 indexed cycleIndex);
    event CycleStarted(uint256 indexed cycleIndex, uint256 timestamp);
    event CycleTimeUpdated(uint256 newCycleTime);
    event RebalanceTimeUpdated(uint256 newRebalanceTime);
    event RebalanceInitiated(
        uint256 indexed cycleIndex,
        uint256 spotPrice,
        int256 netReserveDelta,
        int256 rebalanceAmount
    );

    // --------------------------------------------------------------------------------
    //                                     ERRORS
    // --------------------------------------------------------------------------------
    error InvalidAmount();
    error InsufficientBalance();
    error NotLP();
    error InvalidCycleState();
    error AlreadyRebalanced();
    error RebalancingExpired();
    error ZeroAddress();
    error NothingToClaim();
    error NothingToCancel();
    error MintOrBurnPending();

    // --------------------------------------------------------------------------------
    //                                USER ACTIONS
    // --------------------------------------------------------------------------------
    function depositReserve(uint256 amount) external;
    function cancelDeposit() external;
    function mintAsset(address user) external;
    function burnAsset(uint256 assetAmount) external;
    function cancelBurn() external;
    function withdrawReserve(address user) external;

    // --------------------------------------------------------------------------------
    //                                  LP ACTIONS
    // --------------------------------------------------------------------------------
    function initiateRebalance() external;
    function rebalancePool(address lp, uint256 amount, bool isDeposit) external;

    // --------------------------------------------------------------------------------
    //                              GOVERNANCE ACTIONS
    // --------------------------------------------------------------------------------
    function updateCycleTime(uint256 newCycleTime) external;
    function updateRebalanceTime(uint256 newRebalanceTime) external;
    function pausePool() external;
    function unpausePool() external;

    // --------------------------------------------------------------------------------
    //                               VIEW FUNCTIONS
    // --------------------------------------------------------------------------------
    function getGeneralInfo() external view returns (
        uint256 _xTokenSupply,
        CycleState _cycleState,
        uint256 _cycleIndex,
        uint256 _nextRebalanceStartDate,
        uint256 _nextRebalanceEndDate,
        uint256 _assetPrice
    );

    function getLPInfo() external view returns (
        uint256 _totalDepositRequests,
        uint256 _totalRedemptionRequests,
        int256 _netReserveDelta,
        int256 _rebalanceAmount
    );

    // --------------------------------------------------------------------------------
    //                               STATE GETTERS
    // --------------------------------------------------------------------------------
    function reserveToken() external view returns (IERC20);
    function assetToken() external view returns (IXToken);
    function lpRegistry() external view returns (ILPRegistry);
    function assetOracle() external view returns (IAssetOracle);

    function cycleIndex() external view returns (uint256);
    function cycleState() external view returns (CycleState);
    function nextRebalanceStartDate() external view returns (uint256);
    function nextRebalanceEndDate() external view returns (uint256);
    function cycleTime() external view returns (uint256);
    function rebalanceTime() external view returns (uint256);

    function totalReserveBalance() external view returns (uint256);
    function newReserveSupply() external view returns (uint256);
    function newAssetSupply() external view returns (uint256);
    function netReserveDelta() external view returns (int256);
    function rebalanceAmount() external view returns (int256);

    function rebalancedLPs() external view returns (uint256);
    function hasRebalanced(address lp) external view returns (bool);

    function cycleTotalDepositRequests(uint256 cycle) external view returns (uint256);
    function cycleTotalRedemptionRequests(uint256 cycle) external view returns (uint256);
    function cycleDepositRequests(uint256 cycle, address user) external view returns (uint256);
    function cycleRedemptionRequests(uint256 cycle, address user) external view returns (uint256);
    function lastActionCycle(address user) external view returns (uint256);
    function cycleRebalancePrice(uint256 cycle) external view returns (uint256);
}
