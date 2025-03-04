// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/contracts/utils/Pausable.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IAssetPool} from "../interfaces/IAssetPool.sol";
import {IXToken} from "../interfaces/IXToken.sol";
import {IPoolLiquidityManager} from "../interfaces/IPoolLiquidityManager.sol";
import {IAssetOracle} from "../interfaces/IAssetOracle.sol";
import {IPoolCycleManager} from "../interfaces/IPoolCycleManager.sol";
import {IInterestRateStrategy} from "../interfaces/IInterestRateStrategy.sol";
import {PoolStorage} from"./PoolStorage.sol";
import {xToken} from "./xToken.sol";

/**
 * @title AssetPool
 * @notice Manages user positions, collateral, and interest payments in the protocol
 * @dev Handles the lifecycle of user positions and calculates interest based on pool utilization
 */
contract AssetPool is IAssetPool, PoolStorage, Ownable, Pausable, ReentrancyGuard {
    // --------------------------------------------------------------------------------
    //                               STATE VARIABLES
    // --------------------------------------------------------------------------------

    /**
     * @notice Interest rate strategy contract
     */
    IInterestRateStrategy public interestRateStrategy;

    /**
     * @notice Minimum collateral ratio required (scaled by 10000, default: 120%)
     */
    uint256 public minCollateralRatio = 120_00;

    /**
     * @notice Liquidation threshold ratio (scaled by 10000, default: 110%)
     */
    uint256 public liquidationThreshold = 110_00;

    /**
     * @notice Liquidation reward percentage (scaled by 10000, default: 5%)
     */
    uint256 public liquidationReward = 5_00;

    /**
     * @notice Total interest collected in the current cycle
     */
    uint256 public currentCycleInterest;

    /**
     * @notice Total user deposit requests for the current cycle
     */
    uint256 public _cycleTotalDepositRequests;

    /**
     * @notice Total user redemption requests for the current cycle
     */
    uint256 public _cycleTotalRedemptionRequests;

    /**
     * @notice Mapping of user addresses to their positions
     */
    mapping(address => Position) public positions;

    /**
     * @notice Mapping of user addresses to their pending requests
     */
    mapping(address => UserRequest) public userRequests;

    /**
     * @dev Constructor for the implementation contract
     */
    constructor() Ownable(msg.sender) {
        // Disable implementation initializers
        _disableInitializers();
    }

    // --------------------------------------------------------------------------------
    //                                  MODIFIERS
    // --------------------------------------------------------------------------------

    /**
     * @dev Ensures the caller is the pool cycle manager
     */
    modifier onlyPoolCycleManager() {
        if (msg.sender != address(poolCycleManager)) revert NotPoolCycleManager();
        _;
    }

    /**
     * @dev Ensures the cycle state is active
     */
    modifier onlyActiveCycle() {
        if (poolCycleManager.cycleState() != IPoolCycleManager.CycleState.ACTIVE) revert("Cycle not active");
        _;
    }

    // --------------------------------------------------------------------------------
    //                                 INITIALIZER
    // --------------------------------------------------------------------------------

    /**
     * @notice Initializes the AssetPool contract
     * @param _reserveToken Address of the reserve token
     * @param _assetTokenSymbol Symbol of the asset token
     * @param _assetOracle Address of the asset oracle
     * @param _poolCycleManager Address of the pool cycle manager contract
     * @param _poolLiquidityManager Address of the pool liquidity manager contract
     * @param _owner Address of the contract owner
     */
    function initialize(
        address _reserveToken,
        string memory _assetTokenSymbol,
        address _assetOracle,
        address _poolCycleManager,
        address _poolLiquidityManager,
        address _interestRateStrategy,
        address _owner
    ) external initializer {
        if (_reserveToken == address(0) || _assetOracle == address(0) || 
            _poolLiquidityManager == address(0) || _poolCycleManager == address(0)) 
            revert ZeroAddress();

        poolCycleManager =IPoolCycleManager(_poolCycleManager);
        reserveToken = IERC20Metadata(_reserveToken);
        assetToken = new xToken(_assetTokenSymbol, _assetTokenSymbol);
        poolLiquidityManager = IPoolLiquidityManager(_poolLiquidityManager);
        assetOracle = IAssetOracle(_assetOracle);
        interestRateStrategy = IInterestRateStrategy(_interestRateStrategy);

        _initializeDecimalFactor(address(reserveToken), address(assetToken));

        _transferOwnership(_owner);
    }

    // --------------------------------------------------------------------------------
    //                           USER COLLATERAL FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Allows users to deposit collateral
     * @param amount Amount of collateral to deposit
     */
    function depositCollateral(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert InvalidAmount();

        Position storage position = positions[msg.sender];
        
        // Transfer collateral from user to this contract
        reserveToken.transferFrom(msg.sender, address(this), amount);
        
        // Update user's position
        position.collateralAmount += amount;
        
        emit CollateralDeposited(msg.sender, amount);
    }

    /**
     * @notice Allows users to withdraw excess collateral
     * @param amount Amount of collateral to withdraw
     */
    function withdrawCollateral(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert InvalidAmount();
        
        Position storage position = positions[msg.sender];
        if (position.collateralAmount < amount) revert InsufficientBalance();
        
        // Calculate required collateral
        uint256 requiredCollateral = calculateRequiredCollateral(msg.sender);
        uint256 excessCollateral = 0;
        
        if (position.collateralAmount > requiredCollateral) {
            excessCollateral = position.collateralAmount - requiredCollateral;
        }
        
        if (amount > excessCollateral) revert ExcessiveWithdrawal();
        
        // Update user's position
        position.collateralAmount -= amount;
        
        // Transfer collateral to user
        reserveToken.transfer(msg.sender, amount);
        
        emit CollateralWithdrawn(msg.sender, amount);
    }

    /**
     * @notice Liquidate an undercollateralized position
     * @param user Address of the user whose position to liquidate
     */
    function liquidatePosition(address user) external nonReentrant whenNotPaused {
        if (user == address(0) || user == msg.sender) revert InvalidAmount();
        
        Position storage position = positions[user];
        
        // Check if position is liquidatable
        (,, bool isLiquidatable) = userPosition(user);
        if (!isLiquidatable) revert PositionNotLiquidatable();
        
        // Calculate liquidation reward
        uint256 liquidationRewardAmount = (position.collateralAmount * liquidationReward) / BPS;
        uint256 remainingCollateral = position.collateralAmount - liquidationRewardAmount;
        
        // Clear the user's position
        position.collateralAmount = 0;
        
        // Transfer reward to liquidator
        reserveToken.transfer(msg.sender, liquidationRewardAmount);
        
        // Transfer remaining collateral back to user
        if (remainingCollateral > 0) {
            reserveToken.transfer(user, remainingCollateral);
        }
        
        emit PositionLiquidated(user, msg.sender, liquidationRewardAmount);
    }

    // --------------------------------------------------------------------------------
    //                           USER REQUEST FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Process a deposit request
     * @param amount Amount of reserve tokens to deposit
     */
    function depositRequest(uint256 amount) external nonReentrant whenNotPaused onlyActiveCycle {
        if (amount == 0) revert InvalidAmount();
        
        UserRequest storage request = userRequests[msg.sender];
        if (request.amount > 0) revert RequestPending();
        
        // Transfer tokens from user to poolCycleManager
        reserveToken.transferFrom(msg.sender, address(poolCycleManager), amount);
        
        // Update request state
        request.amount = amount;
        request.isDeposit = true;
        request.requestCycle = poolCycleManager.cycleIndex();
        _cycleTotalDepositRequests += amount;
        
        emit DepositRequested(msg.sender, amount, poolCycleManager.cycleIndex());
    }

    /**
     * @notice Process a redemption request
     * @param amount Amount of asset tokens to redeem
     */
    function redemptionRequest(uint256 amount) external nonReentrant whenNotPaused onlyActiveCycle {
        if (amount == 0) revert InvalidAmount();
        
        uint256 userBalance = assetToken.balanceOf(msg.sender);
        if (userBalance < amount) revert InsufficientBalance();
        
        UserRequest storage request = userRequests[msg.sender];
        if (request.amount > 0) revert RequestPending();
        
        // Transfer asset tokens from user to poolCycleManager
        assetToken.transferFrom(msg.sender, address(poolCycleManager), amount);
        
        // Update request state
        request.amount = amount;
        request.isDeposit = false;
        request.requestCycle = poolCycleManager.cycleIndex();
        _cycleTotalRedemptionRequests += amount;
        
        emit RedemptionRequested(msg.sender, amount, poolCycleManager.cycleIndex());
    }

    /**
     * @notice Cancel a pending request
     */
    function cancelRequest() external nonReentrant onlyActiveCycle {
        UserRequest storage request = userRequests[msg.sender];
        uint256 amount = request.amount;
        bool isDeposit = request.isDeposit;
        uint256 requestCycle = request.requestCycle;
        
        if (requestCycle != poolCycleManager.cycleIndex()) revert NothingToCancel();
        if (amount == 0) revert NothingToCancel();
        
        // Clear request
        delete userRequests[msg.sender];
        
        if (isDeposit) {
            _cycleTotalDepositRequests -= amount;
            // Return reserve tokens
            reserveToken.transferFrom(address(poolCycleManager), msg.sender, amount);
            emit DepositCancelled(msg.sender, amount, poolCycleManager.cycleIndex());
        } else {
            _cycleTotalRedemptionRequests -= amount;
            // Return asset tokens
            assetToken.transferFrom(address(poolCycleManager), msg.sender, amount);
            emit RedemptionCancelled(msg.sender, amount, poolCycleManager.cycleIndex());
        }
    }

    /**
     * @notice Claim processed request
     */
    function claimRequest() external nonReentrant whenNotPaused onlyActiveCycle {
        UserRequest storage request = userRequests[msg.sender];
        uint256 amount = request.amount;
        bool isDeposit = request.isDeposit;
        uint256 requestCycle = request.requestCycle;
        
        if (requestCycle >= poolCycleManager.cycleIndex()) revert NothingToClaim();
        if (amount == 0) revert NothingToClaim();
        
        // Get the rebalance price from the pool cycle manager
        uint256 rebalancePrice = poolCycleManager.cycleRebalancePrice(requestCycle);
        
        // Clear request
        delete userRequests[msg.sender];
        
        if (isDeposit) {
            // Mint case - convert reserve to asset using rebalance price
            uint256 assetAmount = Math.mulDiv(
                amount, 
                PRECISION * reserveToAssetDecimalFactor, 
                rebalancePrice
            );
            
            // Mint tokens
            assetToken.mint(msg.sender, assetAmount, amount);
            
            emit AssetClaimed(msg.sender, assetAmount, requestCycle);
        } else {
            // Withdraw case - convert asset to reserve using rebalance price
            uint256 reserveAmount = Math.mulDiv(
                amount, 
                rebalancePrice, 
                PRECISION * reserveToAssetDecimalFactor
            );
            
            // Transfer reserve tokens from poolCycleManager to user
            reserveToken.transferFrom(address(poolCycleManager), msg.sender, reserveAmount);
            
            emit ReserveWithdrawn(msg.sender, reserveAmount, requestCycle);
        }
    }

    // --------------------------------------------------------------------------------
    //                          INTEREST MANAGEMENT
    // --------------------------------------------------------------------------------

    /**
     * @notice Calculate and charge interest to all users with positions
     * @return totalInterest Total interest collected in the cycle
     */
    function chargeInterestForCycle() external onlyPoolCycleManager returns (uint256 totalInterest) {
        //uint256 currentCycle = poolCycleManager.cycleIndex();
        // uint256 currentRate = getCurrentInterestRate();
        // uint256 cycleLength = poolCycleManager.cycleLength();
        
        // Calculate pro-rated interest for this cycle (annualized rate * cycle length / seconds in year)
        // uint256 cycleInterestRate = (currentRate * cycleLength) / SECONDS_PER_YEAR;
        
        // Reset current cycle interest
        // currentCycleInterest = 0;
        
        // This would benefit from an enumerable set of active users to avoid 
        // iterating over all addresses that ever had a position
        // For production, implement a separate tracking mechanism for active positions
        
        // For now, we leave implementation details to optimize this based on actual protocol usage
        
        // Return accumulated interest
        // return totalInterest;
    }

    /**
     * @notice Distribute collected interest to LPs
     */
    function distributeInterestToLPs() external onlyPoolCycleManager {
        uint256 interestToDistribute = currentCycleInterest;
        if (interestToDistribute == 0) return;
        
        // Reset current cycle interest
        currentCycleInterest = 0;
        
        // Get total LP liquidity
        uint256 totalLiquidity = poolLiquidityManager.getTotalLPLiquidity();
        if (totalLiquidity == 0) return;
        
        // Get count of LPs
        uint256 lpCount = poolLiquidityManager.getLPCount();
        if (lpCount == 0) return;
        
        // Distribute interest to each LP according to their share of total liquidity
        // This would be called after rebalancing when we know which LPs participated
        
        emit InterestDistributed(interestToDistribute, poolCycleManager.cycleIndex());
    }

    // --------------------------------------------------------------------------------
    //                            INTEREST CALCULATION
    // --------------------------------------------------------------------------------

    /**
     * @notice Calculate current interest rate based on pool utilization
     * @return rate Current interest rate (scaled by 10000)
     */
    function getCurrentInterestRate() public view returns (uint256 rate) {
        uint256 utilization = getPoolUtilization();
        return interestRateStrategy.calculateInterestRate(utilization);
    }

    /**
     * @notice Calculate pool utilization ratio
     * @return utilization Pool utilization as a percentage (scaled by 10000)
     */
    function getPoolUtilization() public view returns (uint256 utilization) {
        uint256 totalLiquidity = poolLiquidityManager.getTotalLPLiquidity();
        if (totalLiquidity == 0) return 0;
        
        uint256 assetSupply = assetToken.totalSupply();
        uint256 assetPrice = assetOracle.assetPrice();
        uint256 newMints = _cycleTotalDepositRequests;
        
        // Calculate total value: current asset supply * price + new expected mints
        uint256 totalValue = Math.mulDiv(assetSupply, assetPrice, PRECISION) + newMints;
        
        return Math.min((totalValue * BPS) / totalLiquidity, BPS);
    }

    /**
     * @notice Calculate required collateral for a user
     * @param user Address of the user
     * @return requiredCollateral Required collateral amount
     */
    function calculateRequiredCollateral(address user) public view returns (uint256 requiredCollateral) {
        uint256 assetBalance = assetToken.balanceOf(user);
        if (assetBalance == 0) return 0;
        
        uint256 assetPrice = assetOracle.assetPrice();
        uint256 assetValue = Math.mulDiv(assetBalance, assetPrice, PRECISION);
        
        // Required collateral = asset value * minimum collateral ratio / BPS
        return (assetValue * minCollateralRatio) / BPS;
    }

    // --------------------------------------------------------------------------------
    //                               VIEW FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Get a user's collateral amount
     * @param user Address of the user
     * @return amount User's collateral amount
     */
    function userCollateral(address user) external view returns (uint256 amount) {
        return positions[user].collateralAmount;
    }

    /**
     * @notice Get a user's position details
     * @param user Address of the user
     * @return assetAmount Amount of asset tokens in position
     * @return requiredCollateral Minimum required collateral
     * @return isLiquidatable Whether position can be liquidated
     */
    function userPosition(address user) public view returns (
        uint256 assetAmount,
        uint256 requiredCollateral,
        bool isLiquidatable
    ) {
        Position storage position = positions[user];
        
        assetAmount = assetToken.balanceOf(user);
        requiredCollateral = calculateRequiredCollateral(user);
        
        if (assetAmount == 0) {
            return (0, 0, false);
        }
        
        // Position is liquidatable if collateral falls below liquidation threshold
        uint256 assetPrice = assetOracle.assetPrice();
        uint256 assetValue = Math.mulDiv(assetAmount, assetPrice, PRECISION);
        uint256 liquidationThresholdAmount = (assetValue * liquidationThreshold) / BPS;
        
        isLiquidatable = position.collateralAmount < liquidationThresholdAmount;
        
        return (assetAmount, requiredCollateral, isLiquidatable);
    }

    /**
     * @notice Get a user's pending request
     * @param user Address of the user
     * @return amount Amount involved in the request
     * @return isDeposit Whether it's a deposit or redemption
     * @return requestCycle Cycle when request was made
     */
    function userRequest(address user) external view returns (
        uint256 amount,
        bool isDeposit,
        uint256 requestCycle
    ) {
        UserRequest storage request = userRequests[user];
        return (request.amount, request.isDeposit, request.requestCycle);
    }

    /**
     * @notice Get the minimum collateral ratio
     * @return The minimum collateral ratio (scaled by 10000)
     */
    function getMinCollateralRatio() external view returns (uint256) {
        return minCollateralRatio;
    }

    /**
     * @notice Get the liquidation threshold
     * @return The liquidation threshold (scaled by 10000)
     */
    function getLiquidationThreshold() external view returns (uint256) {
        return liquidationThreshold;
    }

    /**
     * @notice Get total pending deposit requests for the current cycle
     * @return Total amount of pending deposits
     */
    function cycleTotalDepositRequests() external view returns (uint256) {
        return _cycleTotalDepositRequests;
    }

    /**
     * @notice Get total pending redemption requests for the current cycle
     * @return Total amount of pending redemptions
     */
    function cycleTotalRedemptionRequests() external view returns (uint256) {
        return _cycleTotalRedemptionRequests;
    }

    /**
     * @notice Returns the reserve token contract
     */
    function getReserveToken() external view returns (IERC20Metadata) {
        return reserveToken;
    }

    /**
     * @notice Returns the asset token contract
     */
    function getAssetToken() external view returns (IXToken) {
        return assetToken;
    }

    /**
     * @notice Returns the pool cycle manager contract
     */
    function getPoolCycleManager() external view returns (IPoolCycleManager) {
        return poolCycleManager;
    }

    /**
     * @notice Returns the pool liquidity manager contract
     */
    function getPoolLiquidityManager() external view returns (IPoolLiquidityManager) {
        return poolLiquidityManager;
    }

    /**
    * @notice Returns the asset oracle contract
    */
    function getAssetOracle() external view returns (IAssetOracle) {
        return assetOracle;
    }

    /**
     * @notice Returns the reserve to asset decimal factor
     */
    function getReserveToAssetDecimalFactor() external view returns (uint256) {
        return reserveToAssetDecimalFactor;
    }

    // --------------------------------------------------------------------------------
    //                           GOVERNANCE FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Update the minimum collateral ratio
     * @param newRatio New minimum collateral ratio
     */
    function setMinCollateralRatio(uint256 newRatio) external onlyOwner {
        if (newRatio <= liquidationThreshold) revert("Ratio must exceed liquidation threshold");
        if (newRatio > 200_00) revert("Ratio cannot exceed 200%");
        
        minCollateralRatio = newRatio;
    }

    /**
     * @notice Update the liquidation threshold
     * @param newThreshold New liquidation threshold
     */
    function setLiquidationThreshold(uint256 newThreshold) external onlyOwner {
        if (newThreshold >= minCollateralRatio) revert("Threshold must be below min collateral ratio");
        if (newThreshold < 105_00) revert("Threshold cannot be below 105%");
        
        liquidationThreshold = newThreshold;
    }

    /**
     * @notice Update the liquidation reward percentage
     * @param newReward New liquidation reward percentage
     */
    function setLiquidationReward(uint256 newReward) external onlyOwner {
        if (newReward > 10_00) revert("Reward cannot exceed 10%");
        
        liquidationReward = newReward;
    }

    // --------------------------------------------------------------------------------
    //                           INTERNAL FUNCTIONS
    // --------------------------------------------------------------------------------


    /**
     * @notice Handle interest accrual for a specific user
     * @param user Address of the user
     * @param cycleIndex Current cycle index
     * @return interestAmount Interest amount charged
     */
    function accrueUserInterest(address user, uint256 cycleIndex) internal returns (uint256 interestAmount) {
        Position storage position = positions[user];
        
        // Skip if no assets or already updated this cycle
        if (assetToken.balanceOf(user) == 0 || position.lastInterestCycle == cycleIndex) {
            return 0;
        }
        
        uint256 assetBalance = assetToken.balanceOf(user);
        uint256 assetPrice = assetOracle.assetPrice();
        uint256 assetValue = Math.mulDiv(assetBalance, assetPrice, PRECISION);
        
        // Calculate cycles since last interest accrual
        uint256 cyclesSinceLastAccrual = 0;
        if (position.lastInterestCycle < cycleIndex) {
            cyclesSinceLastAccrual = cycleIndex - position.lastInterestCycle;
        }
        
        // If this is the user's first cycle with a position
        if (position.lastInterestCycle == 0 && assetBalance > 0) {
            position.lastInterestCycle = cycleIndex;
            return 0;
        }
        
        // Calculate interest for elapsed cycles
        uint256 interestRate = getCurrentInterestRate();
        uint256 cycleLength = poolCycleManager.cycleLength();
        uint256 cyclicalInterestRate = (interestRate * cycleLength * cyclesSinceLastAccrual) / SECONDS_PER_YEAR;
        
        // Calculate interest amount
        interestAmount = (assetValue * cyclicalInterestRate) / BPS;
        
        // Apply interest (deduct from collateral)
        if (interestAmount > 0 && position.collateralAmount >= interestAmount) {
            position.collateralAmount -= interestAmount;
            currentCycleInterest += interestAmount;
            position.lastInterestCycle = cycleIndex;
            
            emit InterestCharged(user, interestAmount, cycleIndex);
        } else if (interestAmount > 0) {
            // User doesn't have enough collateral to pay full interest
            currentCycleInterest += position.collateralAmount;
            
            emit InterestCharged(user, position.collateralAmount, cycleIndex);
            
            // Position becomes liquidatable
            position.collateralAmount = 0;
            position.lastInterestCycle = cycleIndex;
        }
        
        return interestAmount;
    }
}