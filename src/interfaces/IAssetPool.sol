// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IXToken} from "./IXToken.sol";
import {ILPRegistry} from "./ILPRegistry.sol";

interface IAssetPool {
    enum CycleState {
        REBALANCING,    // LPs can rebalance
        IN_CYCLE        // Normal cycle operation
    }

    event DepositReceived(address indexed user, uint256 amount, uint256 cycleNumber);
    event WithdrawalRequested(address indexed user, uint256 xTokenAmount, uint256 cycleNumber);
    event XTokensClaimed(address indexed user, uint256 amount, uint256 cycleNumber);
    event DepositTokensClaimed(address indexed user, uint256 depositTokenAmount, uint256 cycleNumber);
    event CycleStarted(uint256 cycleNumber, uint256 timestamp);
    event CycleStateUpdated(CycleState newState);
    event Rebalanced(address indexed lp, uint256 lpAdded, uint256 lpWithdrawn);
    event RebalancingCompleted(uint256 cycleNumber);

    error InvalidState();
    error NotLP();
    error InvalidAmount();
    error InsufficientBalance();
    error NotInRebalancingPeriod();
    error RebalancingAlreadyDone();
    error NothingToClaim();
    error ZeroAddress();

    function deposit(uint256 amount) external;
    function requestWithdrawal(uint256 xTokenAmount) external;
    function claimXTokens() external;
    function claimDepositTokens() external;
    function rebalance(uint256 lpAdded, uint256 lpWithdrawn) external;
    function checkAndStartNewCycle() external;

    function assetToken() external view returns (IXToken);
    function depositToken() external view returns (IERC20);
    function lpRegistry() external view returns (ILPRegistry);
    function assetSymbol() external view returns (string memory);
    function cycleLength() external view returns (uint256);
    function rebalancingPeriod() external view returns (uint256);
    function currentCycleStart() external view returns (uint256);
    function currentCycleNumber() external view returns (uint256);
    function currentState() external view returns (CycleState);
    function unclaimedDeposits(address user) external view returns (uint256);
    function unclaimedWithdrawals(address user) external view returns (uint256);
    function lastDepositCycle(address user) external view returns (uint256);
    function lastWithdrawalCycle(address user) external view returns (uint256);
    function cycleRebalanced(address lp) external view returns (bool);
    function rebalancedLPCount() external view returns (uint256);
}