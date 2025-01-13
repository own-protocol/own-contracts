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
    uint256 public reserveBalance;  // total reserve token balance         
    uint256 public totalDepositRequests; // Total deposit requests
    uint256 public totalRedemptionRequests; // Total redemption requests
    uint256 public totalRedemptionScaledRequests; // Total redemption requests in scaled amount

    // Rebalancing instructions
    uint256 public newReserveSupply; // New reserve balance after rebalance excluding rebalance amount
    uint256 public newAssetSupply;  // New asset balance after rebalance excluding rebalance amount
    int256 public netReserveDelta;  // Net reserve change after rebalance excluding rebalance amount
    int256 public rebalanceAmount; // Net reserve redemption PnL

    // Rebalancing state
    uint256 public rebalancedLPs;
    mapping(address => bool) public hasRebalanced;

    // User request states
    mapping(address => uint256) public depositRequests;     // Pending deposits per user
    mapping(address => uint256) public redemptionRequests;  // Pending burns per user
    mapping(address => uint256) public redemptionScaledRequests;  // Pending burns per user in scaled amount
    mapping(address => uint256) public lastActionCycle;     // Last cycle user interacted with

    mapping(uint256 => uint256) public cycleRebalancePrice;  // price at which the rebalance was executed in a cycle

    // Constants
    uint256 private constant PRECISION = 1e18; // Precision for calculations

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
        totalDepositRequests -= amount;
        uint256 rebalancePrice = cycleRebalancePrice[lastActionCycle[user]];

        assetToken.mint(user, amount, rebalancePrice);
        
        emit AssetClaimed(msg.sender, amount, cycleIndex);
    }

    function burnAsset(uint256 xTokenAmount) external whenNotPaused notRebalancing {
        if (xTokenAmount == 0) revert InvalidAmount();
        if (assetToken.balanceOf(msg.sender) < xTokenAmount) revert InsufficientBalance();

        // Get scaled amount from xToken contract
        uint256 scaledAmount = assetToken.scaledBalanceOf(msg.sender);
        uint256 nominalBalance = assetToken.balanceOf(msg.sender);
        uint256 scaledBurnAmount = scaledAmount * xTokenAmount / nominalBalance;
        
        assetToken.burn(msg.sender, xTokenAmount);
        redemptionScaledRequests[msg.sender] = scaledBurnAmount;
        totalRedemptionScaledRequests += scaledBurnAmount;
        redemptionRequests[msg.sender] = xTokenAmount;
        totalRedemptionRequests += xTokenAmount;
        lastActionCycle[msg.sender] = cycleIndex;
        
        emit BurnRequested(msg.sender, xTokenAmount, cycleIndex);
    }

    function cancelBurn() external notRebalancing {
        uint256 amount = redemptionRequests[msg.sender];
        if (amount == 0) revert NothingToCancel();

        uint256 scaledAmount = redemptionScaledRequests[msg.sender];
        redemptionRequests[msg.sender] = 0;
        redemptionScaledRequests[msg.sender] = 0;
        totalRedemptionRequests -= redemptionRequests[msg.sender];
        totalRedemptionScaledRequests -= scaledAmount;
        uint256 price = amount / scaledAmount;
        assetToken.mint(msg.sender, amount, price);
        
        emit BurnCancelled(msg.sender, amount, cycleIndex);
    }

    function withdrawReserve(address user) external whenNotPaused notRebalancing {
        if (lastActionCycle[user] >= cycleIndex) revert NothingToClaim();
        uint256 amount = redemptionRequests[user];
        if (amount == 0) revert NothingToClaim();
        
        uint256 scaledAmount = redemptionScaledRequests[user];
        redemptionRequests[user] = 0;
        redemptionScaledRequests[user] = 0;
        uint256 reserveAmount = scaledAmount * cycleRebalancePrice[lastActionCycle[user]];
        reserveToken.transfer(user, reserveAmount);
        
        emit ReserveWithdrawn(user, reserveAmount, cycleIndex);
    }

    // --------------------------------------------------------------------------------
    //                               REBALANCING LOGIC
    // --------------------------------------------------------------------------------

    /**
     * @notice Initiates the rebalance, calculates how much asset & stablecoin
     *         needs to move, and broadcasts instructions for LPs to act on.
     */
    function initiateRebalance() external {
        require(cycleState == CycleState.ACTIVE, "Already rebalancing");
        require(block.timestamp < nextRebalanceStartDate, "Cycle inprogress");
        cycleState = CycleState.REBALANCING;

        uint256 spotPrice = assetToken.oracle().assetPrice();
        netReserveDelta = int256(totalDepositRequests) - int256(totalRedemptionRequests);
        newReserveSupply =  xToken.totalSupply() + totalDepositRequests; // Redemptions are already burned so they are not considered
        newAssetSupply = newReserveSupply * spotPrice / PRECISION;
        rebalanceAmount = totalRedemptionScaledRequests * spotPrice / PRECISION - totalRedemptionRequests;

        emit RebalanceInitiated(
            cycleIndex,
            spotPrice,
            netReserveDelta,
            rebalanceAmount
        );

    }

    /**
     * @notice Once LPs have traded off-chain, they deposit or withdraw stablecoins accordingly.
     * @param lp Address of the LP performing the final on-chain step
     * @param amount Amount of stablecoin they are sending to (or withdrawing from) the pool
     * @param isDeposit True if depositing stable, false if withdrawing
     */
    function rebalancePool(address lp, uint256 amount, bool isDeposit) external onlyLP {
        require(cycleState == CycleState.REBALANCING, "Not in rebalancing");
        if (hasRebalanced[lp]) revert AlreadyRebalanced();
        if (block.timestamp > nextRebalanceEndDate) revert RebalancingExpired();

        // Approve stablecoins if deposit
        if (isDeposit) {
            // If depositing stable, transfer from LP
            reserveToken.transferFrom(lp, address(this), amount);
            reserveBalance += amount;
        } else {
            // If withdrawing stable, ensure the pool has enough
            if (amount > reserveBalance) revert InvalidAmount();
            reserveBalance -= amount;
            reserveToken.transfer(lp, amount);
        }

        hasRebalanced[lp] = true;
        rebalancedLPs++;

        emit Rebalanced(lp, amount, isDeposit, cycleIndex);

        // If all LPs have rebalanced, start next cycle
        if (rebalancedLPs == lpRegistry.getLPCount(address(this))) {
            _startNewCycle();
        }
    }

    function _startNewCycle() internal {
        cycleIndex++;
        cycleState = CycleState.ACTIVE;
        rebalancedLPs = 0;
        nextRebalanceStartDate = block.timestamp + cycleTime;
        nextRebalanceEndDate = nextRebalanceStartDate + rebalanceTime;

        emit CycleStarted(cycleIndex, block.timestamp);
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

    function getLPInfo()
        external
        view
        returns (
            uint256 _totalDepositRequests,
            uint256 _totalRedemptionRequests,
            int256 _netReserveDelta,
            int256 _rebalanceAmount
        )
    {
        _totalDepositRequests = totalDepositRequests;
        _totalRedemptionRequests = totalRedemptionRequests;
        _netReserveDelta = netReserveDelta;
        _rebalanceAmount = rebalanceAmount;
    }

}
