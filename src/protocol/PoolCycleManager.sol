// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {IPoolCycleManager} from "../interfaces/IPoolCycleManager.sol";
import {IAssetPool} from "../interfaces/IAssetPool.sol";
import {IXToken} from "../interfaces/IXToken.sol";
import {IPoolLiquidityManager} from "../interfaces/IPoolLiquidityManager.sol";
import {IAssetOracle} from "../interfaces/IAssetOracle.sol";
import {IPoolStrategy} from "../interfaces/IPoolStrategy.sol";
import {PoolStorage} from "./PoolStorage.sol";

/**
 * @title PoolCycleManager
 * @notice Manages the lifecycle of operational cycles in the protocol
 * @dev Handles cycle transitions and LP rebalancing operations
 */
contract PoolCycleManager is IPoolCycleManager, PoolStorage, Multicall {
    // --------------------------------------------------------------------------------
    //                               STATE VARIABLES
    // --------------------------------------------------------------------------------

    /**
     * @notice Index of the current operational cycle.
     */
    uint256 public cycleIndex;

    /**
     * @notice Current state of the pool (ACTIVE or REBALANCING etc).
     */
    CycleState public cycleState;

    /**
     * @notice Timestamp of the last cycle action.
     */
    uint256 public lastCycleActionDateTime;

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
     * @notice Cumulative pool interest accrued over time (in Precision units) as of the current cycle.
     */
    mapping (uint256 => uint256) public cyclePoolInterest;

    /**
     * @notice Total interest accrued in the current cycle (in terms of asset).
     */
    uint256 public cycleInterestAmount;

    /**
     * @notice Asset price high for the current cycle
     */
    uint256 public cyclePriceHigh;

    /**
     * @notice Asset price low for the current cycle
     */
    uint256 public cyclePriceLow;

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
     * @param _poolStrategy Address of the pool strategy contract.
     */
    function initialize (
        address _reserveToken,
        address _assetToken,
        address _assetOracle,
        address _assetPool,
        address _poolLiquidityManager,
        address _poolStrategy
    ) external initializer {
        if (_reserveToken == address(0) || _assetToken == address(0) || _assetOracle == address(0) || 
            _poolLiquidityManager == address(0) || _assetPool == address(0)) 
            revert ZeroAddress();

        reserveToken = IERC20Metadata(_reserveToken);
        assetToken = IXToken(_assetToken);
        assetPool = IAssetPool(_assetPool);
        poolLiquidityManager = IPoolLiquidityManager(_poolLiquidityManager);
        poolStrategy = IPoolStrategy(_poolStrategy);
        assetOracle = IAssetOracle(_assetOracle);
        cycleState = CycleState.POOL_ACTIVE;
        lastCycleActionDateTime = block.timestamp;
        cycleIndex = 1;
        cyclePoolInterest[cycleIndex] = 1e18;

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
    function initiateOffchainRebalance() external {
        if (cycleState != CycleState.POOL_ACTIVE) revert InvalidCycleState();
        uint256 oracleLastUpdated = assetOracle.lastUpdated();
        if (block.timestamp - oracleLastUpdated > poolStrategy.oracleUpdateThreshold()) revert OracleNotUpdated();
        if (!assetOracle.isMarketOpen()) revert MarketClosed();

        // Accrue interest before changing cycle state
        _accrueInterest();

        cycleState = CycleState.POOL_REBALANCING_OFFCHAIN;
        lastCycleActionDateTime = block.timestamp;
    }

    /**
     * @notice Initiates the onchain rebalance, calculates how much asset & stablecoin
     *         needs to move, and broadcasts instructions for LPs to act on.
     */
    function initiateOnchainRebalance() external {
        if (cycleState != CycleState.POOL_REBALANCING_OFFCHAIN) revert InvalidCycleState();
        uint256 oracleLastUpdated = assetOracle.lastUpdated();
        if (block.timestamp - oracleLastUpdated > poolStrategy.oracleUpdateThreshold()) revert OracleNotUpdated();
        if (assetOracle.isMarketOpen()) revert MarketOpen();
        if (assetOracle.splitDetected()) {
            if (assetPool.isPriceDeviationValid()) {
                assetPool.updateIsPriceDeviationValid();
            } else {
                revert PriceDeviationHigh();
            }
        }

        (,cyclePriceHigh, cyclePriceLow, ,) = assetOracle.getOHLCData();

        // Accrue interest before changing cycle state
        _accrueInterest();

        lastCycleActionDateTime = block.timestamp;
        cycleState = CycleState.POOL_REBALANCING_ONCHAIN;

        emit RebalanceInitiated(
            cycleIndex,
            cyclePriceHigh,
            cyclePriceLow
        );
    }

    /**
     * @notice Once LPs have traded off-chain, they deposit or withdraw stablecoins accordingly.
     * @param lp Address of the LP performing the final on-chain step
     * @param rebalancePrice Price at which the rebalance was executed
     */
    function rebalancePool(address lp, uint256 rebalancePrice) external onlyLP {
        if (lp != msg.sender) revert UnauthorizedCaller();
        if (cycleState != CycleState.POOL_REBALANCING_ONCHAIN) revert InvalidCycleState();
        if (lastRebalancedCycle[lp] == cycleIndex) revert AlreadyRebalanced();
        if (block.timestamp > lastCycleActionDateTime + poolStrategy.rebalanceLength()) revert RebalancingExpired();

        _validateRebalancingPrice(rebalancePrice);

        uint8 lpLiquidityHealth = poolStrategy.getLPLiquidityHealth(address(poolLiquidityManager), lp);
        if (lpLiquidityHealth < 3) revert InsufficientLPLiquidity();
        uint256 lpLiquidityCommitment = poolLiquidityManager.getLPLiquidityCommitment(lp);
        uint256 totalLiquidity = poolLiquidityManager.totalLPLiquidityCommited();

        // Calculate the LP's share of the rebalance amount
        uint256 amount = 0;
        bool isDeposit = false;
        int256 rebalanceAmount = calculateRebalanceAmount(rebalancePrice);
        if (rebalanceAmount > 0) {
            // Positive rebalance amount means Pool needs to withdraw from LP collateral
            // The LP needs to cover the difference with their collateral
            amount = Math.mulDiv(uint256(rebalanceAmount), lpLiquidityCommitment, totalLiquidity);
            isDeposit = true;
            
            if (amount > 0) {
                // Transfer funds from LP's wallet to the pool
                reserveToken.transferFrom(lp, address(assetPool), amount);
            }
            
        } else if (rebalanceAmount < 0) {
            // Negative rebalance amount means Pool needs to add to LP liquidity
            // The LP gets back funds which are added to their liquidity
            amount = Math.mulDiv(uint256(-rebalanceAmount), lpLiquidityCommitment, totalLiquidity);
            
            if (amount > 0) {
                // Request the asset pool to transfer funds to the LP
                assetPool.transferRebalanceAmount(lp, amount, false);
            }
        }
        // If rebalanceAmount is 0, no action needed

        if (totalLiquidity > 0) {
            // Calculate interest for the LP's liquidity commitment
            uint256 interestAmount = Math.mulDiv(cycleInterestAmount, rebalancePrice, PRECISION);
            // Calculate the LP's share of the interest amount
            uint256 lpCycleInterest = Math.mulDiv(interestAmount, lpLiquidityCommitment, totalLiquidity);
            // Deduct interest from the pool and add to LP's collateral
            if (lpCycleInterest > 0) {
                assetPool.deductInterest(lp, lpCycleInterest, false);
            }
        }
        
        poolLiquidityManager.resolveRequest(lp);
        if (poolLiquidityManager.isLP(lp)) {
            lpLiquidityCommitment = poolLiquidityManager.getLPLiquidityCommitment(lp);
        } else {
            lpLiquidityCommitment = 0;
        }
        // calculate the weighted sum of the rebalance price
        cycleWeightedSum += Math.mulDiv(rebalancePrice, lpLiquidityCommitment * reserveToAssetDecimalFactor, PRECISION);
        lastRebalancedCycle[lp] = cycleIndex;
        rebalancedLPs++;

        emit Rebalanced(lp, rebalancePrice, amount, isDeposit, cycleIndex);

        // If all LPs have rebalanced, start next cycle
        if (rebalancedLPs == poolLiquidityManager.getLPCount()) {
            _startNewCycle(CycleState.POOL_ACTIVE);
        }
    }

    /**
     * @notice Rebalance an lp if the rebalance window has expired and the LP has not rebalanced
     * @dev This is also called the settlement step
     * @dev For transferRebalanceAmount & deductInterest isSettle is true,
     * @dev as we are settling the rebalance amount from the LP's collateral  
     * @param lp Address of the LP to rebalance
     */
    function rebalanceLP(address lp) external {
        if (cycleState != CycleState.POOL_REBALANCING_ONCHAIN) revert InvalidCycleState();
        if (block.timestamp < lastCycleActionDateTime + poolStrategy.rebalanceLength()) revert OnChainRebalancingInProgress();
        if (block.timestamp > lastCycleActionDateTime + poolStrategy.haltThreshold()) revert RebalancingExpired();
        if (lastRebalancedCycle[lp] == cycleIndex) revert AlreadyRebalanced();
        if (!poolLiquidityManager.isLP(lp)) revert NotLP();

        // Calculate the settlement price (average of high and low)
        uint256 settlementPrice = (cyclePriceHigh + cyclePriceLow) / 2;

        uint256 lpLiquidityCommitment = poolLiquidityManager.getLPLiquidityCommitment(lp);
        uint256 totalLiquidity = poolLiquidityManager.totalLPLiquidityCommited();

        // Calculate the LP's share of the rebalance amount
        uint256 amount = 0;
        bool isDeposit = false;
        int256 rebalanceAmount = calculateRebalanceAmount(settlementPrice);
        
        if (rebalanceAmount > 0) {
            // Positive rebalance amount means Pool needs to withdraw from LP collateral
            amount = Math.mulDiv(uint256(rebalanceAmount), lpLiquidityCommitment, totalLiquidity);
            isDeposit = true;
            
            if (amount > 0) {
                // Use LP's collateral to settle
                poolLiquidityManager.deductFromCollateral(lp, amount);
            }
        } else if (rebalanceAmount < 0) {
            // Negative rebalance amount means Pool needs to add to LP liquidity
            amount = Math.mulDiv(uint256(-rebalanceAmount), lpLiquidityCommitment, totalLiquidity);
            
            if (amount > 0) {
                // Transfer funds to the LP
                assetPool.transferRebalanceAmount(lp, amount, true);
            }
        }

        if (totalLiquidity > 0) {
            // Calculate interest for the LP's liquidity commitment
            uint256 interestAmount = Math.mulDiv(cycleInterestAmount, settlementPrice, PRECISION);
            uint256 lpCycleInterest = Math.mulDiv(interestAmount, lpLiquidityCommitment, totalLiquidity);
            // Deduct interest from the pool and add to LP's collateral
            if (lpCycleInterest > 0) {
                assetPool.deductInterest(lp, lpCycleInterest, false);
            }
        }
        
        // Resolve any pending requests for the LP
        poolLiquidityManager.resolveRequest(lp);
        if (poolLiquidityManager.isLP(lp)) {
            lpLiquidityCommitment = poolLiquidityManager.getLPLiquidityCommitment(lp);
        } else {
            lpLiquidityCommitment = 0;
        }
        // calculate the weighted sum of the rebalance price
        cycleWeightedSum += Math.mulDiv(settlementPrice, lpLiquidityCommitment * reserveToAssetDecimalFactor, PRECISION);
        lastRebalancedCycle[lp] = cycleIndex;
        rebalancedLPs++;
        
        emit Rebalanced(lp, settlementPrice, amount, isDeposit, cycleIndex);
        
        // If all LPs have rebalanced, start next cycle
        if (rebalancedLPs == poolLiquidityManager.getLPCount()) {
            _startNewCycle(CycleState.POOL_ACTIVE);
        }
    }

    /**
     * @notice Force rebalance an lp if the pool halt threshold window has reached and the LP has not rebalanced
     * @dev This is also called the forced settlement step and once settled by all LPs, the pool is halted
     * @dev The pool is halted because the pool is being rebalanced with a deviation
     * @param lp Address of the LP to rebalance
     */
    function forceRebalanceLP(address lp) external {
        if (cycleState != CycleState.POOL_REBALANCING_ONCHAIN) revert InvalidCycleState();
        if (block.timestamp < lastCycleActionDateTime + poolStrategy.haltThreshold()) revert InvalidCycleState();
        if (lastRebalancedCycle[lp] == cycleIndex) revert AlreadyRebalanced();
        if (!poolLiquidityManager.isLP(lp)) revert NotLP();

        uint256 lpCollateral = poolLiquidityManager.getLPCollateral(lp);
        bool isDeposit = false;

        if (lpCollateral > 0) {
            // Use LP's balance collateral to settle as much as possible
            poolLiquidityManager.deductFromCollateral(lp, lpCollateral);
            isDeposit = true;
        }

        uint256 settlementPrice = calculateRebalancePriceForAmount(int256(lpCollateral));

        uint256 lpLiquidityCommitment = poolLiquidityManager.getLPLiquidityCommitment(lp);
        uint256 totalLiquidity = poolLiquidityManager.totalLPLiquidityCommited();

        if (totalLiquidity > 0) {
            // Calculate interest for the LP's liquidity commitment
            uint256 interestAmount = Math.mulDiv(cycleInterestAmount, settlementPrice, PRECISION);
            uint256 lpCycleInterest = Math.mulDiv(interestAmount, lpLiquidityCommitment, totalLiquidity);
            // Deduct interest from the pool and add to LP's collateral
            if (lpCycleInterest > 0) {
                assetPool.deductInterest(lp, lpCycleInterest, true);
            }
        }
        
        // Resolve any pending requests for the LP
        poolLiquidityManager.resolveRequest(lp);
        if (poolLiquidityManager.isLP(lp)) {
            lpLiquidityCommitment = poolLiquidityManager.getLPLiquidityCommitment(lp);
        } else {
            lpLiquidityCommitment = 0;
        }
        // calculate the weighted sum of the rebalance price
        cycleWeightedSum += Math.mulDiv(settlementPrice, lpLiquidityCommitment * reserveToAssetDecimalFactor, PRECISION);
        lastRebalancedCycle[lp] = cycleIndex;
        rebalancedLPs++;
        
        emit Rebalanced(lp, settlementPrice, lpCollateral, isDeposit, cycleIndex);
        
        // If all LPs have rebalanced, start next cycle
        if (rebalancedLPs == poolLiquidityManager.getLPCount()) {
            _startNewCycle(CycleState.POOL_HALTED);
        }
    }


    // --------------------------------------------------------------------------------
    //                          INTEREST CALCULATION LOGIC
    // --------------------------------------------------------------------------------

    /**
     * @notice Accrues interest based on the current rate, time elapsed, and cycle/rebalance periods
     * @dev Updates cyclePoolInterest
     */
    function _accrueInterest() internal {
        uint256 currentTimestamp = block.timestamp;
        if (currentTimestamp <= lastInterestAccrualTimestamp) {
            return;
        }
        
        // Convert BPS interest rate (10000 = 100%) to a rate with precision
        uint256 currentRate = assetPool.getCurrentInterestRate();
        uint256 rateWithPrecision = Math.mulDiv(currentRate, PRECISION, BPS);
        
        // Calculate time elapsed since last accrual in seconds
        uint256 timeElapsed = currentTimestamp - lastInterestAccrualTimestamp;
        
        // Calculate interest for the elapsed time
        // Formula: interest = rate * timeElapsed / secondsPerYear
        uint256 interest = Math.mulDiv(rateWithPrecision, timeElapsed, SECONDS_PER_YEAR);
        
        // Add interest to cumulative total
        cyclePoolInterest[cycleIndex] += interest;
        // Calculate the interest amount in terms of asset
        cycleInterestAmount += _convertAssetToReserve(assetToken.totalSupply(), interest);
        
        // Update last accrual timestamp
        lastInterestAccrualTimestamp = currentTimestamp;
        
        emit InterestAccrued(interest, cyclePoolInterest[cycleIndex], currentTimestamp);
    }

    // --------------------------------------------------------------------------------
    //                            INTERNAL FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Calculates the rebalance amount based on the asset price.
     * @dev If assetPrice is prevCyclePrice, the pool is in equilibrium.
     * @dev If assetPrice is greater than prevCyclePrice, the pool is in deficit.
     * @dev If assetPrice is less than prevCyclePrice, the pool is in surplus.
     * @param assetPrice rebalance price of the asset.
     */
    function calculateRebalanceAmount(uint256 assetPrice) internal view returns (int256) {
        uint256 poolAssetValue = _convertAssetToReserve(assetToken.totalSupply(), assetPrice);
        uint256 poolReserveValue = assetPool.reserveBackingAsset();
        return int256(poolAssetValue) - int256(poolReserveValue);
    }

    /**
     * @notice Calculates the rebalance price for a given amount.
     * @param rebalanceAmount Amount to be rebalanced.
     * @return The calculated rebalance price.
     */
    function calculateRebalancePriceForAmount(int256 rebalanceAmount) internal view returns (uint256) {
        uint256 poolReserveValue = assetPool.reserveBackingAsset();
        int256 targetAssetValue = rebalanceAmount + int256(poolReserveValue);

        return _convertReserveToAsset(uint256(targetAssetValue), assetToken.totalSupply());
    }

    /**
     * @notice Validates the rebalancing price against the asset oracle.
     * @param rebalancePrice Price at which the LP is rebalancing.
     */
    function _validateRebalancingPrice(uint256 rebalancePrice) internal view {
        if (rebalancePrice < cyclePriceLow || rebalancePrice > cyclePriceHigh) {
            revert InvalidRebalancePrice();
        }
    }

    /**
     * @notice Starts a new cycle after all LPs have rebalanced.
     */
    function _startNewCycle(CycleState newCycleState) internal {

        poolLiquidityManager.updateCycleData();
        // calculate the rebalance price for the cycle
        // The cycleWeightedSum is divided by the total LP liquidity committed to get the average price
        uint256 price = (cycleWeightedSum * PRECISION) / (poolLiquidityManager.totalLPLiquidityCommited() * reserveToAssetDecimalFactor);
        cycleRebalancePrice[cycleIndex] = price;
        int256 finalRebalanceAmount = calculateRebalanceAmount(price);

        assetPool.updateCycleData(price, finalRebalanceAmount);

        cycleIndex++;
        cycleState = newCycleState;
        rebalancedLPs = 0;
        cycleWeightedSum = 0;
        lastCycleActionDateTime = block.timestamp;
        cycleInterestAmount = 0;
        cyclePoolInterest[cycleIndex] = cyclePoolInterest[cycleIndex - 1];
        cyclePriceHigh = 0;
        cyclePriceLow = 0;
        
        emit CycleStarted(cycleIndex, block.timestamp);
    }
    
    // --------------------------------------------------------------------------------
    //                            VIEW FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Calculates the expected rebalance amount for a specific LP at a given price
     * @dev This helper function allows LPs to determine how much they need to approve/have available
     * @param lp Address of the LP
     * @param rebalancePrice Price at which to calculate the rebalance
     * @return rebalanceAmount The amount the LP needs to contribute (positive) or will receive (negative)
     * @return isDeposit True if LP needs to deposit funds, false if LP will receive funds
     */
    function calculateLPRebalanceAmount(address lp, uint256 rebalancePrice) public view returns (uint256 rebalanceAmount, bool isDeposit) {
        // Validate the LP is registered
        if (!poolLiquidityManager.isLP(lp)) revert NotLP();
        
        // Get LP's liquidity commitment and total liquidity
        uint256 lpLiquidityCommitment = poolLiquidityManager.getLPLiquidityCommitment(lp);
        uint256 totalLiquidity = poolLiquidityManager.totalLPLiquidityCommited();
        
        if (totalLiquidity == 0) return (0, false);
        
        // Calculate overall rebalance amount based on price
        int256 overallRebalanceAmount = calculateRebalanceAmount(rebalancePrice);
        
        if (overallRebalanceAmount > 0) {
            // Positive rebalance amount means LP needs to deposit funds
            rebalanceAmount = Math.mulDiv(uint256(overallRebalanceAmount), lpLiquidityCommitment, totalLiquidity);
            isDeposit = true;
        } else if (overallRebalanceAmount < 0) {
            // Negative rebalance amount means LP will receive funds
            rebalanceAmount = Math.mulDiv(uint256(-overallRebalanceAmount), lpLiquidityCommitment, totalLiquidity);
            isDeposit = false;
        } else {
            // Zero rebalance amount, no action needed
            rebalanceAmount = 0;
            isDeposit = false;
        }
        
        return (rebalanceAmount, isDeposit);
    }

    /**
     * @notice Returns information about the pool.
     * @return _cycleState Current state of the pool.
     * @return _cycleIndex Current cycle index.
     * @return _assetPrice Last pool rebalance price of the asset.
     * @return _lastCycleActionDateTime Timestamp of the last cycle action.
     * @return _reserveBackingAsset Amount of reserve token backing the assets.
     * @return _assetBalance Asset token balance of the pool.
     * @return _totalDepositRequests Total deposit requests in the current cycle.
     * @return _totalRedemptionRequests Total redemption requests in the current cycle.
     */
    function getPoolInfo() external view returns (
        CycleState _cycleState,
        uint256 _cycleIndex,
        uint256 _assetPrice,
        uint256 _lastCycleActionDateTime,
        uint256 _reserveBackingAsset,
        uint256 _assetBalance,
        uint256 _totalDepositRequests,
        uint256 _totalRedemptionRequests
    ) {
        _cycleState = cycleState;
        _cycleIndex = cycleIndex;
        _assetPrice = cycleRebalancePrice[cycleIndex - 1];
        _lastCycleActionDateTime = lastCycleActionDateTime;
        _reserveBackingAsset = assetPool.reserveBackingAsset();
        _assetBalance = assetToken.totalSupply();
        _totalDepositRequests = assetPool.cycleTotalDeposits();
        _totalRedemptionRequests = assetPool.cycleTotalRedemptions();
    }
}