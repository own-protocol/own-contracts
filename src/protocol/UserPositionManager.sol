// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/contracts/utils/Pausable.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "../interfaces/IUserPositionManager.sol";
import "../interfaces/IAssetPool.sol";
import "../interfaces/ILPLiquidityManager.sol";
import "../interfaces/IXToken.sol";
import "../interfaces/IAssetOracle.sol";

/**
 * @title UserPositionManager
 * @notice Manages user positions, collateral, and interest payments in the protocol
 * @dev Handles the lifecycle of user positions and calculates interest based on pool utilization
 */
contract UserPositionManager is IUserPositionManager, Ownable, Pausable, ReentrancyGuard, Initializable {
    // --------------------------------------------------------------------------------
    //                               STATE VARIABLES
    // --------------------------------------------------------------------------------

    /**
     * @notice Struct to track a user's position
     * @param collateralAmount Amount of collateral deposited
     * @param lastInterestCycle Last cycle when interest was charged
     */
    struct Position {
        uint256 collateralAmount;
        uint256 lastInterestCycle;
    }

    /**
     * @notice Struct to track user requests
     * @param amount Amount of tokens requested
     * @param isDeposit True for deposit, false for redemption
     * @param requestCycle Cycle when request was made
     */
    struct UserRequest {
        uint256 amount;
        bool isDeposit;
        uint256 requestCycle;
    }

    /**
     * @notice Address of the asset pool contract
     */
    IAssetPool public assetPool;

    /**
     * @notice Reserve token used for collateral (e.g., USDC)
     */
    IERC20Metadata public reserveToken;

    /**
     * @notice Asset token representing the underlying asset
     */
    IXToken public assetToken;

    /**
     * @notice Oracle providing asset price information
     */
    IAssetOracle public assetOracle;

    /**
     * @notice LP Liquidity Manager contract
     */
    ILPLiquidityManager public lpLiquidityManager;

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
     * @notice Base interest rate when utilization < 50% (scaled by 10000, default: 6%)
     */
    uint256 public baseInterestRate = 6_00;

    /**
     * @notice Maximum interest rate at 90% utilization (scaled by 10000, default: 36%)
     */
    uint256 public maxInterestRate = 36_00;

    /**
     * @notice Optimal utilization point (scaled by 10000, default: 80%)
     */
    uint256 public optimalUtilization = 80_00;

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
     * @notice Precision factor for calculations
     */
    uint256 private constant PRECISION = 1e18;

    /**
     * @notice Basis points scaling factor
     */
    uint256 private constant BPS = 100_00;

    /**
     * @notice Seconds in a year, used for interest calculations
     */
    uint256 private constant SECONDS_PER_YEAR = 365 days;

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
     * @dev Ensures the caller is the asset pool
     */
    modifier onlyAssetPool() {
        if (msg.sender != address(assetPool)) revert NotAssetPool();
        _;
    }

    /**
     * @dev Ensures the cycle state is active
     */
    modifier onlyActiveCycle() {
        if (assetPool.cycleState() != IAssetPool.CycleState.ACTIVE) revert("Cycle not active");
        _;
    }

    // --------------------------------------------------------------------------------
    //                                 INITIALIZER
    // --------------------------------------------------------------------------------

    /**
     * @notice Initializes the UserPositionManager contract
     * @param _assetPool Address of the asset pool contract
     * @param _owner Address of the contract owner
     */
    function initialize(address _assetPool, address _owner) external initializer {
        if (_assetPool == address(0) || _owner == address(0)) revert ZeroAddress();

        assetPool = IAssetPool(_assetPool);
        reserveToken = IERC20Metadata(address(assetPool.reserveToken()));
        assetToken = IXToken(address(assetPool.assetToken()));
        assetOracle = IAssetOracle(address(assetPool.assetOracle()));
        lpLiquidityManager = ILPLiquidityManager(address(assetPool.lpLiquidityManager()));

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
        
        // Transfer tokens from user to asset pool
        reserveToken.transferFrom(msg.sender, address(assetPool), amount);
        
        // Update request state
        request.amount = amount;
        request.isDeposit = true;
        request.requestCycle = assetPool.cycleIndex();
        _cycleTotalDepositRequests += amount;
        
        emit DepositRequested(msg.sender, amount, assetPool.cycleIndex());
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
        
        // Transfer asset tokens from user to asset pool
        assetToken.transferFrom(msg.sender, address(assetPool), amount);
        
        // Update request state
        request.amount = amount;
        request.isDeposit = false;
        request.requestCycle = assetPool.cycleIndex();
        _cycleTotalRedemptionRequests += amount;
        
        emit RedemptionRequested(msg.sender, amount, assetPool.cycleIndex());
    }

    /**
     * @notice Cancel a pending request
     */
    function cancelRequest() external nonReentrant onlyActiveCycle {
        UserRequest storage request = userRequests[msg.sender];
        uint256 amount = request.amount;
        bool isDeposit = request.isDeposit;
        uint256 requestCycle = request.requestCycle;
        
        if (requestCycle != assetPool.cycleIndex()) revert NothingToCancel();
        if (amount == 0) revert NothingToCancel();
        
        // Clear request
        delete userRequests[msg.sender];
        
        if (isDeposit) {
            _cycleTotalDepositRequests -= amount;
            // Return reserve tokens
            reserveToken.transferFrom(address(assetPool), msg.sender, amount);
            emit DepositCancelled(msg.sender, amount, assetPool.cycleIndex());
        } else {
            _cycleTotalRedemptionRequests -= amount;
            // Return asset tokens
            assetToken.transferFrom(address(assetPool), msg.sender, amount);
            emit RedemptionCancelled(msg.sender, amount, assetPool.cycleIndex());
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
        
        if (requestCycle >= assetPool.cycleIndex()) revert NothingToClaim();
        if (amount == 0) revert NothingToClaim();
        
        // Get the rebalance price from the asset pool
        uint256 rebalancePrice = assetPool.cycleRebalancePrice(requestCycle);
        
        // Clear request
        delete userRequests[msg.sender];
        
        if (isDeposit) {
            // Mint case - convert reserve to asset using rebalance price
            uint256 assetAmount = Math.mulDiv(
                amount, 
                PRECISION * assetPool.reserveToAssetDecimalFactor(), 
                rebalancePrice
            );
            
            // Mint tokens through asset pool's asset token
            assetToken.mint(msg.sender, assetAmount, amount);
            
            emit AssetClaimed(msg.sender, assetAmount, requestCycle);
        } else {
            // Withdraw case - convert asset to reserve using rebalance price
            uint256 reserveAmount = Math.mulDiv(
                amount, 
                rebalancePrice, 
                PRECISION * assetPool.reserveToAssetDecimalFactor()
            );
            
            // Transfer reserve tokens from asset pool to user
            reserveToken.transferFrom(address(assetPool), msg.sender, reserveAmount);
            
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
    function chargeInterestForCycle() external onlyAssetPool returns (uint256 totalInterest) {
        uint256 currentCycle = assetPool.cycleIndex();
        uint256 currentRate = getCurrentInterestRate();
        uint256 cycleLength = assetPool.cycleLength();
        
        // Calculate pro-rated interest for this cycle (annualized rate * cycle length / seconds in year)
        uint256 cycleInterestRate = (currentRate * cycleLength) / SECONDS_PER_YEAR;
        
        // Reset current cycle interest
        currentCycleInterest = 0;
        
        // This would benefit from an enumerable set of active users to avoid 
        // iterating over all addresses that ever had a position
        // For production, implement a separate tracking mechanism for active positions
        
        // For now, we leave implementation details to optimize this based on actual protocol usage
        
        // Return accumulated interest
        return totalInterest;
    }

    /**
     * @notice Distribute collected interest to LPs
     */
    function distributeInterestToLPs() external onlyAssetPool {
        uint256 interestToDistribute = currentCycleInterest;
        if (interestToDistribute == 0) return;
        
        // Reset current cycle interest
        currentCycleInterest = 0;
        
        // Get total LP liquidity
        uint256 totalLiquidity = lpLiquidityManager.getTotalLPLiquidity();
        if (totalLiquidity == 0) return;
        
        // Get count of LPs
        uint256 lpCount = lpLiquidityManager.getLPCount();
        if (lpCount == 0) return;
        
        // Distribute interest to each LP according to their share of total liquidity
        // This would be called after rebalancing when we know which LPs participated
        
        emit InterestDistributed(interestToDistribute, assetPool.cycleIndex());
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
        
        if (utilization <= 50_00) {
            // Base rate when utilization <= 50%
            return baseInterestRate;
        } else if (utilization <= optimalUtilization) {
            // Linear increase from base rate to optimal rate
            uint256 utilizationDelta = utilization - 50_00;
            uint256 optimalDelta = optimalUtilization - 50_00;
            uint256 optimalRate = (maxInterestRate * 2) / 3; // 2/3 of max rate at optimal utilization
            
            uint256 additionalRate = ((optimalRate - baseInterestRate) * utilizationDelta) / optimalDelta;
            return baseInterestRate + additionalRate;
        } else {
            // Exponential increase from optimal to max utilization
            uint256 utilizationDelta = utilization - optimalUtilization;
            uint256 maxDelta = 90_00 - optimalUtilization;
            uint256 optimalRate = (maxInterestRate * 2) / 3;
            
            uint256 additionalRate = ((maxInterestRate - optimalRate) * utilizationDelta * utilizationDelta) 
                                    / (maxDelta * maxDelta);
            return optimalRate + additionalRate;
        }
    }

    /**
     * @notice Calculate pool utilization ratio
     * @return utilization Pool utilization as a percentage (scaled by 10000)
     */
    function getPoolUtilization() public view returns (uint256 utilization) {
        uint256 totalLiquidity = lpLiquidityManager.getTotalLPLiquidity();
        if (totalLiquidity == 0) return 0;
        
        uint256 assetSupply = assetToken.totalSupply();
        uint256 assetPrice = assetOracle.assetPrice();
        uint256 newMints = _cycleTotalDepositRequests;
        
        // Calculate total value: current asset supply * price + new expected mints
        uint256 totalValue = Math.mulDiv(assetSupply, assetPrice, PRECISION) + newMints;
        
        return Math.min((totalValue * BPS) / totalLiquidity, BPS); // Cap at 100%
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

    /**
     * @notice Update the base interest rate
     * @param newRate New base interest rate
     */
    function setBaseInterestRate(uint256 newRate) external onlyOwner {
        if (newRate > maxInterestRate) revert("Base rate cannot exceed max rate");
        
        baseInterestRate = newRate;
    }

    /**
     * @notice Update the maximum interest rate
     * @param newRate New maximum interest rate
     */
    function setMaxInterestRate(uint256 newRate) external onlyOwner {
        if (newRate < baseInterestRate) revert("Max rate cannot be below base rate");
        if (newRate > 100_00) revert("Max rate cannot exceed 100%");
        
        maxInterestRate = newRate;
    }

    /**
     * @notice Update the optimal utilization point
     * @param newUtilization New optimal utilization point
     */
    function setOptimalUtilization(uint256 newUtilization) external onlyOwner {
        if (newUtilization <= 50_00 || newUtilization >= 90_00) {
            revert("Utilization must be between 50% and 90%");
        }
        
        optimalUtilization = newUtilization;
    }

    /**
     * @notice Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // --------------------------------------------------------------------------------
    //                           ASSET POOL FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Process deposits and redemptions after a cycle completes
     * @dev Called by the asset pool after rebalancing
     * @param prevCycleIndex The previous cycle index that was just completed
     */
    function processCycleCompletion(uint256 prevCycleIndex) external onlyAssetPool {
        // Reset cycle totals for the new cycle
        _cycleTotalDepositRequests = 0;
        _cycleTotalRedemptionRequests = 0;
        
        // Additional cycle processing logic if needed
    }

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
        uint256 cycleLength = assetPool.cycleLength();
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

    /**
     * @notice Modify total deposit and redemption requests for tracking
     * @dev Called by the Asset Pool to sync state with this contract
     * @param depositAmount Total deposits to add/subtract
     * @param redemptionAmount Total redemptions to add/subtract
     * @param isAddition True if adding, false if subtracting
     */
    function modifyRequestTotals(
        uint256 depositAmount, 
        uint256 redemptionAmount, 
        bool isAddition
    ) external onlyAssetPool {
        if (isAddition) {
            _cycleTotalDepositRequests += depositAmount;
            _cycleTotalRedemptionRequests += redemptionAmount;
        } else {
            if (_cycleTotalDepositRequests >= depositAmount) {
                _cycleTotalDepositRequests -= depositAmount;
            }
            
            if (_cycleTotalRedemptionRequests >= redemptionAmount) {
                _cycleTotalRedemptionRequests -= redemptionAmount;
            }
        }
    }
}