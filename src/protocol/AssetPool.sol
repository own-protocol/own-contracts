// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {IAssetPool} from "../interfaces/IAssetPool.sol";
import {IXToken} from "../interfaces/IXToken.sol";
import {ILPRegistry} from "../interfaces/ILPRegistry.sol";
import {xToken} from "./xToken.sol";

contract AssetPool is IAssetPool, Ownable, Pausable {
    IERC20 public immutable reserveToken;    // Reserve token (e.g., USDC)
    IXToken public immutable assetToken;     // xToken contract
    ILPRegistry public immutable lpRegistry;  // LP Registry contract

    // Pool state
    uint256 public cycleIndex;
    CycleState public cycleState;
    uint256 public nextRebalanceStartDate;
    uint256 public nextRebalanceEndDate;

    // Cycle timing
    uint256 public cycleTime;
    uint256 public rebalanceTime;

    // Asset states
    uint256 public reserveBalance;           // USDC balance
    uint256 public totalDepositRequests;     // Pending deposits
    uint256 public totalRedemptionRequests;  // Pending burns
    uint256 public totalReserveRequired;    // Total reserve required

    uint256 public rebalanceAmount;         // Rebalance amount

    // Rebalancing state
    uint256 public rebalancedLPs;
    mapping(address => bool) public hasRebalanced;

    // User request states
    mapping(address => uint256) public depositRequests;     // Pending deposits per user
    mapping(address => uint256) public redemptionScaledRequests;  // Pending burns per user (in scaled terms)
    mapping(address => uint256) public lastActionCycle;     // Last cycle when user made a request

    // Constants
    uint256 private constant PRECISION = 1e18;

    constructor(
        address _reserveToken,
        string memory _xTokenName,
        string memory _xTokenSymbol,
        address _oracle,
        address _lpRegistry,
        uint256 _cyclePeriod,
        uint256 _rebalancingPeriod,
        address _owner
    ) Ownable(_owner) {
        if (_reserveToken == address(0) || _oracle == address(0) || _lpRegistry == address(0)) 
            revert ZeroAddress();

        reserveToken = IERC20(_reserveToken);
        assetToken = new xToken(_xTokenName, _xTokenSymbol, _oracle);
        lpRegistry = ILPRegistry(_lpRegistry);
        cycleState = CycleState.ACTIVE;
        cycleTime = _cyclePeriod;
        rebalanceTime = _rebalancingPeriod;
    }

    modifier onlyLP() {
        if (!lpRegistry.isLP(address(this), msg.sender)) revert NotLP();
        _;
    }

    modifier notRebalancing() {
        if (cycleState == CycleState.REBALANCING) revert InvalidCycleState();
        _;
    }

    // User Actions
    function depositReserve(uint256 amount) external whenNotPaused notRebalancing {
        if (amount == 0) revert InvalidAmount();
        
        reserveToken.transferFrom(msg.sender, address(this), amount);
        reserveBalance += amount;
        depositRequests[msg.sender] += amount;
        totalDepositRequests += amount;
        lastActionCycle[msg.sender] = cycleIndex;
        
        emit DepositRequested(msg.sender, amount, cycleIndex);
    }

    function cancelDeposit() external notRebalancing {
        uint256 amount = depositRequests[msg.sender];
        if (amount == 0) revert NothingToCancel();
        
        depositRequests[msg.sender] = 0;
        totalDepositRequests -= amount;
        reserveBalance -= amount;
        reserveToken.transfer(msg.sender, amount);
        
        emit DepositCancelled(msg.sender, amount, cycleIndex);
    }

    function mintAsset(address user) external whenNotPaused notRebalancing {
        if (lastActionCycle[user] >= cycleIndex) revert NothingToClaim();
        uint256 amount = depositRequests[user];
        if (amount == 0) revert NothingToClaim();

        depositRequests[user] = 0;
        assetToken.transfer(user, amount);
        
        emit AssetClaimed(msg.sender, amount, cycleIndex);
    }

    function burnAsset(uint256 xTokenAmount) external whenNotPaused notRebalancing {
        if (xTokenAmount == 0) revert InvalidAmount();
        if (assetToken.balanceOf(msg.sender) < xTokenAmount) revert InsufficientBalance();
        
        // Get scaled amount from xToken contract
        uint256 scaledAmount = assetToken.scaledBalanceOf(msg.sender);
        uint256 nominalBalance = assetToken.balanceOf(msg.sender);
        uint256 scaledBurnAmount = (scaledAmount * xTokenAmount) / nominalBalance;
        
        assetToken.transferFrom(msg.sender, address(this), xTokenAmount);
        redemptionScaledRequests[msg.sender] = scaledBurnAmount;
        totalRedemptionRequests += scaledBurnAmount;
        lastActionCycle[msg.sender] = cycleIndex;
        
        emit BurnRequested(msg.sender, xTokenAmount, cycleIndex);
    }

    function cancelBurn() external notRebalancing {
        uint256 scaledAmount = redemptionScaledRequests[msg.sender];
        if (scaledAmount == 0) revert NothingToCancel();
        
        // Convert scaled amount to current nominal amount
        uint256 currentNominalAmount = (scaledAmount * assetToken.totalSupply()) / assetToken.scaledTotalSupply();
        
        redemptionScaledRequests[msg.sender] = 0;
        totalRedemptionRequests -= redemptionScaledRequests[msg.sender];
        assetToken.transfer(msg.sender, currentNominalAmount);
        
        emit BurnCancelled(msg.sender, currentNominalAmount, cycleIndex);
    }

    function withdrawReserve(address user) external whenNotPaused notRebalancing {
        if (lastActionCycle[user] >= cycleIndex) revert NothingToClaim();
        uint256 scaledAmount = redemptionScaledRequests[user];
        if (scaledAmount == 0) revert NothingToClaim();

        // Convert scaled amount to current nominal amount for reserve calculation
        uint256 currentNominalAmount = (scaledAmount * assetToken.totalSupply()) / assetToken.scaledTotalSupply();
        uint256 price = assetToken.oracle().assetPrice();
        uint256 reserveAmount = (currentNominalAmount * price) / PRECISION;
        
        redemptionScaledRequests[user] = 0;
        assetToken.burn(address(this), currentNominalAmount);
        reserveBalance -= reserveAmount;
        reserveToken.transfer(user, reserveAmount);
        
        emit ReserveWithdrawn(user, reserveAmount, cycleIndex);
    }

    // LP Actions
    function rebalance(address lp, uint256 assetPriceRebalancedAt, uint256 amount, bool isClaim) external onlyLP {
        if (cycleState != CycleState.REBALANCING) revert InvalidCycleState();
        if (hasRebalanced[msg.sender]) revert AlreadyRebalanced();
        if (block.timestamp > nextRebalanceEndDate) revert RebalancingExpired();
        
        _validateRebalancing();

        uint256 totalRedemptionRequests = totalRedemptionRequests * assetToken.oracle().assetPrice();
        totalReserveRequired = assetToken.totalSupply() + totalDepositRequests - totalRedemptionRequests;
        rebalanceAmount = totalReserveRequired - reserveBalance;

        if (amount > rebalanceAmount) revert InvalidAmount();
        
        bool deficit = totalReserveRequired > reserveBalance;
        if (deficit) {
            reserveToken.transferFrom(msg.sender, address(this), amount);
            reserveBalance += amount;
        } else {
            reserveToken.transfer(msg.sender, amount);
            reserveBalance -= amount;
        }

        hasRebalanced[msg.sender] = true;
        rebalancedLPs++;

        emit Rebalanced(msg.sender, amount, deficit, cycleIndex);

        if (rebalancedLPs == lpRegistry.getLPCount(address(this))) {
            _startNewCycle();
        }
    }

    // Governance Actions
    function updateCycleTime(uint256 newCycleTime) external onlyOwner {
        cycleTime = newCycleTime;
        emit CycleTimeUpdated(newCycleTime);
    }

    function updateRebalanceTime(uint256 newRebalanceTime) external onlyOwner {
        rebalanceTime = newRebalanceTime;
        emit RebalanceTimeUpdated(newRebalanceTime);
    }

    function pausePool() external onlyOwner {
        _pause();
    }

    function unpausePool() external onlyOwner {
        _unpause();
    }

    // Internal functions
    function _validateRebalancing() internal view {
        require(lpRegistry.getLPLiquidity(address(this), msg.sender) > 0, "Insufficient LP liquidity");
    }

    function _startNewCycle() internal {
        cycleIndex++;
        cycleState = CycleState.ACTIVE;
        nextRebalanceStartDate = block.timestamp + cycleTime;
        nextRebalanceEndDate = nextRebalanceStartDate + rebalanceTime;
        rebalancedLPs = 0;
        
        emit CycleStarted(cycleIndex, block.timestamp);
    }

    // View functions
    function getGeneralInfo() external view returns (
        uint256 _reserveBalance,
        uint256 _xTokenSupply,
        CycleState _cycleState,
        uint256 _cycleIndex,
        uint256 _nextRebalanceStartDate,
        uint256 _nextRebalanceEndDate,
        uint256 _assetPrice
    ) {
        return (
            reserveBalance,
            assetToken.totalSupply(),
            cycleState,
            cycleIndex,
            nextRebalanceStartDate,
            nextRebalanceEndDate,
            assetToken.oracle().assetPrice()
        );
    }

    function getLPInfo() external view returns (
        uint256 _totalDepositRequests,
        uint256 _totalRedemptionRequests,
        uint256 _totalReserveRequired,
        uint256 _rebalanceAmount
    ) {
        _totalDepositRequests = totalDepositRequests;
        _totalRedemptionRequests = totalRedemptionRequests;
        _totalReserveRequired = totalReserveRequired;
        _rebalanceAmount = rebalanceAmount;
    }

}
