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
import {ILPLiquidityManager} from "../interfaces/ILPLiquidityManager.sol";
import {IAssetOracle} from "../interfaces/IAssetOracle.sol";
import {xToken} from "./xToken.sol";

/**
 * @title AssetPool
 * @notice Manages the lifecycle of assets and reserves in a decentralized pool.
 *         Facilitates deposits, minting, redemptions, and rebalancing of assets.
 *         Includes governance controls for updating operational parameters.
 */
contract AssetPool is IAssetPool, Ownable, Pausable, Initializable {
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
     * @notice Address of the LP Liquidity Manager contract for managing LPs.
     */
    ILPLiquidityManager public lpLiquidityManager;

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
     * @notice Reserve token balance of the pool (excluding new deposits).
     */
    uint256 public poolReserveBalance;

    /**
     * @notice Net expected change in reserves post-rebalance.
     */
    int256 public netReserveDelta;

    /**
     * @notice Asset token balance of the pool.
     */
    uint256 public poolAssetBalance;

    /**
     * @notice Net expected change in assets post-rebalance.
     */
    int256 public netAssetDelta;

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
     * @notice Maximum deviation allowed in the rebalance price.
     */
    uint256 private constant MAX_PRICE_DEVIATION = 3_00;

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
     * @param _lpLiquidityManager Address of the LP liquidity manager contract.
     * @param _cycleLength Duration of each operational cycle.
     * @param _rebalanceLength Duration of the rebalance period.
     * @param _owner Owner of the contract.
     */
    function initialize (
        address _reserveToken,
        string memory _xTokenName,
        string memory _xTokenSymbol,
        address _assetOracle,
        address _lpLiquidityManager,
        uint256 _cycleLength,
        uint256 _rebalanceLength,
        address _owner
    ) external initializer {
        if (_reserveToken == address(0) || _assetOracle == address(0) || _lpLiquidityManager == address(0)) 
            revert ZeroAddress();

        _transferOwnership(_owner);

        reserveToken = IERC20Metadata(_reserveToken);
        assetToken = new xToken(_xTokenName, _xTokenSymbol);
        lpLiquidityManager = ILPLiquidityManager(_lpLiquidityManager);
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
        if (!lpLiquidityManager.isLP(msg.sender)) revert NotLP();
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
        uint256 redemptionRequests = cycleTotalRedemptionRequests;

        // Value of redemption requests in reserve tokens
        uint256 redemptionRequestsInReserve = Math.mulDiv(redemptionRequests, assetPrice, PRECISION * reserveToAssetDecimalFactor);
        // Initial purchase value of redemption requests i.e asset tokens in the pool
        uint256 assetReserveSupplyInPool = assetToken.reserveBalanceOf(address(this));
        // Expected new asset mints
        uint256 expectedNewAssetMints = Math.mulDiv(depositRequests, PRECISION * reserveToAssetDecimalFactor, assetPrice);

        // Calculate the net change in reserves post-rebalance
        netReserveDelta = int256(depositRequests) - int256(assetReserveSupplyInPool);
        // Calculate the net change in assets post-rebalance
        netAssetDelta = int256(expectedNewAssetMints) - int256(redemptionRequests);
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
     *
     * ToDo: lpLiquidty should be based on how much being asset being rebalanced during the cycle
     * ToDo: Need to handle the case when LP doesn't rebalance within the rebalance window
     */
    function rebalancePool(address lp, uint256 rebalancePrice) external onlyLP {
        if (cycleState != CycleState.REBALANCING_ONCHAIN) revert InvalidCycleState();
        if (cycleIndex > 0 && lastRebalancedCycle[lp] == cycleIndex) revert AlreadyRebalanced();
        if (block.timestamp > lastCycleActionDateTime + rebalanceLength) revert RebalancingExpired();

        _validateRebalancingPrice(rebalancePrice);

        uint8 lpCollateralHealth = lpLiquidityManager.checkCollateralHealth(lp);
        if (lpCollateralHealth == 1) revert InsufficientLPCollateral();
        uint256 lpLiquidity = lpLiquidityManager.getLPLiquidity(lp);
        uint256 totalLiquidity = lpLiquidityManager.getTotalLPLiquidity();

        // Calculate the LP's share of the rebalance amount
        uint256 amount = 0;
        bool isDeposit = false;


        if (rebalanceAmount > 0) {
            // Positive rebalance amount means Pool needs to withdraw from LP collateral
            // The LP needs to cover the difference with their collateral
            amount = uint256(rebalanceAmount) * lpLiquidity / totalLiquidity;
            
            // Deduct from LP's collateral and transfer to pool
            lpLiquidityManager.deductRebalanceAmount(lp, amount);

        } else if (rebalanceAmount < 0) {
            // Negative rebalance amount means Pool needs to add to LP collateral
            // The LP gets back funds which are added to their collateral
            amount = uint256(-rebalanceAmount) * lpLiquidity / totalLiquidity;
            
            // Transfer from pool to LP's collateral
            reserveToken.transfer(lp, amount);
            
            // Add to LP's collateral
            lpLiquidityManager.addToCollateral(lp, amount);
        }
        // If rebalanceAmount is 0, no action needed

        cycleWeightedSum += rebalancePrice * lpLiquidity;
        lastRebalancedCycle[lp] = cycleIndex;
        rebalancedLPs++;

        emit Rebalanced(lp, rebalancePrice, amount, isDeposit, cycleIndex);

        // If all LPs have rebalanced, start next cycle
        if (rebalancedLPs == lpLiquidityManager.getLPCount()) {
            uint256 assetBalance = assetToken.balanceOf(address(this));
            uint256 reserveBalanceInAssetToken = assetToken.reserveBalanceOf(address(this));
            assetToken.burn(address(this), assetBalance, reserveBalanceInAssetToken);
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
     * @notice Validates the rebalancing price against the asset oracle.
     * @param rebalancePrice Price at which the LP is rebalancing.
     */
    function _validateRebalancingPrice(uint256 rebalancePrice) internal view {
        uint256 oraclePrice = assetOracle.assetPrice();
        
        // Calculate the allowed deviation range
        uint256 maxDeviation = (oraclePrice * MAX_PRICE_DEVIATION) / 100_00;
        uint256 minAllowedPrice = oraclePrice > maxDeviation ? oraclePrice - maxDeviation : 0;
        uint256 maxAllowedPrice = oraclePrice + maxDeviation;
        
        // Check if the rebalance price is within the allowed range
        if (rebalancePrice < minAllowedPrice || rebalancePrice > maxAllowedPrice) {
            revert PriceDeviationTooHigh();
        }
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
        poolReserveBalance = reserveToken.balanceOf(address(this));
        poolAssetBalance = assetToken.totalSupply();
        netReserveDelta = 0;
        netAssetDelta = 0;
        rebalanceAmount = 0;

        emit CycleStarted(cycleIndex, block.timestamp);
    }

    // --------------------------------------------------------------------------------
    //                            VIEW FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Returns the information about the pool.
     * @return _cycleState Current state of the pool.
     * @return _cycleIndex Current cycle index.
     * @return _assetPrice Current price of the asset.
     * @return _lastCycleActionDateTime Timestamp of the last cycle action.
     * @return _reserveBalance Reserve token balance of the pool.
     * @return _assetBalance Asset token balance of the pool.
     * @return _totalDepositRequests Total deposit requests in the current cycle.
     * @return _totalRedemptionRequests Total redemption requests in the current cycle.
     * @return _netReserveDelta Net expected change in reserves post-rebalance.
     * @return _netAssetDelta Net expected change in assets post-rebalance.
     * @return _rebalanceAmount Total amount to rebalance (PnL from reserves).
     */
    function getPoolInfo() external view returns (
        CycleState _cycleState,
        uint256 _cycleIndex,
        uint256 _assetPrice,
        uint256 _lastCycleActionDateTime,
        uint256 _reserveBalance,
        uint256 _assetBalance,
        uint256 _totalDepositRequests,
        uint256 _totalRedemptionRequests,
        int256 _netReserveDelta,
        int256 _netAssetDelta,
        int256 _rebalanceAmount
    ) {
            _cycleState = cycleState;
            _cycleIndex = cycleIndex;
            _assetPrice = assetOracle.assetPrice();
            _lastCycleActionDateTime = lastCycleActionDateTime;
            _reserveBalance = poolReserveBalance;
            _assetBalance = assetToken.totalSupply();
            _totalDepositRequests = cycleTotalDepositRequests;
            _totalRedemptionRequests = cycleTotalRedemptionRequests;
            _netReserveDelta = netReserveDelta;
            _netAssetDelta = netAssetDelta;
            _rebalanceAmount = rebalanceAmount;
    }
}