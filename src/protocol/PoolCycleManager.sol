// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/contracts/utils/Pausable.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IPoolCycleManager} from "../interfaces/IPoolCycleManager.sol";
import {IAssetPool} from "../interfaces/IAssetPool.sol";
import {IXToken} from "../interfaces/IXToken.sol";
import {IPoolLiquidityManager} from "../interfaces/IPoolLiquidityManager.sol";
import {IAssetOracle} from "../interfaces/IAssetOracle.sol";
import {PoolStorage} from "./PoolStorage.sol";

/**
 * @title PoolCycleManager
 * @notice Manages the lifecycle of operational cycles in the protocol
 * @dev Handles cycle transitions and LP rebalancing operations
 */
contract PoolCycleManager is IPoolCycleManager, PoolStorage, Pausable {
    // --------------------------------------------------------------------------------
    //                               STATE VARIABLES
    // --------------------------------------------------------------------------------

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
     * @notice Tracks the last cycle an lp rebalanced.
     */
    mapping(address => uint256) public lastRebalancedCycle;

    /**
     * @notice Rebalance price for each cycle.
     */
    mapping(uint256 => uint256) public cycleRebalancePrice;

    /**
     * @notice Weighted sum of rebalance prices for the current cycle.
     */
    uint256 private cycleWeightedSum;

    /**
     * @notice Maximum deviation allowed in the rebalance price.
     */
    uint256 private constant MAX_PRICE_DEVIATION = 3_00;

    /**
     * @notice Cumulative pool interest accrued over time
     */
    uint256 public cumulativePoolInterest;

    /**
     * @notice Total cumulative interest accrued in reserve tokens
     */
    uint256 public cumulativeInterestInReserve;

    /**
     * @notice Timestamp of the last interest accrual
     */
    uint256 public lastInterestAccrualTimestamp;

    constructor() {
        // Disable the implementation contract
        _disableInitializers();
    }

    // --------------------------------------------------------------------------------
    //                                    INITIALIZER
    // --------------------------------------------------------------------------------

    /**
     * @notice Initializes the PoolCycleManager contract with required dependencies and parameters.
     * @param _reserveToken Address of the reserve token contract (e.g., USDC).
     * @param _assetToken Address of the asset token contract.
     * @param _assetOracle Address of the asset price oracle contract.
     * @param _assetPool Address of the asset pool contract.
     * @param _poolLiquidityManager Address of the LP liquidity manager contract.
     * @param _cycleLength Duration of each operational cycle.
     * @param _rebalanceLength Duration of the rebalance period.
     */
    function initialize (
        address _reserveToken,
        address _assetToken,
        address _assetOracle,
        address _assetPool,
        address _poolLiquidityManager,
        uint256 _cycleLength,
        uint256 _rebalanceLength
    ) external initializer {
        if (_reserveToken == address(0) || _assetToken == address(0) || _assetOracle == address(0) || 
            _poolLiquidityManager == address(0) || _assetPool == address(0)) 
            revert ZeroAddress();

        reserveToken = IERC20Metadata(_reserveToken);
        assetToken = IXToken(_assetToken);
        assetPool = IAssetPool(_assetPool);
        poolLiquidityManager = IPoolLiquidityManager(_poolLiquidityManager);
        assetOracle = IAssetOracle(_assetOracle);
        cycleState = CycleState.ACTIVE;
        cycleLength = _cycleLength;
        rebalanceLength = _rebalanceLength;
        lastCycleActionDateTime = block.timestamp;

        _initializeDecimalFactor(address(reserveToken), address(assetToken));
    }

    // --------------------------------------------------------------------------------
    //                                    MODIFIERS
    // --------------------------------------------------------------------------------

    /**
     * @dev Ensures the caller is a registered LP.
     */
    modifier onlyLP() {
        if (!poolLiquidityManager.isLP(msg.sender)) revert NotLP();
        _;
    }

    // --------------------------------------------------------------------------------
    //                               REBALANCING LOGIC
    // --------------------------------------------------------------------------------

    /**
     * @notice Initiates the off-chain rebalance process.
     */
    function initiateOffchainRebalance() external whenNotPaused {
        if (cycleState != CycleState.ACTIVE) revert InvalidCycleState();
        if (block.timestamp < lastCycleActionDateTime + cycleLength) revert CycleInProgress();

        // Accrue interest before changing cycle state
        _accrueInterest();

        cycleState = CycleState.REBALANCING_OFFCHAIN;
        lastCycleActionDateTime = block.timestamp;
    }

    /**
     * @notice Initiates the onchain rebalance, calculates how much asset & stablecoin
     *         needs to move, and broadcasts instructions for LPs to act on.
     */
    function initiateOnchainRebalance() external whenNotPaused {
        if (cycleState != CycleState.REBALANCING_OFFCHAIN) revert InvalidCycleState();
        uint256 expectedDateTime = lastCycleActionDateTime + rebalanceLength;
        if (block.timestamp < expectedDateTime) revert OffChainRebalanceInProgress();
        uint256 oracleLastUpdated = assetOracle.lastUpdated();
        if (oracleLastUpdated < expectedDateTime) revert OracleNotUpdated();

        uint256 assetPrice = assetOracle.assetPrice();
        uint256 depositRequests = assetPool.cycleTotalDepositRequests();
        uint256 redemptionRequests = assetPool.cycleTotalRedemptionRequests();

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

        // Accrue interest before changing cycle state
        _accrueInterest();

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
     */
    function rebalancePool(address lp, uint256 rebalancePrice) external onlyLP whenNotPaused {
        if (cycleState != CycleState.REBALANCING_ONCHAIN) revert InvalidCycleState();
        if (cycleIndex > 0 && lastRebalancedCycle[lp] == cycleIndex) revert AlreadyRebalanced();
        if (block.timestamp > lastCycleActionDateTime + rebalanceLength) revert RebalancingExpired();

        _validateRebalancingPrice(rebalancePrice);

        uint8 lpCollateralHealth = poolLiquidityManager.checkCollateralHealth(lp);
        if (lpCollateralHealth == 1) revert InsufficientLPCollateral();
        uint256 lpLiquidity = poolLiquidityManager.getLPLiquidity(lp);
        uint256 totalLiquidity = poolLiquidityManager.getTotalLPLiquidity();

        // Calculate the LP's share of the rebalance amount
        uint256 amount = 0;
        bool isDeposit = false;

        if (rebalanceAmount > 0) {
            // Positive rebalance amount means Pool needs to withdraw from LP collateral
            // The LP needs to cover the difference with their collateral
            amount = uint256(rebalanceAmount) * lpLiquidity / totalLiquidity;
            
            // Deduct from LP's collateral and transfer to pool
            poolLiquidityManager.deductRebalanceAmount(lp, amount);
        } else if (rebalanceAmount < 0) {
            // Negative rebalance amount means Pool needs to add to LP collateral
            // The LP gets back funds which are added to their collateral
            amount = uint256(-rebalanceAmount) * lpLiquidity / totalLiquidity;
            
            // Transfer from pool to LP's collateral
            reserveToken.transfer(address(poolLiquidityManager), amount);
            
            // Add to LP's collateral
            poolLiquidityManager.addToCollateral(lp, amount);
        }
        // If rebalanceAmount is 0, no action needed

        cycleWeightedSum += rebalancePrice * lpLiquidity;
        lastRebalancedCycle[lp] = cycleIndex;
        rebalancedLPs++;

        emit Rebalanced(lp, rebalancePrice, amount, isDeposit, cycleIndex);

        // If all LPs have rebalanced, start next cycle
        if (rebalancedLPs == poolLiquidityManager.getLPCount()) {
            uint256 assetBalance = assetToken.balanceOf(address(this));
            uint256 reserveBalanceInAssetToken = assetToken.reserveBalanceOf(address(this));
            assetToken.burn(address(this), assetBalance, reserveBalanceInAssetToken);
            cycleRebalancePrice[cycleIndex] = cycleWeightedSum / totalLiquidity;
            
            _startNewCycle();
        }
    }

    /**
     * @notice Settle the pool if the rebalance window has expired and pool is not fully rebalanced.
     */
    function settlePool() external onlyLP whenNotPaused {
        if (cycleState != CycleState.REBALANCING_ONCHAIN) revert InvalidCycleState();
        if (block.timestamp < lastCycleActionDateTime + rebalanceLength) revert OnChainRebalancingInProgress();
        
        _startNewCycle();
    }

    /**
     * @notice If there is nothing to rebalance, start the next cycle.
     */
    function startNewCycle() external whenNotPaused {
        if (cycleState == CycleState.ACTIVE) revert InvalidCycleState();
        if (assetPool.cycleTotalDepositRequests() > 0) revert InvalidCycleRequest();
        if (assetPool.cycleTotalRedemptionRequests() > 0) revert InvalidCycleRequest();
        
        _startNewCycle();
    }

    // --------------------------------------------------------------------------------
    //                          INTEREST CALCULATION LOGIC
    // --------------------------------------------------------------------------------

    /**
     * @notice Accrues interest based on the current rate, time elapsed, and cycle/rebalance periods
     * @dev Updates cumulativePoolInterest
     */
    function _accrueInterest() internal {
        uint256 currentTimestamp = block.timestamp;
        if (currentTimestamp <= lastInterestAccrualTimestamp) {
            return;
        }
        
        // Convert BPS interest rate (10000 = 100%) to ray (1e27)
        uint256 currentRate = assetPool.getCurrentInterestRate();
        uint256 rateWithPrecision = Math.mulDiv(currentRate, PRECISION, BPS);
        
        // Calculate time elapsed since last accrual in seconds
        uint256 timeElapsed = currentTimestamp - lastInterestAccrualTimestamp;
        
        // Calculate interest for the elapsed time
        // Formula: interest = rate * timeElapsed / secondsPerYear
        uint256 interest = Math.mulDiv(rateWithPrecision, timeElapsed, SECONDS_PER_YEAR);

        // Update cumulativeInterestInReserve
        uint256 assetSupply = assetToken.totalSupply();
        uint256 assetPrice = assetOracle.assetPrice();
        if (cycleState == CycleState.ACTIVE) {
            assetPrice = cycleRebalancePrice[cycleIndex - 1];
        }
        uint256 assetValueInReserve = Math.mulDiv(assetSupply, assetPrice, PRECISION * reserveToAssetDecimalFactor);
        uint256 newInterestInReserve = Math.mulDiv(assetValueInReserve, interest, PRECISION);
        cumulativeInterestInReserve += newInterestInReserve;
        
        // Add interest to cumulative total
        cumulativePoolInterest += interest;
        
        // Update last accrual timestamp
        lastInterestAccrualTimestamp = currentTimestamp;
        
        emit InterestAccrued(interest, cumulativePoolInterest, currentTimestamp);
    }

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
        cycleWeightedSum = 0;
        lastCycleActionDateTime = block.timestamp;
        poolReserveBalance = reserveToken.balanceOf(address(this));
        poolAssetBalance = assetToken.totalSupply();
        netReserveDelta = 0;
        netAssetDelta = 0;
        rebalanceAmount = 0;

        // Accrue interest before changing cycle state
        _accrueInterest();

        // Reset cycle totals in the AssetPool
        assetPool.chargeInterestForCycle();
        assetPool.distributeInterestToLPs();

        emit CycleStarted(cycleIndex, block.timestamp);
    }
    
    // --------------------------------------------------------------------------------
    //                            VIEW FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Returns information about the pool.
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
        _totalDepositRequests = assetPool.cycleTotalDepositRequests();
        _totalRedemptionRequests = assetPool.cycleTotalRedemptionRequests();
        _netReserveDelta = netReserveDelta;
        _netAssetDelta = netAssetDelta;
        _rebalanceAmount = rebalanceAmount;
    }
}