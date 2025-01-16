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

/**
 * @title AssetPool
 * @notice Manages the lifecycle of assets and reserves in a decentralized pool.
 *         Facilitates deposits, minting, redemptions, and rebalancing of assets.
 *         Includes governance controls for updating operational parameters.
 */
contract AssetPool is IAssetPool, Ownable, Pausable {
    // --------------------------------------------------------------------------------
    //                               STATE VARIABLES
    // --------------------------------------------------------------------------------

    /**
     * @notice Address of the reserve token (e.g., USDC).
     */
    IERC20 public immutable reserveToken;

    /**
     * @notice Address of the xToken contract used for asset representation.
     */
    IXToken public immutable assetToken;

    /**
     * @notice Address of the LP Registry contract for managing LPs.
     */
    ILPRegistry public immutable lpRegistry;

    /**
     * @notice Address of the Asset Oracle contract for fetching asset prices.
     */
    IAssetOracle public immutable assetOracle;

    /**
     * @notice Index of the current operational cycle.
     */
    uint256 public cycleIndex;

    /**
     * @notice Current state of the pool (ACTIVE or REBALANCING).
     */
    CycleState public cycleState;

    /**
     * @notice Timestamp when the next rebalance is scheduled to start.
     */
    uint256 public nextRebalanceStartDate;

    /**
     * @notice Timestamp when the next rebalance is scheduled to end.
     */
    uint256 public nextRebalanceEndDate;

    /**
     * @notice Duration of each operational cycle in seconds.
     */
    uint256 public cycleTime;

    /**
     * @notice Duration of the rebalance period in seconds.
     */
    uint256 public rebalanceTime;

    /**
     * @notice Total reserve token balance in the pool.
     */
    uint256 public totalReserveBalance;

    /**
     * @notice New reserve supply post-rebalance.
     */
    uint256 public newReserveSupply;

    /**
     * @notice New asset supply post-rebalance.
     */
    uint256 public newAssetSupply;

    /**
     * @notice Net change in reserves post-rebalance.
     */
    int256 public netReserveDelta;

    /**
     * @notice Total amount to rebalance (PnL from reserves).
     */
    int256 public rebalanceAmount;

    /**
     * @notice Count of LPs who have completed rebalancing in the current cycle.
     */
    uint256 public rebalancedLPs;

    /**
     * @notice Tracks whether an LP has completed rebalancing in the current cycle.
     */
    mapping(address => bool) public hasRebalanced;

    /**
     * @notice Individual user reserve balances.
     */
    mapping(address => uint256) public reserveBalance;

    /**
     * @notice Total pending deposit requests for each cycle.
     */
    mapping(uint256 => uint256) public cycleTotalDepositRequests;

    /**
     * @notice Total pending redemption requests for each cycle.
     */
    mapping(uint256 => uint256) public cycleTotalRedemptionRequests;

    /**
     * @notice Pending deposit requests by user for each cycle.
     */
    mapping(uint256 => mapping(address => uint256)) public cycleDepositRequests;

    /**
     * @notice Pending redemption requests by user for each cycle.
     */
    mapping(uint256 => mapping(address => uint256)) public cycleRedemptionRequests;

    /**
     * @notice Tracks the last cycle a user interacted with.
     */
    mapping(address => uint256) public lastActionCycle;

    /**
     * @notice Rebalance price for each cycle.
     */
    mapping(uint256 => uint256) public cycleRebalancePrice;

    /**
     * @notice Weighted sum of rebalance prices for each cycle.
     */
    mapping(uint256 => uint256) private cycleWeightedSum;

    /**
     * @notice Precision used for calculations.
     */
    uint256 private constant PRECISION = 1e18;

    // --------------------------------------------------------------------------------
    //                                    CONSTRUCTOR
    // --------------------------------------------------------------------------------

    /**
     * @notice Initializes the AssetPool contract with required dependencies and parameters.
     * @param _reserveToken Address of the reserve token contract (e.g., USDC).
     * @param _xTokenName Name of the xToken to be created.
     * @param _xTokenSymbol Symbol of the xToken to be created.
     * @param _assetOracle Address of the asset price oracle contract.
     * @param _lpRegistry Address of the LP registry contract.
     * @param _cyclePeriod Duration of each operational cycle.
     * @param _rebalancingPeriod Duration of the rebalance period.
     * @param _owner Address of the contract owner.
     */
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

    // --------------------------------------------------------------------------------
    //                                    MODIFIERS
    // --------------------------------------------------------------------------------

    /**
     * @dev Ensures the caller is a registered LP.
     */
    modifier onlyLP() {
        if (!lpRegistry.isLP(address(this), msg.sender)) revert NotLP();
        _;
    }

    /**
     * @dev Ensures the pool is not in a rebalancing state.
     */
    modifier notRebalancing() {
        if (cycleState == CycleState.REBALANCING) revert InvalidCycleState();
        _;
    }

    // --------------------------------------------------------------------------------
    //                                  USER ACTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Allows a user to deposit reserve tokens into the pool.
     *         The deposited amount will be processed in the next cycle.
     * @param amount Amount of reserve tokens to deposit.
     */
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

    /**
     * @notice Allows a user to cancel a pending deposit request for the current cycle.
     */
    function cancelDeposit() external notRebalancing {
        uint256 amount = cycleDepositRequests[cycleIndex][msg.sender];
        if (amount == 0) revert NothingToCancel();
        
        cycleDepositRequests[cycleIndex][msg.sender] = 0;
        cycleTotalDepositRequests[cycleIndex] -= amount;
        reserveToken.transfer(msg.sender, amount);
        lastActionCycle[msg.sender] = 0;
        
        emit DepositCancelled(msg.sender, amount, cycleIndex);
    }

    /**
     * @notice Mints asset tokens for a user based on their processed deposit requests.
     * @param user Address of the user claiming the asset tokens.
     */
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

    /**
     * @notice Burn asset tokens for a user and creates a redemption request for the current cycle.
     *         The redemption request will be processed in the next cycle.
     * @param assetAmount Amount of asset tokens to burn.
     */
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

    /**
     * @notice Allows a user to cancel a pending burn request for the current cycle.
     */
    function cancelBurn() external notRebalancing {
        uint256 assetAmount = cycleRedemptionRequests[cycleIndex][msg.sender];
        if (assetAmount == 0) revert NothingToCancel();

        cycleRedemptionRequests[cycleIndex][msg.sender] = 0;
        cycleTotalRedemptionRequests[cycleIndex] -= assetAmount;
        lastActionCycle[msg.sender] = 0;
        
        assetToken.transfer(msg.sender, assetAmount);
        
        emit BurnCancelled(msg.sender, assetAmount, cycleIndex);
    }

    /**
     * @notice Allows a user to withdraw reserve tokens after their redemption request is processed.
     * @param user Address of the user withdrawing the reserve tokens.
     */
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
     * @param rebalancePrice Price at which the rebalance was executed
     * @param amount Amount of stablecoin they are sending to (or withdrawing from) the pool
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
            _startNewCycle();
        }
    }

    // --------------------------------------------------------------------------------
    //                            GOVERNANCE FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Updates the duration of each cycle.
     * @param newCycleTime New cycle duration in seconds.
     */
    function updateCycleTime(uint256 newCycleTime) external onlyOwner {
        cycleTime = newCycleTime;
        emit CycleTimeUpdated(newCycleTime);
    }

    /**
     * @notice Updates the duration of the rebalance period.
     * @param newRebalanceTime New rebalance duration in seconds.
     */
    function updateRebalanceTime(uint256 newRebalanceTime) external onlyOwner {
        rebalanceTime = newRebalanceTime;
        emit RebalanceTimeUpdated(newRebalanceTime);
    }

    /**
     * @notice Pauses the pool, disabling all user actions.
     */
    function pausePool() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the pool, re-enabling all user actions.
     */
    function unpausePool() external onlyOwner {
        _unpause();
    }

    // --------------------------------------------------------------------------------
    //                            INTERNAL FUNCTIONS
    // --------------------------------------------------------------------------------


    /**
     * @notice Validates the rebalancing action performed by an LP.
     * @param lp Address of the LP performing the rebalance.
     * @param amount Amount of reserve being deposited or withdrawn.
     * @param isDeposit True if depositing reserve, false if withdrawing.
     */
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

    /**
     * @notice Starts a new cycle after all LPs have rebalanced.
     */
    function _startNewCycle() internal {
        uint256 totalLiquidity = lpRegistry.getTotalLPLiquidity(address(this));
        uint256 assetBalance = assetToken.balanceOf(address(this));
        uint256 reserveBalanceInAssetToken = assetToken.reserveBalanceOf(address(this));
        assetToken.burn(address(this), assetBalance, reserveBalanceInAssetToken);
        cycleRebalancePrice[cycleIndex] = cycleWeightedSum[cycleIndex] / totalLiquidity;
        cycleIndex++;
        cycleState = CycleState.ACTIVE;
        rebalancedLPs = 0;
        nextRebalanceStartDate = block.timestamp + cycleTime;
        nextRebalanceEndDate = nextRebalanceStartDate + rebalanceTime;

        emit CycleStarted(cycleIndex, block.timestamp);
    }

    // --------------------------------------------------------------------------------
    //                            VIEW FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Returns the general information about the pool.
     * @return _xTokenSupply Total supply of the xToken.
     * @return _cycleState Current state of the pool.
     * @return _cycleIndex Current cycle index.
     * @return _nextRebalanceStartDate Timestamp of the next rebalance start.
     * @return _nextRebalanceEndDate Timestamp of the next rebalance end.
     * @return _assetPrice Current price of the asset.
     */
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

    /**
     * @notice Returns the LP-specific information about the pool.
     * @return _totalDepositRequests Total pending deposit requests.
     * @return _totalRedemptionRequests Total pending redemption requests.
     * @return _netReserveDelta Net change in reserves post-rebalance.
     * @return _rebalanceAmount Total amount to rebalance (PnL from reserves).
     */
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
