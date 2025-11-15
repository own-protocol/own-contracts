// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "../../interfaces/IPoolStrategy.sol";
import "../../interfaces/IPoolLiquidityManager.sol";
import "../../interfaces/IAssetPoolWithPoolStorage.sol";
import "../../interfaces/IXToken.sol";
import "../../interfaces/IAssetOracle.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title DefaultPoolStrategy
 * @notice Default implementation of pool strategy with standard interest, collateral & liquidity models
 */
contract DefaultPoolStrategy is IPoolStrategy, Ownable {
    // --------------------------------------------------------------------------------
    //                               STATE VARIABLES
    // --------------------------------------------------------------------------------

    // pool cycle parameters
    uint256 public rebalanceLength;             // length of onchain rebalancing period (default: 3 hours)
    uint256 public oracleUpdateThreshold;       // Threshold for oracle update (default: 15 minutes)

    // Asset interest rate parameters
    uint256 public baseInterestRate;            // Base interest rate (e.g., 9%)
    uint256 public interestRate1;               // Tier 1 interest rate (e.g., 18%)
    uint256 public maxInterestRate;             // Maximum interest rate (e.g., 72%)
    uint256 public utilizationTier1;            // First utilization tier (e.g., 65%)
    uint256 public utilizationTier2;            // Second utilization tier (e.g., 85%)
    
    // Fee parameters
    uint256 public protocolFee;                 // Fee on interest (e.g., 10.0%)
    address public feeRecipient;                // Address to receive fees
    
    // User collateral parameters 
    uint256 public userHealthyCollateralRatio;  // Healthy ratio (e.g., 20%)
    uint256 public userLiquidationThreshold;    // Liquidation threshold (e.g., 12.5%)
    
    // LP liquidity parameters 
    uint256 public lpHealthyCollateralRatio;    // Healthy ratio (e.g., 30%)
    uint256 public lpLiquidationThreshold;      // Liquidation threshold (e.g., 20%)
    uint256 public lpLiquidationReward;         // Liquidation reward (e.g., 0.5%)
    uint256 public lpMinCommitment;             // Minimum liquidity commitment for LPs (e.g., 100 tokens)

    // Pool halt parameters
    uint256 public haltThreshold;               // Threshold for halting the pool (default: 5 days)
    uint256 public haltLiquidityPercent;        // Percentage of liquidity commitment to halt (default: 70%)
    uint256 public haltFeePercent;              // Percentage of fees to halt (default: 5%)
    uint256 public haltRequestThreshold;        // Threshold for halting requests (default: 20 cycles)

    // Yield generating reserve
    bool public isYieldBearing;                 // Flag to indicate if the reserve is yield generating
    
    // Constants
    uint256 private constant BPS = 100_00;      // 100% in basis points (10000)
    uint256 private constant PRECISION = 1e18;  // Precision for calculations
    
    // --------------------------------------------------------------------------------
    //                                  CONSTRUCTOR
    // --------------------------------------------------------------------------------

    /**
     * @notice Initializes the DefaultPoolStrategy contract with default owner
     * @dev Parameters are set separately via setter functions
     */
    constructor() Ownable(msg.sender) {
    }
    
    // --------------------------------------------------------------------------------
    //                                CONFIGURATION FUNCTIONS
    // --------------------------------------------------------------------------------


    /**
     * @notice Sets the cycle parameters
     * @param _rebalanceLength Length of rebalancing period in seconds
     * @param _oracleUpdateThreshold Threshold for oracle update
     */
    function setCycleParams(
        uint256 _rebalanceLength,
        uint256 _oracleUpdateThreshold
    ) external onlyOwner {
        rebalanceLength = _rebalanceLength;
        oracleUpdateThreshold = _oracleUpdateThreshold;

        emit CycleParamsUpdated(_rebalanceLength, _oracleUpdateThreshold);
    }
    
    /**
     * @notice Sets the interest rate parameters
     * @param baseRate Base interest rate (scaled by 10000)
     * @param rate1 Tier 1 interest rate (scaled by 10000)
     * @param maxRate Maximum interest rate (scaled by 10000)
     * @param utilTier1 First utilization tier (scaled by 10000)
     * @param utilTier2 Second utilization tier (scaled by 10000)
     */
    function setInterestRateParams(
        uint256 baseRate,
        uint256 rate1,
        uint256 maxRate,
        uint256 utilTier1,
        uint256 utilTier2
    ) external onlyOwner {
        // Parameter validation
        require(baseRate <= rate1, "Base rate must be <= Interest rate 1");
        require(rate1 <= maxRate, "Interest rate 1 must be <= max rate");
        require(maxRate <= BPS, "Max rate cannot exceed 100%");
        require(utilTier1 <= utilTier2, "Tier1 must be <= Tier2");
        require(utilTier2 <= BPS, "Tier2 must be <= BPS");
        
        baseInterestRate = baseRate;
        interestRate1 = rate1;
        maxInterestRate = maxRate;
        utilizationTier1 = utilTier1;
        utilizationTier2 = utilTier2;
        
        emit InterestRateParamsUpdated(
            baseRate,
            interestRate1,
            maxRate,
            utilTier1,
            utilTier2
        );
    }
    
    /**
     * @notice Sets the fee parameters
     * @param _protocolFee fee on interest (scaled by 10000)
     * @param _feeRecipient Address to receive fees
     */
    function setProtocolFeeParams(
        uint256 _protocolFee,
        address _feeRecipient
    ) external onlyOwner {
        require(
            _protocolFee <= BPS, 
            "Fees cannot exceed 100%"
        );
        require(_feeRecipient != address(0), "Invalid fee recipient");
        
        protocolFee = _protocolFee;
        feeRecipient = _feeRecipient;
        
        emit FeeParamsUpdated(
            protocolFee,
            _feeRecipient
        );
    }
    
    /**
     * @notice Sets the user collateral parameters
     * @param healthyRatio Healthy collateral ratio (scaled by 10000)
     * @param liquidationRatio Liquidation threshold (scaled by 10000)
     */
    function setUserCollateralParams(
        uint256 healthyRatio,
        uint256 liquidationRatio
    ) external onlyOwner {
        require(liquidationRatio <= healthyRatio, "Liquidation ratio must be <= healthy ratio");
        
        userHealthyCollateralRatio = healthyRatio;
        userLiquidationThreshold = liquidationRatio;
        
        emit UserCollateralParamsUpdated(
            healthyRatio,
            liquidationRatio
        );
    }
    
    /**
     * @notice Sets the LP collateral parameters
     * @param healthyRatio Healthy collateral ratio (scaled by 10000)
     * @param liquidationThreshold Warning threshold (scaled by 10000)
     * @param liquidationReward Liquidation reward (scaled by 10000)
     * @param minCommitment Minimum liquidity commitment for LPs (in reserve tokens)
     */
    function setLPLiquidityParams(
        uint256 healthyRatio,
        uint256 liquidationThreshold,
        uint256 liquidationReward,
        uint256 minCommitment
    ) external onlyOwner {
        require(liquidationThreshold <= healthyRatio, "liquidation threshold must be <= healthy ratio");
        require(liquidationReward <= BPS, "Reward cannot exceed 100%");
        
        lpHealthyCollateralRatio = healthyRatio;
        lpLiquidationThreshold = liquidationThreshold;
        lpLiquidationReward = liquidationReward;
        lpMinCommitment = minCommitment;
        
        emit LPLiquidityParamsUpdated(
            healthyRatio,
            liquidationThreshold,
            liquidationReward,
            minCommitment
        );
    }

    /**
     * @notice Sets the halt parameters
     * @param _haltThreshold Threshold for halting the pool (in seconds)
     * @param _haltLiquidityPercent Percentage of liquidity commitment to halt (scaled by 10000)
     * @param _haltFeePercent Percentage of fees to halt (scaled by 10000)
     * @param _haltRequestThreshold Threshold for halting requests (in cycles)
     */
    function setHaltParams(
        uint256 _haltThreshold,
        uint256 _haltLiquidityPercent,
        uint256 _haltFeePercent,
        uint256 _haltRequestThreshold
    ) external onlyOwner {
        require(_haltThreshold > 0, "Halt threshold must be > 0");
        require(_haltLiquidityPercent <= BPS, "Halt liquidity percent cannot exceed 100%");
        require(_haltFeePercent <= BPS, "Halt fee percent cannot exceed 100%");
        require(_haltRequestThreshold > 0, "Halt request threshold must be > 0");

        haltThreshold = _haltThreshold;
        haltLiquidityPercent = _haltLiquidityPercent;
        haltFeePercent = _haltFeePercent;
        haltRequestThreshold = _haltRequestThreshold;

        emit HaltParamsUpdated(
            _haltThreshold,
            _haltLiquidityPercent,
            _haltFeePercent,
            _haltRequestThreshold
        );
    }

    /**
     * @notice Sets the yield generating reserve flag
     */
    function setIsYieldBearing() external onlyOwner {
        isYieldBearing = !isYieldBearing;
        
        emit IsYieldBearingUpdated(
            isYieldBearing
        );
    }

    // --------------------------------------------------------------------------------
    //                             CYCLE FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Returns the cycle parameters
     * @return rebalancePeriod Length of rebalancing period in seconds
     * @return oracleThreshold Threshold for oracle update
     */
    function getCycleParams() external view returns (
        uint256 rebalancePeriod,
        uint256 oracleThreshold
    ) {
        return (rebalanceLength, oracleUpdateThreshold);
    }
    
    // --------------------------------------------------------------------------------
    //                             ASSET INTEREST FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Returns all interest rate parameters
     * @return baseRate The base interest rate (scaled by 10000)
     * @return rate1 The tier 1 interest rate (scaled by 10000)
     * @return maxRate The maximum interest rate (scaled by 10000)
     * @return utilTier1 The first utilization tier (scaled by 10000)
     * @return utilTier2 The second utilization tier (scaled by 10000)
     */
    function getInterestRateParams() external view returns (
        uint256 baseRate,
        uint256 rate1,
        uint256 maxRate,
        uint256 utilTier1,
        uint256 utilTier2
    ) {
        return (
            baseInterestRate,
            interestRate1,
            maxInterestRate,
            utilizationTier1,
            utilizationTier2
        );
    }

    /**
     * @notice Calculate interest rate based on utilization
     * @param utilization Current utilization rate (scaled by 10000)
     * @return rate Current interest rate (scaled by 10000)
     */
    function calculateInterestRate(uint256 utilization) public view returns (uint256 rate) {
        if (utilization <= utilizationTier1) {
            // Base rate when utilization <= Tier1
            return baseInterestRate;
        } else if (utilization <= utilizationTier2) {
            // Linear increase from base rate to interest rate 1
            uint256 utilizationDelta = utilization - utilizationTier1;
            uint256 optimalDelta = utilizationTier2 - utilizationTier1;
            
            uint256 additionalRate = ((interestRate1 - baseInterestRate) * utilizationDelta) / optimalDelta;
            return baseInterestRate + additionalRate;
        } else if (utilization <= BPS) {
            // Linear increase from interest rate 1 to max rate
            uint256 utilizationDelta = utilization - utilizationTier2;
            uint256 optimalDelta = BPS - utilizationTier2;
            
            uint256 additionalRate = ((maxInterestRate - interestRate1) * utilizationDelta) / optimalDelta;
            return interestRate1 + additionalRate;
        } else {
            return maxInterestRate; // Max rate
        }
    }
    
    // --------------------------------------------------------------------------------
    //                             COLLATERAL & LIQUIDITY FUNCTIONS
    // --------------------------------------------------------------------------------
    
    /**
     * @notice Returns user collateral parameters
     */
    function getUserCollateralParams() external view returns (
        uint256 healthyRatio,
        uint256 liquidationThreshold
    ) {
        return (
            userHealthyCollateralRatio,
            userLiquidationThreshold
        );
    }
    
    /**
     * @notice Returns LP collateral parameters
     */
    function getLPLiquidityParams() external view returns (
        uint256 healthyRatio,
        uint256 liquidationThreshold,
        uint256 liquidationReward
    ) {
        return (
            lpHealthyCollateralRatio,
            lpLiquidationThreshold,
            lpLiquidationReward
        );
    }
    
    /**
     * @notice Calculates required user collateral
     * @param assetPool Address of the asset pool
     * @param user Address of the user
     */
    function calculateUserRequiredCollateral(address assetPool, address user) external view returns (uint256) {
        IAssetPoolWithPoolStorage pool = IAssetPoolWithPoolStorage(assetPool);
        IPoolCycleManager cycleManager = pool.poolCycleManager();

        uint256 reserveToAssetDecimalFactor = pool.reserveToAssetDecimalFactor();
        // Get the previous cycle's rebalance price
        uint256 prevCycle = cycleManager.cycleIndex() - 1;
        uint256 rebalancePrice = cycleManager.cycleRebalancePrice(prevCycle);
        (uint256 assetAmount, uint256 depositAmount, ) = pool.userPositions(user);
        if(assetAmount == 0) {
            return Math.mulDiv(depositAmount, userHealthyCollateralRatio, BPS);
        }
        assetAmount = calculatePostSplitAmount(assetPool, user, assetAmount);
        uint256 assetValue = Math.mulDiv(assetAmount, rebalancePrice, PRECISION * reserveToAssetDecimalFactor);
        uint256 interestDebt = pool.getInterestDebt(user, prevCycle);
        uint256 requiredCollateral = Math.mulDiv(assetValue, userHealthyCollateralRatio, BPS, Math.Rounding.Ceil);
        return requiredCollateral + interestDebt;
    }
    
    /**
     * @notice Calculates required LP collateral
     * @param liquidityManager Address of the pool liquidity manager
     * @param lp Address of the LP
     */
    function calculateLPRequiredCollateral(address liquidityManager, address lp) external view returns (uint256) {
        
        IPoolLiquidityManager manager = IPoolLiquidityManager(liquidityManager);
        IPoolLiquidityManager.LPPosition memory position = manager.getLPPosition(lp);
        uint256 lpCommitment = position.liquidityCommitment;
        
        IPoolLiquidityManager.LPRequest memory request = manager.getLPRequest(lp);
        if (request.requestType == IPoolLiquidityManager.RequestType.ADD_LIQUIDITY) {
            lpCommitment += request.requestAmount;
        }
        uint256 healthyCollateral = Math.mulDiv(lpCommitment, lpHealthyCollateralRatio, BPS, Math.Rounding.Ceil);
        uint256 reserveYieldAmount = 0;
        if (isYieldBearing) {
            uint256 reserveYieldIndex = manager.reserveYieldIndex();
            uint256 lpReserveYieldIndex = manager.lpReserveYieldIndex(lp);
            reserveYieldAmount = Math.mulDiv(
                position.collateralAmount + position.interestAccrued,
                reserveYieldIndex - lpReserveYieldIndex,
                PRECISION
            );
            reserveYieldAmount = Math.mulDiv((BPS - protocolFee), reserveYieldAmount, BPS);
        }
        healthyCollateral = _safeSubtract(healthyCollateral, reserveYieldAmount);
        return healthyCollateral;
    }

    /**
     * @notice Check collateral health status of a user
     * @param user User address
     * @return health 3 = Healthy, 2 = Warning, 1 = Liquidatable
     */
    function getUserCollateralHealth(address assetPool, address user) external view returns (uint8 health) {
        IAssetPoolWithPoolStorage pool = IAssetPoolWithPoolStorage(assetPool);
        IPoolCycleManager cycleManager = pool.poolCycleManager();

        (uint256 assetAmount , , uint256 collateralAmount) = pool.userPositions(user);

        if (isYieldBearing) {
            uint256 reserveYieldIndex = pool.reserveYieldIndex(cycleManager.cycleIndex());
            uint256 userReserveYieldIndex = pool.userReserveYieldIndex(user);
            uint256 reserveYieldAmount = Math.mulDiv(
                assetAmount,
                reserveYieldIndex - userReserveYieldIndex,
                PRECISION
            );
            collateralAmount += Math.mulDiv((BPS - protocolFee), reserveYieldAmount, BPS);
        }

        if (assetAmount == 0) {
            return 3; // Healthy - no asset balance means no risk
        }
        assetAmount = calculatePostSplitAmount(assetPool, user, assetAmount);

        uint256 reserveToAssetDecimalFactor = pool.reserveToAssetDecimalFactor();
        // Get the previous cycle's rebalance price
        uint256 prevCycle = cycleManager.cycleIndex() - 1;
        uint256 rebalancePrice = cycleManager.cycleRebalancePrice(prevCycle);
        uint256 interestDebt = pool.getInterestDebt(user, prevCycle);
        uint256 assetValue = Math.mulDiv(assetAmount, rebalancePrice, PRECISION * reserveToAssetDecimalFactor);
        uint256 userCollateralBalance = _safeSubtract(collateralAmount, interestDebt);

        uint256 healthyCollateral = Math.mulDiv(assetValue, userHealthyCollateralRatio, BPS, Math.Rounding.Ceil);
        uint256 reqCollateral = Math.mulDiv(assetValue, userLiquidationThreshold, BPS, Math.Rounding.Ceil);
        
        if (userCollateralBalance >= healthyCollateral) {
            return 3; // Healthy
        } else if (userCollateralBalance > reqCollateral) {
            return 2; // Warning
        } else {
            return 1; // Liquidatable
        }
    }

    /**
     * @notice Check liquidity health status of an LP
     * @param lp Address of the LP
     * @return health 3 = Healthy, 2 = Warning, 1 = Liquidatable
     */
    function getLPLiquidityHealth(address liquidityManager, address lp) external view returns (uint8 health) {
        IPoolLiquidityManager manager = IPoolLiquidityManager(liquidityManager);
        
        IPoolLiquidityManager.LPPosition memory position = manager.getLPPosition(lp);
        uint256 lpCollateral = position.collateralAmount;
        uint256 lpCommitment = position.liquidityCommitment;
        
        if (isYieldBearing) {
            uint256 reserveYieldIndex = manager.reserveYieldIndex();
            uint256 lpReserveYieldIndex = manager.lpReserveYieldIndex(lp);
            uint256 reserveYieldAmount = Math.mulDiv(
                lpCollateral + position.interestAccrued,
                reserveYieldIndex - lpReserveYieldIndex,
                PRECISION
            );
            lpCollateral += Math.mulDiv((BPS - protocolFee), reserveYieldAmount, BPS);
        }

        uint256 healthyLiquidity = Math.mulDiv(lpCommitment, lpHealthyCollateralRatio, BPS);
        uint256 reqLiquidity = Math.mulDiv(lpCommitment, lpLiquidationThreshold, BPS);
        
        if (lpCollateral >= healthyLiquidity) {
            return 3; // Healthy
        } else if (lpCollateral >= reqLiquidity) {
            return 2; // Warning
        } else {
            return 1; // Liquidatable
        }
    }

    // --------------------------------------------------------------------------------
    //                             YIELD FUNCTIONS
    // --------------------------------------------------------------------------------

    function calculateYieldAccrued(
        uint256 prevAmount, 
        uint256 currentAmount, 
        uint256 depositAmount
    ) external pure returns (uint256) {  
        if (depositAmount == 0 || currentAmount < prevAmount) {
            return 0; // No yield if no previous amount
        }      
        // Calculate yield
        uint256 yield = Math.mulDiv(currentAmount - prevAmount, PRECISION, depositAmount);
        return yield;
    }

    // --------------------------------------------------------------------------------
    //                             POOL FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Calculate utilised liquidity (including cycle changes)
     * @param assetPool Address of the asset pool
     * @return cycleUtilisedLiquidity Total utilised liquidity
     */
    function calculateCycleUtilisedLiquidity(address assetPool) public view returns (uint256 cycleUtilisedLiquidity) {
        IAssetPoolWithPoolStorage pool = IAssetPoolWithPoolStorage(assetPool);
        IPoolCycleManager cycleManager = pool.poolCycleManager();
        
        uint256 prevCycle = cycleManager.cycleIndex() - 1;
        uint256 price = cycleManager.cycleRebalancePrice(prevCycle); 
        uint256 utilisedLiquidity = pool.getUtilisedLiquidity();
        uint256 cycleTotalDeposits = pool.cycleTotalDeposits();
        uint256 cycleTotalRedemptions = pool.cycleTotalRedemptions();
        uint256 cycleRedemptionsInReserveToken = 0;
        
        // Calculate redemptions in reserve token
        if (cycleTotalRedemptions > 0) {
            uint256 reserveToAssetDecimalFactor = pool.reserveToAssetDecimalFactor();
            cycleRedemptionsInReserveToken = Math.mulDiv(cycleTotalRedemptions, price, PRECISION * reserveToAssetDecimalFactor);
        }

        uint256 nettChange = 0;
        
        if (cycleTotalDeposits > cycleRedemptionsInReserveToken) {
            nettChange = cycleTotalDeposits - cycleRedemptionsInReserveToken;
            cycleUtilisedLiquidity = utilisedLiquidity + nettChange;
        } else if (cycleTotalDeposits < cycleRedemptionsInReserveToken) {
            nettChange = cycleRedemptionsInReserveToken - cycleTotalDeposits;
            cycleUtilisedLiquidity = utilisedLiquidity > nettChange ? utilisedLiquidity - nettChange : 0;
        } else {
            cycleUtilisedLiquidity = utilisedLiquidity;
        }
        
        return cycleUtilisedLiquidity;
    }

    /**
     * @notice Calculate current interest rate based on pool utilization
     * @return rate Current interest rate (scaled by 10000)
     */
    function calculatePoolInterestRate(address assetPool) public view returns (uint256 rate) {
        uint256 utilization = calculatePoolUtilizationRatio(assetPool);
        return calculateInterestRate(utilization);
    }

     /**
     * @notice Calculate interest rate based on pool utilization (including cycle changes)
     * @dev This function gives the expected interest rate for the next cycle
     * @dev It takes into account the new deposits, redemptions & liquidity changes in the cycle
     * @return rate interest rate (scaled by 10000)
     */
    function calculateCycleInterestRate(address assetPool) public view returns (uint256 rate) {
        uint256 utilization = calculateCyclePoolUtilizationRatio(assetPool);
        return calculateInterestRate(utilization);
    }

    /**
     * @notice Calculate pool utilization ratio
     * @return utilization Pool utilization as a percentage (scaled by 10000)
     */
    function calculatePoolUtilizationRatio(address assetPool) public view returns (uint256 utilization) {
        IAssetPoolWithPoolStorage pool = IAssetPoolWithPoolStorage(assetPool);
        IPoolLiquidityManager poolLiquidityManager = pool.poolLiquidityManager();

        uint256 totalLiquidity = poolLiquidityManager.totalLPLiquidityCommited();
        if (totalLiquidity == 0) return 0;
        uint256 utilisedLiquidity = pool.getUtilisedLiquidity();
        
        return Math.min((utilisedLiquidity * BPS) / totalLiquidity, BPS);
    }

    /**
     * @notice Calculate pool utilization ratio (including cycle changes)
     * @dev This function gives the expected utilization for the next cycle
     * @dev It takes into account the new deposits, redemptions & liquidity changes in the cycle
     * @return utilization Pool utilization as a percentage (scaled by 10000)
     */    
    function calculateCyclePoolUtilizationRatio(address assetPool) public view returns (uint256 utilization) {
        IAssetPoolWithPoolStorage pool = IAssetPoolWithPoolStorage(assetPool);
        IPoolLiquidityManager poolLiquidityManager = pool.poolLiquidityManager();

        uint256 cycleTotalLiquidity = poolLiquidityManager.getCycleTotalLiquidityCommited();
        if (cycleTotalLiquidity == 0) return 0;
        uint256 cycleUtilisedLiquidity = calculateCycleUtilisedLiquidity(assetPool);
        
        return Math.min((cycleUtilisedLiquidity * BPS) / cycleTotalLiquidity, BPS);
    }

    /**
     * @notice Calculate available liquidity in the pool
     * @return availableLiquidity Available liquidity in reserve tokens
     */
    function calculateAvailableLiquidity(address assetPool) public view returns (uint256 availableLiquidity) {
        IAssetPoolWithPoolStorage pool = IAssetPoolWithPoolStorage(assetPool);
        IPoolLiquidityManager poolLiquidityManager = pool.poolLiquidityManager();

        uint256 totalLiquidity = poolLiquidityManager.totalLPLiquidityCommited();
        uint256 utilisedLiquidity = pool.getUtilisedLiquidity();
        
        return totalLiquidity > utilisedLiquidity ? totalLiquidity - utilisedLiquidity : 0;
    }

    /**
     * @notice Calculate available liquidity in the pool (including cycle changes)
     * @dev This function gives the expected available liquidity for the next cycle
     * @dev It takes into account the new deposits, redemptions & liquidity changes in the cycle
     * @return availableLiquidity Available liquidity in reserve tokens
     */
    function calculateCycleAvailableLiquidity(address assetPool) public view returns (uint256 availableLiquidity) {
        IAssetPoolWithPoolStorage pool = IAssetPoolWithPoolStorage(assetPool);
        IPoolLiquidityManager poolLiquidityManager = pool.poolLiquidityManager();

        uint256 cycleTotalLiquidity = poolLiquidityManager.getCycleTotalLiquidityCommited();
        uint256 cycleUtilisedLiquidity = calculateCycleUtilisedLiquidity(assetPool);
        
        return cycleTotalLiquidity > cycleUtilisedLiquidity ? cycleTotalLiquidity - cycleUtilisedLiquidity : 0;
    }

    /**
     * @notice Calculate post-split amount for a user
     * @dev This function calculates the user's asset amount after accounting for any token splits
     * @param assetPool Address of the asset pool
     * @param user Address of the user
     * @param amount User's asset amount before split adjustments
     * @return postSplitAmount User's asset amount after split adjustments
     */
    function calculatePostSplitAmount(address assetPool, address user, uint256 amount) public view returns (uint256 postSplitAmount) {
        IAssetPoolWithPoolStorage pool = IAssetPoolWithPoolStorage(assetPool);
        IPoolCycleManager cycleManager = pool.poolCycleManager();
        
        uint256 splitIndex = cycleManager.poolSplitIndex();
        uint256 userSplitIndex = pool.userSplitIndex(user);
        if (userSplitIndex == splitIndex) {
            // No split adjustment needed if user is at the same split index
            return amount;
        }          
        // Calculate the post-split amount
        postSplitAmount = Math.mulDiv(amount, cycleManager.splitMultiplier(splitIndex), cycleManager.splitMultiplier(userSplitIndex));

        return postSplitAmount;
    }

    /**
     * @notice Safely subtracts an amount from a value, ensuring it doesn't go negative
     * @dev This function is used to prevent underflows
     * @param from The value to subtract from
     * @param amount The amount to subtract
     * @return The result of the subtraction, or 0 if it would go negative
     */
    function _safeSubtract(uint256 from, uint256 amount) internal pure returns (uint256) {
        return amount > from ? 0 : from - amount;
    }
}