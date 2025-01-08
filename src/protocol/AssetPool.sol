// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAssetPool} from "../interfaces/IAssetPool.sol";
import {IXToken} from "../interfaces/IXToken.sol";
import {ILPRegistry} from "../interfaces/ILPRegistry.sol";
import {xToken} from "./xToken.sol";

contract AssetPool is IAssetPool, Ownable {
    IXToken public assetToken;
    IERC20 public depositToken;
    ILPRegistry public immutable lpRegistry;
    string public assetSymbol;
    
    uint256 public immutable cycleLength;
    uint256 public immutable rebalancingPeriod;
    uint256 public currentCycleStart;
    uint256 public currentCycleNumber;
    CycleState public currentState;
    
    mapping(address => uint256) public unclaimedDeposits;
    mapping(address => uint256) public unclaimedWithdrawals;
    mapping(address => uint256) public lastDepositCycle;
    mapping(address => uint256) public lastWithdrawalCycle;
    mapping(address => bool) public cycleRebalanced;
    uint256 public rebalancedLPCount;

    constructor(
        string memory _assetSymbol,
        string memory _assetTokenName,
        string memory _assetTokenSymbol,
        address _depositToken,
        address _oracle,
        uint256 _cycleLength,
        uint256 _rebalancingPeriod,
        address _owner,
        address _lpRegistry
    ) Ownable(_owner) {
        if (_depositToken == address(0) || _oracle == address(0) || 
            _lpRegistry == address(0) || _owner == address(0)) revert ZeroAddress();
        
        assetSymbol = _assetSymbol;
        depositToken = IERC20(_depositToken);
        assetToken = new xToken(_assetTokenName, _assetTokenSymbol, _oracle);
        cycleLength = _cycleLength;
        rebalancingPeriod = _rebalancingPeriod;
        currentState = CycleState.IN_CYCLE;
        lpRegistry = ILPRegistry(_lpRegistry);
    }

    modifier onlyLP() {
        if (!lpRegistry.isLP(address(this), msg.sender)) revert NotLP();
        _;
    }

    function deposit(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        
        depositToken.transferFrom(msg.sender, address(this), amount);
        unclaimedDeposits[msg.sender] += amount;
        lastDepositCycle[msg.sender] = currentCycleNumber;
        
        emit DepositReceived(msg.sender, amount, currentCycleNumber);
    }

    function requestWithdrawal(uint256 xTokenAmount) external {
        if (xTokenAmount == 0) revert InvalidAmount();
        if (assetToken.balanceOf(msg.sender) < xTokenAmount) revert InsufficientBalance();
        
        assetToken.transferFrom(msg.sender, address(this), xTokenAmount);
        unclaimedWithdrawals[msg.sender] += xTokenAmount;
        lastWithdrawalCycle[msg.sender] = currentCycleNumber;
        
        emit WithdrawalRequested(msg.sender, xTokenAmount, currentCycleNumber);
    }

    function claimXTokens() external {
        uint256 depositCycle = lastDepositCycle[msg.sender];
        if (depositCycle == 0 || depositCycle >= currentCycleNumber) revert NothingToClaim();
        if (currentState != CycleState.IN_CYCLE) revert InvalidState();
        
        uint256 amount = unclaimedDeposits[msg.sender];
        if (amount == 0) revert NothingToClaim();
        
        unclaimedDeposits[msg.sender] = 0;
        assetToken.mint(msg.sender, amount);
        
        emit XTokensClaimed(msg.sender, amount, currentCycleNumber);
    }

    function claimDepositTokens() external {
        uint256 withdrawalCycle = lastWithdrawalCycle[msg.sender];
        if (withdrawalCycle == 0 || withdrawalCycle >= currentCycleNumber) revert NothingToClaim();
        if (currentState != CycleState.IN_CYCLE) revert InvalidState();
        
        uint256 xTokenAmount = unclaimedWithdrawals[msg.sender];
        if (xTokenAmount == 0) revert NothingToClaim();
        
        uint256 depositTokenAmount = calculateDepositTokenAmount(xTokenAmount);
        
        unclaimedWithdrawals[msg.sender] = 0;
        assetToken.burn(address(this), xTokenAmount);
        depositToken.transfer(msg.sender, depositTokenAmount);
        
        emit DepositTokensClaimed(msg.sender, depositTokenAmount, currentCycleNumber);
    }

    function rebalance(uint256 lpAdded, uint256 lpWithdrawn) external onlyLP {
        if (currentState != CycleState.REBALANCING) revert NotInRebalancingPeriod();
        if (cycleRebalanced[msg.sender]) revert RebalancingAlreadyDone();
        if (block.timestamp > currentCycleStart + rebalancingPeriod) revert NotInRebalancingPeriod();

        if (lpAdded > 0) {
            depositToken.transferFrom(msg.sender, address(this), lpAdded);
        }
        if (lpWithdrawn > 0) {
            depositToken.transfer(msg.sender, lpWithdrawn);
        }

        cycleRebalanced[msg.sender] = true;
        rebalancedLPCount++;

        emit Rebalanced(msg.sender, lpAdded, lpWithdrawn);

        if (rebalancedLPCount == lpRegistry.getLPCount(address(this))) {
            currentState = CycleState.IN_CYCLE;
            rebalancedLPCount = 0;
            emit CycleStateUpdated(CycleState.IN_CYCLE);
            emit RebalancingCompleted(currentCycleNumber);
        }
    }

    function checkAndStartNewCycle() external {
    if (currentState == CycleState.IN_CYCLE && 
        block.timestamp >= currentCycleStart + cycleLength) {
        
        currentCycleNumber++;
        currentCycleStart = block.timestamp;
        currentState = CycleState.REBALANCING;
        rebalancedLPCount = 0;
        
        emit CycleStarted(currentCycleNumber, block.timestamp);
        emit CycleStateUpdated(CycleState.REBALANCING);
    }
}

    function calculateDepositTokenAmount(uint256 xTokenAmount) internal view returns (uint256) {
        uint256 price = assetToken.oracle().assetPrice();
        return (xTokenAmount * price * 1e16) / 1e18;
    }
}