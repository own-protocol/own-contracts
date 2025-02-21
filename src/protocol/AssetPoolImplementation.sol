// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/contracts/utils/Pausable.sol";
import "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IAssetPool} from "../interfaces/IAssetPool.sol";
import {IXToken} from "../interfaces/IXToken.sol";
import {ILPRegistry} from "../interfaces/ILPRegistry.sol";
import {IAssetOracle} from "../interfaces/IAssetOracle.sol";
import {xToken} from "./xToken.sol";

/**
 * @title AssetPoolImplementation
 * @notice Manages the lifecycle of assets and reserves in a decentralized pool.
 *         Facilitates deposits, minting, redemptions, and rebalancing of assets.
 *         Includes governance controls for updating operational parameters.
 */
contract AssetPoolImplementation is IAssetPool, Ownable, Pausable, Initializable {
    // --------------------------------------------------------------------------------
    //                               STATE VARIABLES
    // --------------------------------------------------------------------------------

    /**
     * @notice Address of the reserve token (e.g., USDC).
     */
    IERC20Metadata public reserveToken;

    /**
     * @notice Address of the xToken contract used for asset representation.
     */
    IXToken public assetToken;

    /**
     * @notice Address of the LP Registry contract for managing LPs.
     */
    ILPRegistry public lpRegistry;

    /**
     * @notice Address of the Asset Oracle contract for fetching asset prices.
     */
    IAssetOracle public assetOracle;

    /**
     * @notice Index of the current operational cycle.
     */
    uint256 public cycleIndex;

    /**
     * @notice Current state of the pool (ACTIVE or REBALANCING).
     */
    CycleState public cycleState;

    /**
     * @notice Duration of each operational cycle in seconds.
     */
    uint256 public cycleLength;

    /**
     * @notice Duration of the rebalance period in seconds.
     */
    uint256 public rebalanceLength;

    /**
     * @notice Timestamp of the last cycle action.
     */
    uint256 public lastCycleActionDateTime;

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
     * @notice Total deposit requests in the current cycle.
     */
    uint256 public cycleTotalDepositRequests;

    /**
     * @notice Total redemption requests in the current cycle.
     */
    uint256 public cycleTotalRedemptionRequests;

    /**
     * @notice Mapping of users to their request
     */
    mapping(address => UserRequest) public pendingRequests;

    /**
     * @notice Tracks the last cycle an lp rebalanced.
     */
    mapping(address => uint256) public lastRebalancedCycle;

    /**
     * @notice Individual user reserve balances.
     */
    mapping(address => uint256) public reserveBalance;

    /**
     * @notice Rebalance price for each cycle.
     */
    mapping(uint256 => uint256) public cycleRebalancePrice;

    /**
     * @notice Weighted sum of rebalance prices for the current cycle.
     */
    uint256 private cycleWeightedSum;

    /**
     * @notice Decimal factor used for calculations.
     */
    uint256 public reserveToAssetDecimalFactor;

    /**
     * @notice Precision used for calculations.
     */
    uint256 private constant PRECISION = 1e18;

    constructor() Ownable(msg.sender) {
        // Disable the implementation contract
        _disableInitializers();
    }

    // --------------------------------------------------------------------------------
    //                                    INITIALIZER
    // --------------------------------------------------------------------------------

    /**
     * @notice Initializes the AssetPool contract with required dependencies and parameters.
     * @param _reserveToken Address of the reserve token contract (e.g., USDC).
     * @param _xTokenName Name of the xToken to be created.
     * @param _xTokenSymbol Symbol of the xToken to be created.
     * @param _assetOracle Address of the asset price oracle contract.
     * @param _lpRegistry Address of the LP registry contract.
     * @param _cycleLength Duration of each operational cycle.
     * @param _rebalanceLength Duration of the rebalance period.
     */
    function initialize (
        address _reserveToken,
        string memory _xTokenName,
        string memory _xTokenSymbol,
        address _assetOracle,
        address _lpRegistry,
        uint256 _cycleLength,
        uint256 _rebalanceLength,
        address _owner
    ) external initializer {
        if (_reserveToken == address(0) || _assetOracle == address(0) || _lpRegistry == address(0)) 
            revert ZeroAddress();

        _transferOwnership(_owner);

        reserveToken = IERC20Metadata(_reserveToken);
        assetToken = new xToken(_xTokenName, _xTokenSymbol);
        lpRegistry = ILPRegistry(_lpRegistry);
        assetOracle = IAssetOracle(_assetOracle);
        cycleState = CycleState.ACTIVE;
        cycleLength = _cycleLength;
        rebalanceLength = _rebalanceLength;
        lastCycleActionDateTime = block.timestamp;

        uint8 reserveDecimals = reserveToken.decimals();
        uint8 assetDecimals = assetToken.decimals();
        reserveToAssetDecimalFactor = 10 ** uint256(assetDecimals - reserveDecimals);
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
        if (cycleState != CycleState.ACTIVE) revert InvalidCycleState();
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
    function depositRequest(uint256 amount) external whenNotPaused notRebalancing {
        if (amount == 0) revert InvalidAmount();

        UserRequest storage request = pendingRequests[msg.sender];

        if (request.amount > 0) revert MintOrBurnPending();
        reserveToken.transferFrom(msg.sender, address(this), amount);

        request.amount = amount;
        request.isDeposit = true;
        request.requestCycle = cycleIndex;
        cycleTotalDepositRequests += amount;
        
        emit DepositRequested(msg.sender, amount, cycleIndex);
    }

    /**
     * @notice Creates a redemption request for the user. The user must have enough asset tokens that want to redeem for reserve tokens.
     *         The redemption request will be processed in the next cycle.
     * @param assetAmount Amount of asset tokens to burn.
     */
    function redemptionRequest(uint256 assetAmount) external whenNotPaused notRebalancing {
        if (assetAmount == 0) revert InvalidAmount();

        uint256 userBalance = assetToken.balanceOf(msg.sender);
        if (userBalance < assetAmount) revert InsufficientBalance();

        UserRequest storage request = pendingRequests[msg.sender];
        if (request.amount > 0) revert MintOrBurnPending();

        assetToken.transferFrom(msg.sender, address(this), assetAmount);
        
        request.amount = assetAmount;
        request.isDeposit = false;
        request.requestCycle = cycleIndex;
        cycleTotalRedemptionRequests += assetAmount;
        
        emit RedemptionRequested(msg.sender, assetAmount, cycleIndex);
    }

    /**
     * @notice Allows a user to cancel a pending request.
     */
    function cancelRequest() external notRebalancing {

        UserRequest storage request = pendingRequests[msg.sender];
        uint256 amount = request.amount;
        bool isDeposit = request.isDeposit;
        uint256 requestCycle = request.requestCycle;

        if (requestCycle != cycleIndex) revert NothingToCancel();
        if (amount == 0) revert NothingToCancel();

        delete pendingRequests[msg.sender];

        if (isDeposit) {
            cycleTotalDepositRequests -= amount;
            // Return reserve tokens
            reserveToken.transfer(msg.sender, amount);
            emit DepositCancelled(msg.sender, amount, cycleIndex);
        } else {
            cycleTotalRedemptionRequests -= amount;
            // Return asset tokens
            assetToken.transfer(msg.sender, amount);
            emit RedemptionCancelled(msg.sender, amount, cycleIndex);
        }
    }

    /**
     * @notice Claim asset or reserve based on user's previous pending requests once they are processed
     * @param user Address of the user for whom the asset or reserve is to be claimed
     */
    function claimRequest(address user) external whenNotPaused notRebalancing {

        UserRequest storage request = pendingRequests[user];
        uint256 amount = request.amount;
        bool isDeposit = request.isDeposit;
        uint256 requestCycle = request.requestCycle;

        if (requestCycle >= cycleIndex) revert NothingToClaim();
        if (amount == 0) revert NothingToClaim();

        delete pendingRequests[user];

        uint256 rebalancePrice = cycleRebalancePrice[requestCycle];

        if (isDeposit) {
            // Mint case - convert reserve to asset using exact price
            uint256 assetAmount = Math.mulDiv(amount, PRECISION * reserveToAssetDecimalFactor, rebalancePrice);
            assetToken.mint(user, assetAmount, amount);
            emit AssetClaimed(user, assetAmount, requestCycle);
        } else {
            // Withdraw case - convert asset to reserve using exact price
            uint256 reserveAmount = Math.mulDiv(amount, rebalancePrice, PRECISION * reserveToAssetDecimalFactor);
            reserveToken.transfer(user, reserveAmount);
            emit ReserveWithdrawn(user, reserveAmount, requestCycle);
        }
    }

    // --------------------------------------------------------------------------------
    //                               REBALANCING LOGIC
    // --------------------------------------------------------------------------------

    /**
     * @notice Initiates the off-chain rebalance process.
     */
    function initiateOffchainRebalance() external {
        if (cycleState != CycleState.ACTIVE) revert InvalidCycleState();
        if (block.timestamp < lastCycleActionDateTime + cycleLength) revert CycleInProgress();
        cycleState = CycleState.REBALANCING_OFFCHAIN;
        lastCycleActionDateTime = block.timestamp;
    }

    /**
     * @notice Initiates the onchain rebalance, calculates how much asset & stablecoin
     *         needs to move, and broadcasts instructions for LPs to act on.
     */
    function initiateOnchainRebalance() external {
        if (cycleState != CycleState.REBALANCING_OFFCHAIN) revert InvalidCycleState();
        uint256 expectedDateTime = lastCycleActionDateTime + rebalanceLength;
        if (block.timestamp < expectedDateTime) revert OffChainRebalanceInProgress();
        uint256 oracleLastUpdated = assetOracle.lastUpdated();
        if (oracleLastUpdated < expectedDateTime) revert OracleNotUpdated();

        uint256 assetPrice = assetOracle.assetPrice();
        uint256 depositRequests = cycleTotalDepositRequests;
        uint256 redemptionRequestsInAsset = cycleTotalRedemptionRequests;
        uint256 redemptionRequestsInReserve = Math.mulDiv(redemptionRequestsInAsset, assetPrice, PRECISION * reserveToAssetDecimalFactor);
        // The balance of the asset token in the pool represents the amount of redemption requests in asset.
        // Asset reserve represents the value the asset token was minted at.
        uint256 assetReserveSupplyInPool = assetToken.reserveBalanceOf(address(this));

        // Calculate the net change in reserves post-rebalance
        netReserveDelta = int256(depositRequests) - int256(assetReserveSupplyInPool);
        newReserveSupply =  assetToken.totalReserveSupply() + depositRequests - assetReserveSupplyInPool;
        // Calculate the total amount to rebalance
        rebalanceAmount = int256(redemptionRequestsInReserve) - int256(assetReserveSupplyInPool);

        lastCycleActionDateTime = block.timestamp;
        cycleState = CycleState.REBALANCING_ONCHAIN;

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
        if (cycleState != CycleState.REBALANCING_ONCHAIN) revert InvalidCycleState();
        if (cycleIndex > 0 && lastRebalancedCycle[lp] == cycleIndex) revert AlreadyRebalanced();
        if (block.timestamp > lastCycleActionDateTime + rebalanceLength) revert RebalancingExpired();
        uint256 lpLiquidity = lpRegistry.getLPLiquidity(address(this), lp);

        _validateRebalancing(lp, amount, isDeposit);

        cycleWeightedSum += rebalancePrice * lpLiquidity;

        if (isDeposit) {
            // If depositing stable, transfer from LP
            reserveToken.transferFrom(lp, address(this), amount);
        } else {
            // If withdrawing stable, ensure the pool has enough
            reserveToken.transfer(lp, amount);
        }

        lastRebalancedCycle[lp] = cycleIndex;
        rebalancedLPs++;

        emit Rebalanced(lp, rebalancePrice, amount, isDeposit, cycleIndex);

        // If all LPs have rebalanced, start next cycle
        if (rebalancedLPs == lpRegistry.getLPCount(address(this))) {
            uint256 assetBalance = assetToken.balanceOf(address(this));
            uint256 reserveBalanceInAssetToken = assetToken.reserveBalanceOf(address(this));
            assetToken.burn(address(this), assetBalance, reserveBalanceInAssetToken);
            uint256 totalLiquidity = lpRegistry.getTotalLPLiquidity(address(this));
            cycleRebalancePrice[cycleIndex] = cycleWeightedSum / totalLiquidity;
            
            _startNewCycle();
        }
    }

    /**
     * @notice Settle the pool if the rebalance window has expired and pool is not fully rebalanced.
     * ToDo: Slash the LPs who didn't rebalance within the rebalance window, rebalance the pool and start the next cycle
     */
    function settlePool() external onlyLP {
        if (cycleState != CycleState.REBALANCING_ONCHAIN) revert InvalidCycleState();
        if (block.timestamp < lastCycleActionDateTime + rebalanceLength) revert OnChainRebalancingInProgress();
        
        _startNewCycle();
    }

    /**
     * @notice If there is nothing to rebalance, start the next cycle.
     */
    function startNewCycle() external {
        if (cycleState == CycleState.ACTIVE) revert InvalidCycleState();
        if (cycleTotalDepositRequests > 0) revert InvalidCycleRequest();
        if (cycleTotalRedemptionRequests > 0) revert InvalidCycleRequest();
        
        _startNewCycle();
    }

    // --------------------------------------------------------------------------------
    //                            GOVERNANCE FUNCTIONS
    // --------------------------------------------------------------------------------

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

    /**
     * Todo: Add a function to clean old rebalance prices to free up storage.
     */

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
        cycleIndex++;
        cycleState = CycleState.ACTIVE;
        rebalancedLPs = 0;
        cycleTotalDepositRequests = 0;
        cycleTotalRedemptionRequests = 0;
        cycleWeightedSum = 0;
        lastCycleActionDateTime = block.timestamp;

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
     * @return _assetPrice Current price of the asset.
     * @return _lastCycleActionDateTime Timestamp of the last cycle action.
     */
    function getGeneralInfo() external view returns (
        uint256 _xTokenSupply,
        CycleState _cycleState,
        uint256 _cycleIndex,
        uint256 _assetPrice,
        uint256 _lastCycleActionDateTime
    ) {
        return (
            assetToken.totalSupply(),
            cycleState,
            cycleIndex,
            assetOracle.assetPrice(),
            lastCycleActionDateTime
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
        _totalDepositRequests = cycleTotalDepositRequests;
        _totalRedemptionRequests = cycleTotalRedemptionRequests;
        _netReserveDelta = netReserveDelta;
        _rebalanceAmount = rebalanceAmount;
    }

}
