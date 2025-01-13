// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IXToken} from "./IXToken.sol";
import {ILPRegistry} from "./ILPRegistry.sol";

interface IAssetPool {
    enum CycleState {
        ACTIVE,         // Normal operation
        REBALANCING    // LPs rebalancing reserves
    }

    event DepositRequested(address indexed user, uint256 amount, uint256 indexed cycleIndex);
    event DepositCancelled(address indexed user, uint256 amount, uint256 indexed cycleIndex);
    event AssetClaimed(address indexed user, uint256 amount, uint256 indexed cycleIndex);
    event BurnRequested(address indexed user, uint256 xTokenAmount, uint256 indexed cycleIndex);
    event BurnCancelled(address indexed user, uint256 amount, uint256 indexed cycleIndex);
    event ReserveWithdrawn(address indexed user, uint256 amount, uint256 indexed cycleIndex);
    event Rebalanced(address indexed lp, uint256 amount, bool isDeficit, uint256 indexed cycleIndex);
    event CycleStarted(uint256 indexed cycleIndex, uint256 timestamp);
    event CycleTimeUpdated(uint256 newCycleTime);
    event RebalanceTimeUpdated(uint256 newRebalanceTime);
    event RebalanceInitiated(
        uint256 indexed cycleIndex,
        uint256 spotPrice,
        int256 netSharesDelta,
        int256 netStableDelta
    );

    error InvalidAmount();
    error InsufficientBalance();
    error NotLP();
    error InvalidCycleState();
    error AlreadyRebalanced();
    error RebalancingExpired();
    error ZeroAddress();
    error NothingToClaim();
    error NothingToCancel();

    // User actions
    function depositReserve(uint256 amount) external;
    function cancelDeposit() external;
    function mintAsset(address user) external;
    function burnAsset(uint256 xTokenAmount) external;
    function cancelBurn() external;
    function withdrawReserve(address user) external;

    // LP actions
    function initiateRebalance() external;
    function rebalancePool(address lp, uint256 amount, bool isDeposit) external;

    // Governance actions
    function updateCycleTime(uint256 newCycleTime) external;
    function updateRebalanceTime(uint256 newRebalanceTime) external;
    function pausePool() external;
    function unpausePool() external;

    // View functions
    function getGeneralInfo() external view returns (
        uint256 _reserveBalance,
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
        uint256 _totalReserveRequired,
        uint256 _rebalanceAmount,
        int256 _netReserveDelta,
        int256 _netAssetDelta
    );

    // State getters
    function reserveToken() external view returns (IERC20);
    function assetToken() external view returns (IXToken);
    function lpRegistry() external view returns (ILPRegistry);
    function cycleIndex() external view returns (uint256);
    function cycleState() external view returns (CycleState);
    function nextRebalanceStartDate() external view returns (uint256);
    function nextRebalanceEndDate() external view returns (uint256);
    function cycleTime() external view returns (uint256);
    function rebalanceTime() external view returns (uint256);
    function reserveBalance() external view returns (uint256);
    function totalDepositRequests() external view returns (uint256);
    function totalRedemptionRequests() external view returns (uint256);
    function totalReserveRequired() external view returns (uint256);
    function rebalanceAmount() external view returns (uint256);
    function rebalancedLPs() external view returns (uint256);
    function hasRebalanced(address lp) external view returns (bool);
    function depositRequests(address user) external view returns (uint256);
    function redemptionScaledRequests(address user) external view returns (uint256);
    function lastActionCycle(address user) external view returns (uint256);
}