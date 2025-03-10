// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

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
     * @notice Healthy collateral ratio required (scaled by 10000, default: 120%)
     */
    uint256 public constant healthyCollateralRatio = 120_00;

    /**
     * @notice Liquidation threshold ratio (scaled by 10000, default: 110%)
     */
    uint256 public constant liquidationThreshold = 110_00;

    /**
     * @notice Liquidation reward percentage (scaled by 10000, default: 5%)
     */
    uint256 public constant liquidationReward = 5_00;

    /**
     * @notice Total interest collected in the current cycle
     */
    uint256 public currentCycleInterest;

    /**
     * @notice Total user deposit requests for the current cycle
     */
    uint256 public cycleTotalDepositRequests;

    /**
     * @notice Total user redemption requests for the current cycle
     */
    uint256 public cycleTotalRedemptionRequests;

    /**
     * @notice Mapping of user addresses to their positions
     */
    mapping(address => Position) public positions;

    /**
     * @notice Mapping of user addresses to their pending requests
     */
    mapping(address => UserRequest) public userRequests;

    /**
     * @notice Total user collateral in the pool
     */
    uint256 public totalUserCollateral;

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
        assetToken = new xToken(_assetTokenSymbol, _assetTokenSymbol, _poolCycleManager);
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
     * @notice Allows users to deposit additional collateral
     * @param amount Amount of collateral to deposit
     */
    function addCollateral(uint256 amount) external nonReentrant {
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
    function withdrawCollateral(uint256 amount) external nonReentrant {
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
     * ToDo: Require liquidator to add the assetToken to the pool which will be used to liquidate the position
     */
    function liquidatePosition(address user) external nonReentrant {
        if (user == address(0) || user == msg.sender) revert Unauthorized();
        
        Position storage position = positions[user];
        
        // Check if position is liquidatable
        (,, bool isLiquidatable) = userPosition(user);
        if (!isLiquidatable) revert PositionNotLiquidatable();
        
        // Calculate liquidation reward
        uint256 liquidationRewardAmount = (position.collateralAmount * liquidationReward) / BPS;
        uint256 remainingCollateral = position.collateralAmount - (liquidationRewardAmount + getInterestDebt(user));
        
        // Clear the user's position
        position.collateralAmount = 0;
        position.scaledInterest = 0;
        
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
     * @param collateralAmount Amount of collateral to provide
     */
    function depositRequest(uint256 amount, uint256 collateralAmount) external nonReentrant onlyActiveCycle {
        if (amount == 0) revert InvalidAmount();
        if (collateralAmount == 0) revert InvalidAmount();
        
        UserRequest storage request = userRequests[msg.sender];
        if (request.amount > 0) revert RequestPending();
        
        // Calculate minimum required collateral based on deposit amount
        uint256 minRequiredCollateral = Math.mulDiv(amount, healthyCollateralRatio - BPS, BPS);
        
        // Ensure provided collateral meets minimum requirement
        if (collateralAmount < minRequiredCollateral) revert InsufficientCollateral();
        
        // Transfer tokens from user to poolCycleManager
        reserveToken.transferFrom(msg.sender, address(this), amount + collateralAmount);
        
        // Update request state
        request.amount = amount;
        request.collateralAmount = collateralAmount;
        request.isDeposit = true;
        request.requestCycle = poolCycleManager.cycleIndex();
        cycleTotalDepositRequests += amount;
        
        emit DepositRequested(msg.sender, amount, poolCycleManager.cycleIndex());
    }

    /**
     * @notice Process a redemption request
     * @param amount Amount of asset tokens to redeem
     */
    function redemptionRequest(uint256 amount) external nonReentrant onlyActiveCycle {
        if (amount == 0) revert InvalidAmount();
        
        uint256 userBalance = assetToken.balanceOf(msg.sender);
        if (userBalance < amount) revert InsufficientBalance();
        
        UserRequest storage request = userRequests[msg.sender];
        if (request.amount > 0) revert RequestPending();
        
        // Transfer asset tokens from user to poolCycleManager
        assetToken.transferFrom(msg.sender, address(this), amount);
        
        // Update request state
        request.amount = amount;
        request.collateralAmount = 0;
        request.isDeposit = false;
        request.requestCycle = poolCycleManager.cycleIndex();
        cycleTotalRedemptionRequests += amount;
        
        emit RedemptionRequested(msg.sender, amount, poolCycleManager.cycleIndex());
    }

    /**
     * @notice Cancel a pending request
     */
    function cancelRequest() external nonReentrant onlyActiveCycle {
        UserRequest storage request = userRequests[msg.sender];
        uint256 amount = request.amount;
        uint256 collateralAmount = request.collateralAmount;
        bool isDeposit = request.isDeposit;
        uint256 requestCycle = request.requestCycle;
        
        if (requestCycle != poolCycleManager.cycleIndex()) revert NothingToCancel();
        if (amount == 0) revert NothingToCancel();
        
        // Clear request
        delete userRequests[msg.sender];
        
        if (isDeposit) {
            cycleTotalDepositRequests -= amount;
            // Return reserve tokens and collateral
            reserveToken.transfer(msg.sender, amount + collateralAmount);
            
            
            emit DepositCancelled(msg.sender, amount, poolCycleManager.cycleIndex());
        } else {
            cycleTotalRedemptionRequests -= amount;
            // Return asset tokens
            assetToken.transferFrom(address(this), msg.sender, amount);
            emit RedemptionCancelled(msg.sender, amount, poolCycleManager.cycleIndex());
        }
    }

    /**
     * @notice Claim processed request
     * @param user Address of the user
     */
    function claimRequest(address user) external nonReentrant onlyActiveCycle {
        UserRequest storage request = userRequests[user];
        uint256 amount = request.amount;
        uint256 collateralAmount = request.collateralAmount;
        bool isDeposit = request.isDeposit;
        uint256 requestCycle = request.requestCycle;
        
        if (requestCycle >= poolCycleManager.cycleIndex()) revert NothingToClaim();
        if (amount == 0) revert NothingToClaim();
        
        // Get the rebalance price from the pool cycle manager
        uint256 rebalancePrice = poolCycleManager.cycleRebalancePrice(requestCycle);
        
        // Clear request
        delete userRequests[user];

        Position storage position = positions[user];
        
        if (isDeposit) {
            // Mint case - convert reserve to asset using rebalance price
            uint256 assetAmount = Math.mulDiv(
                amount, 
                PRECISION * reserveToAssetDecimalFactor, 
                rebalancePrice
            );

            // Get total cumulative interest in reserve from cycle manager
            uint256 totalInterest = poolCycleManager.cumulativeInterestAmount();
            
            // Calculate user's scaled interest based on their deposit amount
            // For initial deposits, the deposit amount is the correct measure of their capital at risk
            if (totalInterest > 0) {
                // Calculate proportional interest based on deposit amount
                position.scaledInterest += Math.mulDiv(
                    assetAmount, 
                    totalInterest, 
                    cycleTotalDepositRequests
                ); 
            }
        
            position.collateralAmount += collateralAmount;
            
            // Mint tokens
            assetToken.mint(user, assetAmount, amount);
            
            emit AssetClaimed(user, assetAmount, requestCycle);
        } else {
            // Withdraw case - convert asset to reserve using rebalance price
            uint256 reserveAmount = Math.mulDiv(
                amount, 
                rebalancePrice, 
                PRECISION * reserveToAssetDecimalFactor
            );

            uint256 balanceCollateral = 0;
            if(assetToken.balanceOf(user) == 0) {
                uint256 interestDebt = getInterestDebt(user);
                balanceCollateral = position.collateralAmount - interestDebt;
                position.scaledInterest = 0;
                position.collateralAmount = 0;
            }
        
            // Transfer reserve tokens from poolCycleManager to user
            reserveToken.transfer(user, reserveAmount + balanceCollateral);
            
            emit ReserveWithdrawn(user, reserveAmount, requestCycle);
        }
    }

    // --------------------------------------------------------------------------------
    //                            INTEREST MANAGEMENT
    // --------------------------------------------------------------------------------

    /**
     * @notice Calculate interest debt for a user
     * @param user User address
     * @return interestDebt Amount of interest debt in reserve tokens
     */
    function getInterestDebt(address user) public view returns (uint256 interestDebt) {
        Position storage position = positions[user];
        uint256 scaledInterest = position.scaledInterest;
        if (scaledInterest == 0) return 0;
        
        uint256 totalInterest = poolCycleManager.cumulativeInterestAmount();
        if (totalInterest == 0) return 0;
        
        // Calculate user's share of total interest
        return Math.mulDiv(
            scaledInterest,
            totalInterest,
            PRECISION
        );
    }

    /**
     * @notice Check collateral health status of a user
     * @param user User address
     * @return health 3 = Healthy, 2 = Warning, 1 = Liquidatable
     */
    function getCollateralHealth(address user) public view returns (uint8 health) {
        Position storage position = positions[user];
        uint256 assetBalance = assetToken.balanceOf(user);
        
        if (assetBalance == 0) {
            return 3; // Healthy - no asset balance means no risk
        }
        
        uint256 assetPrice = assetOracle.assetPrice();
        uint256 assetValue = Math.mulDiv(assetBalance, assetPrice, PRECISION);
        
        // Calculate required collateral
        uint256 requiredCollateral = Math.mulDiv(assetValue, healthyCollateralRatio, BPS);
        
        // Calculate interest debt
        uint256 interestDebt = getInterestDebt(user);
        
        // Total required = collateral requirement + interest debt
        uint256 totalRequired = requiredCollateral + interestDebt;
        
        // Calculate liquidation threshold amount
        uint256 liquidationThresholdAmount = Math.mulDiv(assetValue, liquidationThreshold, BPS) + interestDebt;
        
        if (position.collateralAmount >= totalRequired) {
            return 3; // Healthy
        } else if (position.collateralAmount >= liquidationThresholdAmount) {
            return 2; // Warning
        } else {
            return 1; // Liquidatable
        }
    }

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
        uint256 newMints = cycleTotalDepositRequests;
        
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
        return (assetValue * healthyCollateralRatio) / BPS;
    }

    // --------------------------------------------------------------------------------
    //                               EXTERNAL FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
    * @notice Deducts interest from the pool and transfers it to the liquidity manager
    * @param amount Amount of interest to deduct
    */
    function deductInterest(uint256 amount) external onlyPoolCycleManager {
        if (amount == 0) revert InvalidAmount();

        // Check if we have enough reserve tokens for the interest
        uint256 reserveBalance = reserveToken.balanceOf(address(this));

        if(reserveBalance < amount) revert InsufficientBalance();
        
        // Transfer interest to liquidity manager
        reserveToken.transfer(address(poolLiquidityManager), amount);   
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
        uint8 health = getCollateralHealth(user);
        assetAmount = assetToken.balanceOf(user);
        requiredCollateral = calculateRequiredCollateral(user);
        isLiquidatable = (health == 1);
        
        return (assetAmount, requiredCollateral, isLiquidatable);
    }

    /**
     * @notice Get a user's pending request
     * @param user Address of the user
     * @return amount Amount involved in the request
     * @return collateralAmount Collateral amount involved in the request
     * @return isDeposit Whether it's a deposit or redemption
     * @return requestCycle Cycle when request was made
     */
    function userRequest(address user) external view returns (
        uint256 amount,
        uint256 collateralAmount,
        bool isDeposit,
        uint256 requestCycle
    ) {
        UserRequest storage request = userRequests[user];
        return (request.amount, request.collateralAmount, request.isDeposit, request.requestCycle);
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

}