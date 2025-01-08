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

    event Deposit(address indexed user, uint256 amount, uint256 indexed cycleIndex);
    event WithdrawRequested(address indexed user, uint256 xTokenAmount, uint256 indexed cycleIndex);
    event Rebalanced(address indexed lp, uint256 amount, bool isDeficit, uint256 indexed cycleIndex);
    event CycleStarted(uint256 indexed cycleIndex, uint256 timestamp);
    event XTokensClaimed(address indexed user, uint256 amount, uint256 indexed cycleIndex);
    event DepositTokensClaimed(address indexed user, uint256 amount, uint256 indexed cycleIndex);

    error InvalidAmount();
    error InsufficientBalance();
    error NotLP();
    error InvalidCycleState();
    error AlreadyRebalanced();
    error RebalancingExpired();
    error ZeroAddress();
    error NothingToClaim();

    // User actions
    function deposit(uint256 amount) external;
    function withdraw(uint256 xTokenAmount) external;
    function claimXTokens() external;
    function claimDepositTokens() external;

    // LP actions
    function rebalance(uint256 amount) external;

    // View functions
    function cycleState() external view returns (CycleState);
    function cycleIndex() external view returns (uint256);
    function unclaimedDeposits(address user) external view returns (uint256);
    function unclaimedBurns(address user) external view returns (uint256);
}