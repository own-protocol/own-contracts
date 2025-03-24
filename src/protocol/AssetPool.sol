// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IAssetPool} from "../interfaces/IAssetPool.sol";
import {IXToken} from "../interfaces/IXToken.sol";
import {IPoolLiquidityManager} from "../interfaces/IPoolLiquidityManager.sol";
import {IAssetOracle} from "../interfaces/IAssetOracle.sol";
import {IPoolCycleManager} from "../interfaces/IPoolCycleManager.sol";
import {IPoolStrategy} from "../interfaces/IPoolStrategy.sol";
import {PoolStorage} from"./PoolStorage.sol";
import {xToken} from "./xToken.sol";

/**
 * @title AssetPool
 * @notice Manages user positions, collateral, and interest payments in the protocol
 * @dev Handles the lifecycle of user positions and calculates interest based on pool utilization
 */
contract AssetPool is IAssetPool, PoolStorage, Ownable, ReentrancyGuard {
    // --------------------------------------------------------------------------------
    //                               STATE VARIABLES
    // --------------------------------------------------------------------------------

    /**
     * @notice Total user deposit requests for the current cycle
     */
    uint256 public cycleTotalDepositRequests;

    /**
     * @notice Total user redemption requests for the current cycle
     */
    uint256 public cycleTotalRedemptionRequests;

    /**
     * @notice Reserve token balance of the pool (excluding new deposits).
     */
    uint256 public poolReserveBalance;

    /**
     * @notice Mapping of user addresses to their positions
     */
    mapping(address => UserPosition) public userPositions;

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
        if (poolCycleManager.cycleState() != IPoolCycleManager.CycleState.POOL_ACTIVE) revert("Cycle not active");
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
     * @param _poolStrategy Address of the pool strategy contract
     * @param _owner Address of the contract owner
     */
    function initialize(
        address _reserveToken,
        string memory _assetTokenSymbol,
        address _assetOracle,
        address _poolCycleManager,
        address _poolLiquidityManager,
        address _poolStrategy,
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
        poolStrategy = IPoolStrategy(_poolStrategy);

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

        UserPosition storage position = userPositions[msg.sender];
        
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
        
        UserPosition storage position = userPositions[msg.sender];
        if (position.collateralAmount < amount) revert InsufficientBalance();
        
        // Calculate required collateral
        uint256 requiredCollateral = poolStrategy.calculateUserRequiredCollateral(address(this), msg.sender);
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
        
        UserPosition storage position = userPositions[user];
        
        // Check if position is liquidatable
        uint256 collateralHealth = poolStrategy.getUserCollateralHealth(address(this), user);
        bool isLiquidatable = collateralHealth == 1;
        if (!isLiquidatable) revert PositionNotLiquidatable();

        ( , , uint256 liquidationReward) = poolStrategy.getUserCollateralParams();
        
        // Calculate liquidation reward
        uint256 liquidationRewardAmount = Math.mulDiv(position.collateralAmount, liquidationReward, BPS);
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

        (, , , , ,uint256 maxUtilisation) = poolStrategy.getInterestRateParams();
        // Check if pool has enough liquidity to accept the deposit
        uint256 utilisation = getPoolUtilizationWithDeposit(amount);
        if (utilisation > maxUtilisation) revert InsufficientLiquidity();

        (uint256 healthyRatio , ,) = poolStrategy.getUserCollateralParams();
        
        // Calculate minimum required collateral based on deposit amount
        uint256 minRequiredCollateral = Math.mulDiv(amount, healthyRatio, BPS);
        
        // Ensure provided collateral meets minimum requirement
        if (collateralAmount < minRequiredCollateral) revert InsufficientCollateral();

        uint256 totalDeposit = amount + collateralAmount;

        // Transfer tokens from user to poolCycleManager
        reserveToken.transferFrom(msg.sender, address(this), totalDeposit);
        
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

        UserPosition memory position = userPositions[msg.sender];
        if (position.assetAmount < amount) revert InvalidRedemptionRequest();
        
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

        uint256 totalDeposit = amount + collateralAmount;
        
        // Clear request
        delete userRequests[msg.sender];
        
        if (isDeposit) {
            cycleTotalDepositRequests -= amount;
            // Return reserve tokens and collateral
            reserveToken.transfer(msg.sender, totalDeposit);
            
            
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

        UserPosition storage position = userPositions[user];
        
        if (isDeposit) {
            // Mint case - convert reserve to asset using rebalance price
            uint256 assetAmount = Math.mulDiv(
                amount, 
                PRECISION * reserveToAssetDecimalFactor, 
                rebalancePrice
            );

            // Get total cumulative interest in reserve from cycle manager
            uint256 totalInterest = poolCycleManager.cumulativeInterestAmount();
            
            if (totalInterest > 0) {
                // Calculate scaled interest based on asset amount
                position.scaledInterest += Math.mulDiv(assetAmount, PRECISION, totalInterest * reserveToAssetDecimalFactor);
            }

            // Update user's position
            position.assetAmount += assetAmount;
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
            uint256 positionAssetAmount = position.assetAmount;
            if(positionAssetAmount - amount == 0) {
                uint256 interestDebt = getInterestDebt(user);
                balanceCollateral = position.collateralAmount - interestDebt;
                position.scaledInterest = 0;
                position.assetAmount = 0;
                position.collateralAmount = 0;
            } else {
                position.assetAmount -= amount;
            }         
        
            uint256 totalAmount = reserveAmount + balanceCollateral;
            // Transfer reserve tokens from poolCycleManager to user
            reserveToken.transfer(user, totalAmount);
            
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
        UserPosition storage position = userPositions[user];
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
     * @notice Calculate current interest rate based on pool utilization
     * @return rate Current interest rate (scaled by 10000)
     */
    function getCurrentInterestRate() public view returns (uint256 rate) {
        uint256 utilization = getPoolUtilization();
        return poolStrategy.calculateInterestRate(utilization);
    }

    /**
     * @notice Calculate pool utilization ratio
     * @return utilization Pool utilization as a percentage (scaled by 10000)
     */
    function getPoolUtilization() public view returns (uint256 utilization) {
        uint256 totalLiquidity = poolLiquidityManager.getTotalLPLiquidityCommited();
        if (totalLiquidity == 0) return 0;
        uint256 utilisedLiquidity = getUtilisedLiquidity();
        
        return Math.min((utilisedLiquidity * BPS) / totalLiquidity, BPS);
    }

    /**
     * @notice Calculate pool utilization ratio considering the deposit amount
     * @param depositAmount Additional deposit amount to consider in calculation
     * @return utilization Pool utilization as a percentage (scaled by 10000)
     */
    function getPoolUtilizationWithDeposit(uint256 depositAmount) public view returns (uint256 utilization) {
        uint256 totalLiquidity = poolLiquidityManager.getTotalLPLiquidityCommited();
        if (totalLiquidity == 0) return 0;

        uint256 assetPrice = assetOracle.assetPrice();
        
        uint256 utilisedLiquidity = getUtilisedLiquidity() 
            + cycleTotalDepositRequests 
            + depositAmount
            - Math.mulDiv(cycleTotalRedemptionRequests, assetPrice, PRECISION * reserveToAssetDecimalFactor);
        
        return ((utilisedLiquidity * BPS) / totalLiquidity);
    }

    /**
     * @notice Calculate utilised liquidity in the pool
     * @return utilisedLiquidity Total utilised liquidity in reserve tokens
     */
    function getUtilisedLiquidity() public view returns (uint256) {      

        uint256 poolValue = getPoolValue();
        (uint256 healthyRatio, , ) = poolStrategy.getLPLiquidityParams();
        uint256 totalRatio = BPS + healthyRatio;

        uint256 utilisedLiquidity = Math.mulDiv(poolValue, totalRatio, BPS);
        
        return utilisedLiquidity;
    }

    /**
     * @notice Calculate pool value
     * @return value Pool value in reserve tokens
     */
    function getPoolValue() public view returns (uint256 value) {
        uint256 assetSupply = assetToken.totalSupply();
        uint256 assetPrice = assetOracle.assetPrice();

        return Math.mulDiv(assetSupply, assetPrice, PRECISION * reserveToAssetDecimalFactor);
    }

    // --------------------------------------------------------------------------------
    //                               EXTERNAL FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
    * @notice Deducts interest from the pool and transfers it to the liquidity manager
    * @param lp Address of the LP to whom interest is owed
    * @param amount Amount of interest to deduct
    */
    function deductInterest(address lp, uint256 amount) external onlyPoolCycleManager {
        if (amount == 0) revert InvalidAmount();

        // Check if we have enough reserve tokens for the interest
        uint256 reserveBalance = reserveToken.balanceOf(address(this));

        if(reserveBalance < amount) revert InsufficientBalance();

        // Calculate and deduct protocol fee
        uint256 protocolFeePercentage = poolStrategy.getProtocolFee();
        uint256 protocolFee = (protocolFeePercentage > 0) ? Math.mulDiv(amount, protocolFeePercentage, BPS) : 0;
        if (protocolFee > 0) {
            reserveToken.transfer(poolStrategy.getFeeRecipient(), protocolFee);
            emit FeeDeducted(lp, protocolFee);
        }
        
        uint256 lpCycleInterest = amount - protocolFee;

        uint256 cycleIndex = poolCycleManager.cycleIndex();

        // Transfer interest to liquidity manager
        reserveToken.transfer(address(poolLiquidityManager), lpCycleInterest);

        poolLiquidityManager.addToInterest(lp, lpCycleInterest);
            
        emit InterestDistributedToLP(lp, lpCycleInterest, cycleIndex);
    }

    /**
     * @notice Update cycle data at the end of a cycle
     */
    function updateCycleData(uint256 rebalancePrice, int256 rebalanceAmount) external onlyPoolCycleManager {
        uint256 assetBalance = assetToken.balanceOf(address(this));
        uint256 reserveBalanceInAssetToken = assetToken.reserveBalanceOf(address(this));
        poolReserveBalance = poolReserveBalance 
            + cycleTotalDepositRequests
            - Math.mulDiv(cycleTotalRedemptionRequests, rebalancePrice, PRECISION * reserveToAssetDecimalFactor);

        if (rebalanceAmount > 0) {
            poolReserveBalance += uint256(rebalanceAmount);
        } else if (rebalanceAmount < 0) {
            poolReserveBalance -= uint256(-rebalanceAmount);
        }

        if (assetBalance > 0) {
            assetToken.burn(address(this), assetBalance, reserveBalanceInAssetToken);
        }

        cycleTotalDepositRequests = 0;
        cycleTotalRedemptionRequests = 0;
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
        return userPositions[user].collateralAmount;
    }

    /**
     * @notice Get a user's position details
     * @param user Address of the user
     * @return assetAmount Amount of asset tokens in position
     * @return collateralAmount Amount of collateral in position
     * @return interestDebt Amount of interest debt in reserve tokens
     */
    function userPosition(address user) external view returns (
        uint256 assetAmount,
        uint256 collateralAmount,
        uint256 interestDebt
    ) {
        UserPosition storage position = userPositions[user];
        assetAmount = position.assetAmount;
        collateralAmount = position.collateralAmount;
        interestDebt = getInterestDebt(user);
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
     * @notice Returns the pool strategy contract
     */
    function getPoolStrategy() external view returns (IPoolStrategy) {
        return poolStrategy;
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