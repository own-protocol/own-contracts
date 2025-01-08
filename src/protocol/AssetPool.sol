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
    IERC20 public immutable reserveToken;    // Reserve token (e.g., USDC)
    IXToken public immutable assetToken;    // xToken contract (renamed from xToken)
    ILPRegistry public immutable lpRegistry; // LP Registry contract

    // Pool state
    uint256 public cycleIndex;
    uint256 public cycleExpiry;
    CycleState public cycleState;

    // Asset states
    uint256 public reserveBalance;
    uint256 public pendingDeposits;
    uint256 public pendingBurns;

    // Protocol requirements
    uint256 public totalReserveRequired;

    // Rebalancing state
    uint256 public rebalanceParticipants;
    mapping(address => bool) public hasRebalanced;

    // User claim states
    mapping(address => uint256) public unclaimedDeposits;
    mapping(address => uint256) public unclaimedBurns;
    mapping(address => uint256) public lastDepositCycle;
    mapping(address => uint256) public lastBurnCycle;

    // Constants
    uint256 private constant PRECISION = 1e18;
    uint256 private constant PRICE_PRECISION = 1e16;
    uint256 private constant CYCLE_DURATION = 7 days;
    uint256 private constant REBALANCE_WINDOW = 1 days;

    constructor(
        address _reserveToken,
        string memory _xTokenName,
        string memory _xTokenSymbol,
        address _oracle,
        address _lpRegistry
    ) Ownable(msg.sender) {
        if (_reserveToken == address(0) || _oracle == address(0) || _lpRegistry == address(0)) 
            revert ZeroAddress();

        reserveToken = IERC20(_reserveToken);
        assetToken = new xToken(_xTokenName, _xTokenSymbol, _oracle);
        lpRegistry = ILPRegistry(_lpRegistry);
        cycleState = CycleState.ACTIVE;
    }

    modifier onlyLP() {
        if (!lpRegistry.isLP(address(this), msg.sender)) revert NotLP();
        _;
    }

    function deposit(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        if (cycleState != CycleState.ACTIVE) revert InvalidCycleState();
        
        reserveToken.transferFrom(msg.sender, address(this), amount);
        
        pendingDeposits += amount;
        reserveBalance += amount;
        unclaimedDeposits[msg.sender] += amount;
        lastDepositCycle[msg.sender] = cycleIndex;
        
        emit Deposit(msg.sender, amount, cycleIndex);
    }

    function withdraw(uint256 xTokenAmount) external {
        if (xTokenAmount == 0) revert InvalidAmount();
        if (cycleState != CycleState.ACTIVE) revert InvalidCycleState();
        if (assetToken.balanceOf(msg.sender) < xTokenAmount) revert InsufficientBalance();
        
        assetToken.transferFrom(msg.sender, address(this), xTokenAmount);
        pendingBurns += xTokenAmount;
        unclaimedBurns[msg.sender] += xTokenAmount;
        lastBurnCycle[msg.sender] = cycleIndex;
        
        emit WithdrawRequested(msg.sender, xTokenAmount, cycleIndex);
    }

    function claimXTokens() external {
        if (cycleState != CycleState.ACTIVE) revert InvalidCycleState();
        if (lastDepositCycle[msg.sender] >= cycleIndex) revert NothingToClaim();

        uint256 amount = unclaimedDeposits[msg.sender];
        if (amount == 0) revert NothingToClaim();

        unclaimedDeposits[msg.sender] = 0;
        assetToken.mint(msg.sender, amount);

        emit XTokensClaimed(msg.sender, amount, cycleIndex);
    }

    function claimDepositTokens() external {
        if (cycleState != CycleState.ACTIVE) revert InvalidCycleState();
        if (lastBurnCycle[msg.sender] >= cycleIndex) revert NothingToClaim();

        uint256 xTokenAmount = unclaimedBurns[msg.sender];
        if (xTokenAmount == 0) revert NothingToClaim();

        uint256 spotPrice = assetToken.oracle().assetPrice();
        uint256 depositTokenAmount = (xTokenAmount * spotPrice * PRICE_PRECISION) / PRECISION;

        unclaimedBurns[msg.sender] = 0;
        assetToken.burn(address(this), xTokenAmount);
        reserveToken.transfer(msg.sender, depositTokenAmount);

        emit DepositTokensClaimed(msg.sender, depositTokenAmount, cycleIndex);
    }

    function rebalance(uint256 amount) external onlyLP {
        if (cycleState != CycleState.REBALANCING) revert InvalidCycleState();
        if (hasRebalanced[msg.sender]) revert AlreadyRebalanced();
        if (block.timestamp > cycleExpiry + REBALANCE_WINDOW) revert RebalancingExpired();

        (uint256 requiredAmount, bool deficit) = calculateRebalance();

        if (amount > requiredAmount) revert InvalidAmount();
        
        if (deficit){
            reserveToken.transferFrom(msg.sender, address(this), amount);
            reserveBalance += amount;
        } else {
            reserveToken.transfer(msg.sender, amount);
            reserveBalance -= amount;
        }

        hasRebalanced[msg.sender] = true;
        rebalanceParticipants++;

        emit Rebalanced(msg.sender, amount, deficit, cycleIndex);

        // Start new cycle if all LPs have rebalanced
        if (rebalanceParticipants == lpRegistry.getLPCount(address(this))) {
            cycleIndex++;
            cycleExpiry = block.timestamp + CYCLE_DURATION;
            cycleState = CycleState.ACTIVE;
            rebalanceParticipants = 0;
            pendingDeposits = 0;
            pendingBurns = 0;
            
            emit CycleStarted(cycleIndex, block.timestamp);
        }
    }

    function calculateRebalance() internal view returns (uint256 amount, bool deficit) {
        uint256 xTokenSupply = assetToken.totalSupply();
        uint256 spotPrice = assetToken.oracle().assetPrice();

        uint256 baseReserveRequired = (xTokenSupply - pendingBurns) * PRECISION;
        uint256 redemptionReserveRequired = (pendingBurns * spotPrice * PRICE_PRECISION) / PRECISION;
        
        uint256 _totalReserveRequired = baseReserveRequired + redemptionReserveRequired + pendingDeposits;

        if (_totalReserveRequired > reserveBalance) {
            return (_totalReserveRequired - reserveBalance, true);
        } else {
            return (reserveBalance - _totalReserveRequired, false);
        }
    }
}