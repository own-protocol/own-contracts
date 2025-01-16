// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/Pausable.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IAssetPool} from "../interfaces/IAssetPool.sol";
import {IXToken} from "../interfaces/IXToken.sol";
import {ILPRegistry} from "../interfaces/ILPRegistry.sol";
import {IAssetOracle} from "../interfaces/IAssetOracle.sol";
import {xToken} from "./xToken.sol";

contract AssetPool is IAssetPool, Ownable, Pausable {
    IERC20 public immutable reserveToken;    // Reserve token (e.g., USDC)
    IXToken public immutable assetToken;     // xToken contract
    ILPRegistry public immutable lpRegistry;  // LP Registry contract
    IAssetOracle public immutable assetOracle;     // Asset Oracle contract

    // Pool state
    uint256 public cycleIndex;
    CycleState public cycleState;
    uint256 public nextRebalanceStartDate;
    uint256 public nextRebalanceEndDate;

    // Cycle timing
    uint256 public cycleTime;
    uint256 public rebalanceTime;

     // Asset states
    uint256 public totalReserveBalance;  // total reserve token balance         

    // Rebalancing instructions
    uint256 public newReserveSupply; // New reserve balance after rebalance excluding rebalance amount
    uint256 public newAssetSupply;  // New asset balance after rebalance excluding rebalance amount
    int256 public netReserveDelta;  // Net reserve change after rebalance excluding rebalance amount
    int256 public rebalanceAmount; // Net reserve redemption PnL

    // Rebalancing state
    uint256 public rebalancedLPs;
    mapping(address => bool) public hasRebalanced;

    // User request states
    mapping(address => uint256) public reserveBalance; // User reserve balance
    mapping(uint256 => uint256) public cycleTotalDepositRequests; // Pending deposits per user
    mapping(uint256 => uint256) public cycleTotalRedemptionRequests;  // Pending burns per user
    mapping(uint256 => mapping(address => uint256)) public cycleDepositRequests;     // Pending deposits per user
    mapping(uint256 => mapping(address => uint256)) public cycleRedemptionRequests;  // Pending burns per user
    mapping(address => uint256) public lastActionCycle;     // Last cycle user interacted with

    mapping(uint256 => uint256) public cycleRebalancePrice;  // price at which the rebalance was executed in a cycle
    mapping(uint256 => uint256) private cycleWeightedSum;  // Weighted sum of rebalance prices

    // Constants
    uint256 private constant PRECISION = 1e18; // Precision for calculations

    constructor(
        address _reserveToken,
        string memory _xTokenName,
        string memory _xTokenSymbol,
        address _assetOracle,
        address _lpRegistry,
        uint256 _cyclePeriod,
        uint256 _rebalancingPeriod,
        address _owner
    ) Ownable(_owner) {
        if (_reserveToken == address(0) || _assetOracle == address(0) || _lpRegistry == address(0)) 
            revert ZeroAddress();

        reserveToken = IERC20(_reserveToken);
        assetToken = new xToken(_xTokenName, _xTokenSymbol);
        lpRegistry = ILPRegistry(_lpRegistry);
        assetOracle = IAssetOracle(_assetOracle);
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
        uint256 userCycle = lastActionCycle[msg.sender];
        if (amount == 0) revert InvalidAmount();
        if (userCycle > 0 && userCycle != cycleIndex) revert MintOrBurnPending();
        reserveToken.transferFrom(msg.sender, address(this), amount);
        cycleDepositRequests[cycleIndex][msg.sender] += amount;
        cycleTotalDepositRequests[cycleIndex] += amount;
        lastActionCycle[msg.sender] = cycleIndex;
        
        emit DepositRequested(msg.sender, amount, cycleIndex);
    }

    function cancelDeposit() external notRebalancing {
        uint256 amount = cycleDepositRequests[cycleIndex][msg.sender];
        if (amount == 0) revert NothingToCancel();
        
        cycleDepositRequests[cycleIndex][msg.sender] = 0;
        cycleTotalDepositRequests[cycleIndex] -= amount;
        reserveToken.transfer(msg.sender, amount);
        lastActionCycle[msg.sender] = 0;
        
        emit DepositCancelled(msg.sender, amount, cycleIndex);
    }

    function mintAsset(address user) external whenNotPaused notRebalancing {
        uint256 userCycle = lastActionCycle[user];
        if (userCycle >= cycleIndex) revert NothingToClaim();
        uint256 reserveAmount = cycleDepositRequests[userCycle][msg.sender];
        if (reserveAmount == 0) revert NothingToClaim();

        cycleDepositRequests[userCycle][msg.sender] = 0;
        cycleTotalDepositRequests[userCycle] -= reserveAmount;
        uint256 rebalancePrice = cycleRebalancePrice[userCycle];
        lastActionCycle[user] = 0;

        uint256 assetAmount = Math.mulDiv(reserveAmount, PRECISION, rebalancePrice);

        assetToken.mint(user, assetAmount, reserveAmount);
        
        emit AssetClaimed(msg.sender, assetAmount, userCycle);
    }

    function burnAsset(uint256 assetAmount) external whenNotPaused notRebalancing {
        uint256 userBalance = assetToken.balanceOf(msg.sender);
        uint256 userCycle = lastActionCycle[msg.sender];
        if (assetAmount == 0) revert InvalidAmount();
        if (userBalance < assetAmount) revert InsufficientBalance();
        if (userCycle > 0 && userCycle != cycleIndex) revert MintOrBurnPending();

        assetToken.transferFrom(msg.sender, address(this), assetAmount);
        cycleRedemptionRequests[cycleIndex][msg.sender] = assetAmount;
        cycleTotalRedemptionRequests[cycleIndex] += assetAmount;
        lastActionCycle[msg.sender] = cycleIndex;
        
        emit BurnRequested(msg.sender, assetAmount, cycleIndex);
    }

    function cancelBurn() external notRebalancing {
        uint256 assetAmount = cycleRedemptionRequests[cycleIndex][msg.sender];
        if (assetAmount == 0) revert NothingToCancel();

        cycleRedemptionRequests[cycleIndex][msg.sender] = 0;
        cycleTotalRedemptionRequests[cycleIndex] -= assetAmount;
        lastActionCycle[msg.sender] = 0;
        
        assetToken.transfer(msg.sender, assetAmount);
        
        emit BurnCancelled(msg.sender, assetAmount, cycleIndex);
    }

    function withdrawReserve(address user) external whenNotPaused notRebalancing {
        uint256 userCycle = lastActionCycle[user];
        if (userCycle >= cycleIndex) revert NothingToClaim();
        uint256 assetAmount = cycleRedemptionRequests[userCycle][msg.sender];
        if (assetAmount == 0) revert NothingToClaim();
        
        uint256 reserveAmountToTransfer = Math.mulDiv(assetAmount, cycleRebalancePrice[userCycle], PRECISION);
        cycleRedemptionRequests[userCycle][user] = 0;
        cycleTotalRedemptionRequests[userCycle] -= assetAmount;
        lastActionCycle[user] = 0;
        reserveToken.transfer(user, reserveAmountToTransfer);
        
        emit ReserveWithdrawn(user, reserveAmountToTransfer, cycleIndex);
    }

    // --------------------------------------------------------------------------------
    //                               REBALANCING LOGIC
    // --------------------------------------------------------------------------------

    /**
     * @notice Initiates the rebalance, calculates how much asset & stablecoin
     *         needs to move, and broadcasts instructions for LPs to act on.
     */
    function initiateRebalance() external {
        if (cycleState != CycleState.ACTIVE) revert InvalidCycleState();
        if (block.timestamp >= nextRebalanceStartDate) revert CycleInProgress();
        cycleState = CycleState.REBALANCING;
        uint256 assetPrice = assetOracle.assetPrice();
        uint256 depositRequests = cycleTotalDepositRequests[cycleIndex];
        uint256 redemptionRequestsInAsset = cycleTotalRedemptionRequests[cycleIndex];
        uint256 redemptionRequestsInReserve = Math.mulDiv(redemptionRequestsInAsset, assetPrice, PRECISION);
        uint256 assetReserveSupplyInPool = assetToken.reserveBalanceOf(address(this));

        netReserveDelta = int256(depositRequests) - int256(assetReserveSupplyInPool);
        newReserveSupply =  assetToken.totalReserveSupply() + depositRequests - assetReserveSupplyInPool; 
        rebalanceAmount = int256(redemptionRequestsInReserve) - int256(assetReserveSupplyInPool);

        emit RebalanceInitiated(
            cycleIndex,
            assetPrice,
            netReserveDelta,
            rebalanceAmount
        );

    }

    /**
     * @notice Once LPs have traded off-chain, they deposit or withdraw stablecoins accordingly.
     * @param lp Address of the LP performing the final on-chain step
     * @param amount Amount of stablecoin they are sending to (or withdrawing from) the pool
     * @param rebalancePrice Price at which the rebalance was executed
     * @param isDeposit True if depositing stable, false if withdrawing
     *
     * ToDo: lpLiquidty should be based on how much being asset being rebalanced during the cycle
     * ToDo: Need to handle the case when LP doesn't rebalance within the rebalance window
     */

    function rebalancePool(address lp, uint256 rebalancePrice, uint256 amount, bool isDeposit) external onlyLP {
        if (cycleState != CycleState.REBALANCING) revert InvalidCycleState();
        if (hasRebalanced[lp]) revert AlreadyRebalanced();
        if (block.timestamp > nextRebalanceEndDate) revert RebalancingExpired();
        uint256 lpLiquidity = lpRegistry.getLPLiquidity(address(this), lp);

        _validateRebalancing(lp, amount, isDeposit);

        cycleWeightedSum[cycleIndex] += rebalancePrice * lpLiquidity;

        // Approve stablecoins if deposit
        if (isDeposit) {
            // If depositing stable, transfer from LP
            reserveToken.transferFrom(lp, address(this), amount);
        } else {
            // If withdrawing stable, ensure the pool has enough
            reserveToken.transfer(lp, amount);
        }

        hasRebalanced[lp] = true;
        rebalancedLPs++;

        emit Rebalanced(lp, rebalancePrice, amount, isDeposit, cycleIndex);

        // If all LPs have rebalanced, start next cycle
        if (rebalancedLPs == lpRegistry.getLPCount(address(this))) {
            uint256 totalLiquidity = lpRegistry.getTotalLPLiquidity(address(this));
            uint256 assetBalance = assetToken.balanceOf(address(this));
            uint256 reserveBalanceInAssetToken = assetToken.reserveBalanceOf(address(this));
            assetToken.burn(address(this), assetBalance, reserveBalanceInAssetToken);
            cycleRebalancePrice[cycleIndex] = cycleWeightedSum[cycleIndex] / totalLiquidity;
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
    function _validateRebalancing(address lp, uint256 amount, bool isDeposit) internal view {
        uint256 lpLiquidity = lpRegistry.getLPLiquidity(address(this), lp);
        if (lpLiquidity == 0) revert InsufficientLPLiquidity();

        // Check if the rebalance direction aligns with the rebalanceAmount
        if (rebalanceAmount > 0 && !isDeposit) revert RebalanceMismatch();
        if (rebalanceAmount < 0 && isDeposit) revert RebalanceMismatch();

        // Calculate the expected amount based on LP's liquidity share
        uint256 expectedAmount = uint256(rebalanceAmount > 0 ? rebalanceAmount : -rebalanceAmount) * lpLiquidity / lpRegistry.getTotalLPLiquidity(address(this));
        if (amount != expectedAmount) revert RebalanceMismatch();

        
    }

    // View functions
    function getGeneralInfo() external view returns (
        uint256 _xTokenSupply,
        CycleState _cycleState,
        uint256 _cycleIndex,
        uint256 _nextRebalanceStartDate,
        uint256 _nextRebalanceEndDate,
        uint256 _assetPrice
    ) {
        return (
            assetToken.totalSupply(),
            cycleState,
            cycleIndex,
            nextRebalanceStartDate,
            nextRebalanceEndDate,
            assetOracle.assetPrice()
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
        _totalDepositRequests = cycleTotalDepositRequests[cycleIndex];
        _totalRedemptionRequests = cycleTotalRedemptionRequests[cycleIndex];
        _netReserveDelta = netReserveDelta;
        _rebalanceAmount = rebalanceAmount;
    }

}
