// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
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
contract PoolCycleManager is IPoolCycleManager, PoolStorage, Ownable, Multicall {
    using SafeERC20 for IERC20Metadata;

    // --------------------------------------------------------------------------------
    //                               STATE VARIABLES
    // --------------------------------------------------------------------------------

    /**
     * @notice Index of the current operational cycle.
     */
    uint256 public cycleIndex;

    /**
     * @notice Timestamp of the last cycle action.
     */
    uint256 public lastCycleActionDateTime;

    /**
     * @notice Count of LPs who have completed rebalancing in the current cycle.
     */
    uint256 public rebalancedLPs;

    /**
     * @notice Amount of reserve to be rebalanced in the current cycle.
     */
    int256 public cycleRebalanceAmount;

    /**
     * @notice Weighted sum of rebalance prices for the current cycle.
     */
    uint256 private cycleWeightedSum;

    /**
     * @notice Total interest accrued in the current cycle (in terms of asset).
     */
    uint256 public cycleInterestAmount;

    /**
     * @notice Asset price open for the current cycle
     */
    uint256 public cyclePriceOpen;

    /**
     * @notice Asset price close for the current cycle
     */
    uint256 public cyclePriceClose;

    /**
     * @notice Number of LPs who need to rebalance in the current cycle
     */
    uint256 public cycleLPCount;

    /**
     * @notice Amount of liquidity that wants the pool to halt
     */
    uint256 public poolHaltAmount;

    /**
     * @notice Timestamp of the last interest accrual
     */
    uint256 public lastInterestAccrualTimestamp;

    /**
     * @notice Number of token splits that have occurred in the pool.
     */
    uint256 public poolSplitIndex;

    /**
     * @notice Multiplier of each split that has occurred in the pool.
     */
    mapping(uint256 => uint256) public splitMultiplier;

    /**
     * @notice Cumulative pool interest paid per asset till the current cycle.
     */
    mapping (uint256 => uint256) public cumulativeInterestIndex;

    /**
     * @notice Tracks the last cycle an lp rebalanced.
     */
    mapping(address => uint256) public lastRebalancedCycle;

    /**
     * @notice Rebalance price for each cycle.
     */
    mapping(uint256 => uint256) public cycleRebalancePrice;

    /**
     * @notice Current state of the pool (ACTIVE or REBALANCING etc).
     */
    CycleState public cycleState;

    /**
     * @notice Flag to indicate if the price deviation is valid
     */
    bool public isPriceDeviationValid;
    
    constructor() Ownable(msg.sender) {
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
        address _poolCycleManager,
        address _poolLiquidityManager,
        address _poolStrategy,
        address _owner
    ) external initializer {
        if (_reserveToken == address(0) || _assetToken == address(0) || _assetOracle == address(0) || 
            _poolLiquidityManager == address(0) || _assetPool == address(0)) 
            revert ZeroAddress();

        reserveToken = IERC20Metadata(_reserveToken);
        assetToken = IXToken(_assetToken);
        assetOracle = IAssetOracle(_assetOracle);
        assetPool = IAssetPool(_assetPool);
        poolCycleManager = IPoolCycleManager(_poolCycleManager);
        poolLiquidityManager = IPoolLiquidityManager(_poolLiquidityManager);
        poolStrategy = IPoolStrategy(_poolStrategy);
        cycleState = CycleState.POOL_ACTIVE;
        lastCycleActionDateTime = block.timestamp;
        cycleIndex = 1;
        cumulativeInterestIndex[1] = 1e18; // Initialize interest index for cycle 1
        splitMultiplier[0] = 1e18; // Initialize split multiplier for no splits

        _initializeDecimalFactor(address(reserveToken), address(assetToken));

        // Transfer ownership to the specified address
        _transferOwnership(_owner);
    }

    // --------------------------------------------------------------------------------
    //                               REBALANCING LOGIC
    // --------------------------------------------------------------------------------

    /**
     * @notice Initiates the off-chain rebalance process.
     */
    function initiateOffchainRebalance() external {
        if (cycleState != CycleState.POOL_ACTIVE) revert InvalidCycleState();
        if (poolLiquidityManager.lpCount() == 0) revert InvalidCycleState();
        uint256 oracleLastUpdated = assetOracle.lastUpdated();
        if (block.timestamp - oracleLastUpdated > poolStrategy.oracleUpdateThreshold()) revert OracleNotUpdated();
        if (!assetOracle.isMarketOpen()) revert MarketClosed();

        cycleState = CycleState.POOL_REBALANCING_OFFCHAIN;

        emit RebalanceInitiated(cycleIndex, cycleState);
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
            if (isPriceDeviationValid) {
                _updateIsPriceDeviationValid();
            } else {
                revert PriceDeviationHigh();
            }
        }

        (cyclePriceOpen, , , cyclePriceClose,) = assetOracle.ohlcData();

        // Accrue interest before changing cycle state
        _accrueInterest();

        lastCycleActionDateTime = block.timestamp;
        cycleState = CycleState.POOL_REBALANCING_ONCHAIN;
        cycleLPCount = poolLiquidityManager.lpCount();

        emit RebalanceInitiated(cycleIndex, cycleState);
    }

    /**
     * @notice Once LPs have traded off-chain, they deposit or withdraw stablecoins accordingly.
     * @param lp Address of the LP performing the final on-chain step
     * @param rebalancePrice Price at which the rebalance was executed
     */
    function rebalancePool(address lp, uint256 rebalancePrice) public {
        if (!poolLiquidityManager.isLPActive(lp)) revert NotLP();
        address delegate = poolLiquidityManager.lpDelegates(lp);
        if (lp != msg.sender && (delegate == address(0) || msg.sender != delegate)) revert UnauthorizedCaller();
        if (cycleState != CycleState.POOL_REBALANCING_ONCHAIN) revert InvalidCycleState();
        if (lastRebalancedCycle[lp] == cycleIndex) revert AlreadyRebalanced();
        if (block.timestamp > lastCycleActionDateTime + poolStrategy.rebalanceLength()) revert RebalancingExpired();

        _validateRebalancingPrice(rebalancePrice);

        uint8 lpLiquidityHealth = poolStrategy.getLPLiquidityHealth(address(poolLiquidityManager), lp);
        if (lpLiquidityHealth == 1) revert InsufficientLPLiquidity();
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
            cycleRebalanceAmount += int256(amount);
            isDeposit = true;
            
            if (amount > 0) {
                // Transfer funds from LP's wallet to the pool
                reserveToken.safeTransferFrom(lp, address(assetPool), amount);
            }
            
        } else if (rebalanceAmount < 0) {
            // Negative rebalance amount means Pool needs to add to LP liquidity
            // The LP gets back funds which are added to their liquidity
            amount = Math.mulDiv(uint256(-rebalanceAmount), lpLiquidityCommitment, totalLiquidity);
            cycleRebalanceAmount -= int256(amount);
            if (amount > 0) {
                // Request the asset pool to transfer funds to the LP
                assetPool.transferRebalanceAmount(lp, amount, false);
                emit RebalanceAmountTransferred(lp, amount, cycleIndex);
                
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
        lpLiquidityCommitment = poolLiquidityManager.getLPLiquidityCommitment(lp);

        // calculate the weighted sum of the rebalance price
        cycleWeightedSum += Math.mulDiv(rebalancePrice, lpLiquidityCommitment * reserveToAssetDecimalFactor, PRECISION);
        lastRebalancedCycle[lp] = cycleIndex;
        rebalancedLPs++;

        emit Rebalanced(lp, rebalancePrice, amount, isDeposit, cycleIndex);

        // If all LPs have rebalanced, start next cycle
        if (rebalancedLPs == cycleLPCount) {
            uint256 poolHaltPercent = 0;
            uint256 availableLiquidity = poolStrategy.calculateCycleAvailableLiquidity(address(assetPool));
            if (poolHaltAmount > 0 && totalLiquidity > 0) {
                // Calculate the halt percentage based on the pool halt amount
                poolHaltPercent = Math.mulDiv(poolHaltAmount, BPS, totalLiquidity);
            }
            // if poolHaltPercent is greater than the halt liquidity percent
            if (poolHaltPercent > poolStrategy.haltLiquidityPercent() && poolHaltAmount > availableLiquidity) {
                _startNewCycle(CycleState.POOL_HALTED);
            } else {
                _startNewCycle(CycleState.POOL_ACTIVE);
            }
        }
    }

    /**
     * @notice Rebalance the pool with halt request. This can be used when lp wants to halt the pool
     * @param lp Address of the LP to rebalance
     * @param rebalancePrice The price to use for rebalancing
     * @param haltPool Whether to halt the pool
     */
    function rebalancePool(address lp, uint256 rebalancePrice, bool haltPool) external {
        if (haltPool && cycleIndex > poolStrategy.haltRequestThreshold()) {
            uint256 liquidityCommitment = poolLiquidityManager.getLPLiquidityCommitment(lp);
            uint256 haltFee = Math.mulDiv(liquidityCommitment, poolStrategy.haltFeePercent(), BPS);
            // Transfer halt fee to the fee recipient
            reserveToken.safeTransferFrom(lp, poolStrategy.feeRecipient(), haltFee);
            poolHaltAmount += liquidityCommitment;
        }
        rebalancePool(lp, rebalancePrice);
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
        if (!poolLiquidityManager.isLPActive(lp)) revert NotLP();

        // Calculate the settlement price (average of open and close)
        uint256 settlementPrice = (cyclePriceOpen + cyclePriceClose) / 2;

        uint256 lpLiquidityCommitment = poolLiquidityManager.getLPLiquidityCommitment(lp);
        uint256 totalLiquidity = poolLiquidityManager.totalLPLiquidityCommited();

        // Calculate the LP's share of the rebalance amount
        uint256 amount = 0;
        bool isDeposit = false;
        int256 rebalanceAmount = calculateRebalanceAmount(settlementPrice);

        if (rebalanceAmount > 0) {
            // Positive rebalance amount means Pool needs to withdraw from LP collateral
            amount = Math.mulDiv(uint256(rebalanceAmount), lpLiquidityCommitment, totalLiquidity);
            cycleRebalanceAmount += int256(amount);
            isDeposit = true;
            
            if (amount > 0) {
                // Use LP's collateral to settle
                poolLiquidityManager.deductFromCollateral(lp, amount);
            }
        } else if (rebalanceAmount < 0) { 
            // Negative rebalance amount means Pool needs to add to LP liquidity
            amount = Math.mulDiv(uint256(-rebalanceAmount), lpLiquidityCommitment, totalLiquidity);
            cycleRebalanceAmount -= int256(amount);
            if (amount > 0) {
                // Transfer funds to the LP
                assetPool.transferRebalanceAmount(lp, amount, true);
            }
        }

        if (totalLiquidity > 0) {
            // Calculate interest for the LP's liquidity commitment
            uint256 interestAmount = Math.mulDiv(cycleInterestAmount, settlementPrice, PRECISION);
            uint256 lpCycleInterest = Math.mulDiv(interestAmount, lpLiquidityCommitment, totalLiquidity);
            // Deduct interest from the pool and transfer it to the protocol as penalty
            if (lpCycleInterest > 0) {
                assetPool.deductInterest(lp, lpCycleInterest, true);
            }
        }
        
        // Resolve any pending requests for the LP
        poolLiquidityManager.resolveRequest(lp);
        lpLiquidityCommitment = poolLiquidityManager.getLPLiquidityCommitment(lp);

        // calculate the weighted sum of the rebalance price
        cycleWeightedSum += Math.mulDiv(settlementPrice, lpLiquidityCommitment * reserveToAssetDecimalFactor, PRECISION);
        lastRebalancedCycle[lp] = cycleIndex;
        rebalancedLPs++;
        
        emit Rebalanced(lp, settlementPrice, amount, isDeposit, cycleIndex);
        
        // If all LPs have rebalanced, start next cycle
        if (rebalancedLPs == cycleLPCount) {
            uint256 poolHaltPercent = 0;
            uint256 availableLiquidity = poolStrategy.calculateCycleAvailableLiquidity(address(assetPool));
            if (poolHaltAmount > 0 && totalLiquidity > 0) {
                // Calculate the halt percentage based on the pool halt amount
                poolHaltPercent = Math.mulDiv(poolHaltAmount, BPS, totalLiquidity);
            }
            // if poolHaltPercent is greater than the halt liquidity percent
            if (poolHaltPercent > poolStrategy.haltLiquidityPercent() && poolHaltAmount > availableLiquidity) {
                _startNewCycle(CycleState.POOL_HALTED);
            } else {
                _startNewCycle(CycleState.POOL_ACTIVE);
            }
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
        if (!poolLiquidityManager.isLPActive(lp)) revert NotLP();

        uint256 lpCollateral = poolLiquidityManager.getLPCollateral(lp);
        bool isDeposit = false;

        if (lpCollateral > 0) {
            // Use LP's balance collateral to settle as much as possible
            poolLiquidityManager.deductFromCollateral(lp, lpCollateral);
            cycleRebalanceAmount += int256(lpCollateral);
            isDeposit = true;
        }

        uint256 settlementPrice = calculateRebalancePriceForAmount(int256(lpCollateral));

        uint256 lpLiquidityCommitment = poolLiquidityManager.getLPLiquidityCommitment(lp);
        uint256 totalLiquidity = poolLiquidityManager.totalLPLiquidityCommited();

        if (totalLiquidity > 0) {
            // Calculate interest for the LP's liquidity commitment
            uint256 interestAmount = Math.mulDiv(cycleInterestAmount, settlementPrice, PRECISION);
            uint256 lpCycleInterest = Math.mulDiv(interestAmount, lpLiquidityCommitment, totalLiquidity);
            // Deduct interest from the pool and transfer it to the protocol as penalty
            if (lpCycleInterest > 0) {
                assetPool.deductInterest(lp, lpCycleInterest, true);
            }
        }
        
        // Resolve any pending requests for the LP
        poolLiquidityManager.resolveRequest(lp);
        lpLiquidityCommitment = poolLiquidityManager.getLPLiquidityCommitment(lp);

        // calculate the weighted sum of the rebalance price
        cycleWeightedSum += Math.mulDiv(settlementPrice, lpLiquidityCommitment * reserveToAssetDecimalFactor, PRECISION);
        lastRebalancedCycle[lp] = cycleIndex;
        rebalancedLPs++;
        
        emit Rebalanced(lp, settlementPrice, lpCollateral, isDeposit, cycleIndex);
        
        // If all LPs have rebalanced, start next cycle
        if (rebalancedLPs == cycleLPCount) {
            _startNewCycle(CycleState.POOL_HALTED);
        }
    }

    /**
     * @notice Resolves price deviation by executing a token split or validating the price
     * @param isTokenSplit True if the price shock was due to a stock split
     * @param splitRatio Only used if isTokenSplit is true - numerator of split ratio (e.g., 2 for 2:1 split)
     * @param splitDenominator Only used if isTokenSplit is true - denominator of split ratio (e.g., 1 for 2:1 split)
     */
    function resolvePriceDeviation(
        bool isTokenSplit,
        uint256 splitRatio,
        uint256 splitDenominator
    ) external onlyOwner {
        if (cycleState != CycleState.POOL_REBALANCING_OFFCHAIN) revert InvalidCycleState();
        // Token split is disabled in v1
        isTokenSplit = false;
        
        if (isTokenSplit) {
            if (!assetOracle.verifySplit(splitRatio, splitDenominator)) revert InvalidSplit();
            // Increment the pool split index
            poolSplitIndex++;
            // Update the split multiplier for the new split
            splitMultiplier[poolSplitIndex] = Math.mulDiv(splitMultiplier[poolSplitIndex - 1], splitRatio, splitDenominator);
            // Execute token split
            _executeTokenSplit(splitRatio, splitDenominator);
        } 
        isPriceDeviationValid = true;
        emit isPriceDeviationValidUpdated(isPriceDeviationValid);
    }


    // --------------------------------------------------------------------------------
    //                          INTEREST CALCULATION LOGIC
    // --------------------------------------------------------------------------------

    /**
     * @notice Accrues interest based on the current rate, time elapsed, and cycle/rebalance periods
     * @dev Calculates cycleInterestAmount
     */
    function _accrueInterest() internal {
        uint256 currentTimestamp = block.timestamp;
        if (currentTimestamp <= lastInterestAccrualTimestamp) {
            return;
        }
        
        // Convert BPS interest rate (10000 = 100%) to a rate with precision
        uint256 currentRate = poolStrategy.calculatePoolInterestRate(address(assetPool));
        uint256 rateWithPrecision = Math.mulDiv(currentRate, PRECISION, BPS);
        
        // Calculate time elapsed since last accrual in seconds
        uint256 timeElapsed = currentTimestamp - lastInterestAccrualTimestamp;
        
        // Calculate interest for the elapsed time
        // Formula: interest = rate * timeElapsed / secondsPerYear
        uint256 interest = Math.mulDiv(rateWithPrecision, timeElapsed, SECONDS_PER_YEAR);
        
        // Calculate the interest amount in terms of asset
        cycleInterestAmount += _convertAssetToReserve(assetToken.totalSupply(), interest);
        
        // Update last accrual timestamp
        lastInterestAccrualTimestamp = currentTimestamp;
        
        emit InterestAccrued(interest, currentTimestamp);
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
        if (rebalancePrice < Math.min(cyclePriceOpen, cyclePriceClose) ||
            rebalancePrice > Math.max(cyclePriceOpen, cyclePriceClose)) {
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
        uint256 lpCommitment = poolLiquidityManager.totalLPLiquidityCommited();
        uint256 price = lpCommitment > 0 ? Math.mulDiv(cycleWeightedSum, PRECISION, lpCommitment * reserveToAssetDecimalFactor) : 0;
        cycleRebalancePrice[cycleIndex] = price;
        // Calculate the cumulative interest index
        if (assetToken.totalSupply() > 0) {
            cumulativeInterestIndex[cycleIndex] += Math.mulDiv(cycleInterestAmount * reserveToAssetDecimalFactor, price, assetToken.totalSupply());
        }

        assetPool.updateCycleData(price, cycleRebalanceAmount);

        cycleIndex++;
        cycleState = newCycleState;
        rebalancedLPs = 0;
        cycleWeightedSum = 0;
        lastCycleActionDateTime = block.timestamp;
        cycleRebalanceAmount = 0;
        cycleInterestAmount = 0;
        cyclePriceOpen = 0;
        cyclePriceClose = 0;
        poolHaltAmount = 0;
        cumulativeInterestIndex[cycleIndex] = cumulativeInterestIndex[cycleIndex - 1];
        
        emit CycleStarted(cycleIndex, block.timestamp);
    }

    /**
     * @notice Updates the price deviation validity flag
     */
    function _updateIsPriceDeviationValid() internal {
        isPriceDeviationValid  = !isPriceDeviationValid;
        emit isPriceDeviationValidUpdated(isPriceDeviationValid);
    }


    /**
     * @notice Executes a token split for the asset token
     * @param splitRatio Numerator of the split ratio (e.g., 2 for a 2:1 split)
     * @param splitDenominator Denominator of the split ratio (e.g., 1 for a 2:1 split)
     * @dev Only callable by the owner or the pool cycle manager
     */
    function _executeTokenSplit(
        uint256 splitRatio,
        uint256 splitDenominator
    ) internal {            
        // Apply the token split to the xToken
        assetToken.applySplit(splitRatio, splitDenominator);
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