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
     * @notice Total user deposits for the current cycle
     */
    uint256 public cycleTotalDeposits;

    /**
     * @notice Total user redemptions for the current cycle
     */
    uint256 public cycleTotalRedemptions;

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
     * @notice Mapping of user addresses to their liquidation initiators
     */
    mapping(address => address) public liquidationInitiators;

    /**
     * @notice Scaled asset balance for interest calculation
     */
    mapping(address => uint256) private scaledAssetBalance;

    /**
     * @notice Scaled reserve balance for interest calculation
     */
    mapping(address => uint256) private scaledReserveBalance;

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
    function addCollateral(uint256 amount) external nonReentrant onlyActiveCycle {
        if (amount == 0) revert InvalidAmount();

        UserPosition storage position = userPositions[msg.sender];
        
        // Transfer collateral from user to this contract
        reserveToken.transferFrom(msg.sender, address(this), amount);
        
        // Update user's position
        position.collateralAmount += amount;

        uint256 collateralHealth = poolStrategy.getUserCollateralHealth(address(this), msg.sender);
        if (collateralHealth < 3)  revert InsufficientCollateral();

        UserRequest storage request = userRequests[msg.sender];
        if (request.requestType == RequestType.LIQUIDATE) {

            if (request.requestCycle != poolCycleManager.cycleIndex()) revert NothingToCancel();

            uint256 requestAmount = request.amount;
            address liquidationInitiator = liquidationInitiators[msg.sender];
            // Cancel liquidation request if collateral is added
            cycleTotalRedemptions -= requestAmount;
            // Refund the liquidator's tokens
            assetToken.transfer(liquidationInitiators[msg.sender], requestAmount);

            delete userRequests[msg.sender];
            delete liquidationInitiators[msg.sender];

            emit LiquidationCancelled(msg.sender, liquidationInitiator, requestAmount);
        }
        
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

        // Check if pool has enough liquidity to accept the deposit
        uint256 availableLiquidity = poolLiquidityManager.getCycleTotalLiquidityCommited() - getCycleUtilisedLiquidity();

        if (availableLiquidity < amount) revert InsufficientLiquidity();

        (uint256 healthyRatio , ,) = poolStrategy.getUserCollateralParams();
        
        // Calculate minimum required collateral based on deposit amount
        uint256 minRequiredCollateral = Math.mulDiv(amount, healthyRatio, BPS);
        
        // Ensure provided collateral meets minimum requirement
        if (collateralAmount < minRequiredCollateral) revert InsufficientCollateral();

        uint256 totalDeposit = amount + collateralAmount;

        // Transfer tokens from user to poolCycleManager
        reserveToken.transferFrom(msg.sender, address(this), totalDeposit);
        
        // Update request state
        request.requestType = RequestType.DEPOSIT;
        request.amount = amount;
        request.collateralAmount = collateralAmount;
        request.requestCycle = poolCycleManager.cycleIndex();
        cycleTotalDeposits += amount;
        
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
        if (request.requestType != RequestType.NONE) revert RequestPending();
        
        // Transfer asset tokens from user to poolCycleManager
        assetToken.transferFrom(msg.sender, address(this), amount);
        
        // Update request state
        request.requestType = RequestType.REDEEM;
        request.amount = amount;
        request.collateralAmount = 0;
        request.requestCycle = poolCycleManager.cycleIndex();
        cycleTotalRedemptions += amount;
        
        emit RedemptionRequested(msg.sender, amount, poolCycleManager.cycleIndex());
    }

    /**
     * @notice Claim processed request
     * @param user Address of the user
     */
    function claimRequest(address user) external nonReentrant onlyActiveCycle {
        UserRequest storage request = userRequests[user];
        RequestType requestType = request.requestType;
        uint256 amount = request.amount;
        uint256 collateralAmount = request.collateralAmount;
        uint256 requestCycle = request.requestCycle;
        
        if (requestCycle >= poolCycleManager.cycleIndex()) revert NothingToClaim();
        if (requestType == RequestType.NONE) revert NothingToClaim();
        
        // Get the rebalance price from the pool cycle manager
        uint256 rebalancePrice = poolCycleManager.cycleRebalancePrice(requestCycle);
        
        // Clear request
        delete userRequests[user];

        UserPosition storage position = userPositions[user];
        uint256 poolInterest = poolCycleManager.cumulativePoolInterest();
        
        if (requestType == RequestType.DEPOSIT) {
            // Mint case - convert reserve to asset using rebalance price
            uint256 assetAmount = Math.mulDiv(
                amount, 
                PRECISION * reserveToAssetDecimalFactor, 
                rebalancePrice
            );

            uint256 scaledAssetAmount = Math.mulDiv(assetAmount, PRECISION, poolInterest);

            // Update user's position
            position.assetAmount += assetAmount;
            position.collateralAmount += collateralAmount;
            scaledAssetBalance[user] += scaledAssetAmount;
            
            // Mint tokens
            assetToken.mint(user, assetAmount, amount);
            
            emit AssetClaimed(user, assetAmount, requestCycle);
        } else {
            // Withdraw case - convert asset to reserve using rebalance price
            (uint256 reserveAmount, uint256 collateralAmount, uint256 scaledAssetAmount, uint256 interestDebt) = 
                _calculateRedemptionValues(user, amount, rebalancePrice);

            uint256 totalAmount = 0;
            uint256 positionAssetAmount = position.assetAmount;
            if(positionAssetAmount - amount == 0) {
                position.assetAmount = 0;
                position.collateralAmount = 0;
                scaledAssetBalance[user] = 0;
            } else {
                position.assetAmount -= amount;
                position.collateralAmount -= collateralAmount;
                scaledAssetBalance[user] -= scaledAssetAmount;
            }
            totalAmount = reserveAmount + collateralAmount - interestDebt;
        
            // Transfer reserve tokens
            if (requestType == RequestType.REDEEM) {
                reserveToken.transfer(user, totalAmount);
            } else if (requestType == RequestType.LIQUIDATE) {
                // Liquidation case - transfer reserve tokens to the liquidator
                address liquidator = liquidationInitiators[user];
                if (liquidator == address(0)) revert InvalidLiquidationRequest();
                reserveToken.transfer(liquidator, totalAmount);
                // Clear liquidation initiator
                delete liquidationInitiators[user];

                emit LiquidationClaimed(user, liquidator, amount, totalAmount, collateralAmount);
            }
            
            emit ReserveWithdrawn(user, reserveAmount, requestCycle);
        }
    }

    /**
     * @notice Initiates a liquidation request for an underwater position
     * @param user Address of the user whose position is to be liquidated
     * @param amount Amount of asset to liquidate (must be <= 30% of user's position)
     */
    function liquidationRequest(address user, uint256 amount) external nonReentrant onlyActiveCycle {
        // Basic validations
        if (user == address(0) || user == msg.sender) revert InvalidLiquidationRequest();
        if (amount == 0) revert InvalidAmount();
        
        // Check if the user's position is liquidatable
        uint8 collateralHealth = poolStrategy.getUserCollateralHealth(address(this), user);
        if (collateralHealth != 1) revert PositionNotLiquidatable();
        
        // Get user's current position
        UserPosition storage position = userPositions[user];
        uint256 userAssetAmount = position.assetAmount;
        
        // Verify that user has assets
        if (userAssetAmount == 0) revert InvalidLiquidationRequest();
        
        // Check if amount exceeds the 30% limit
        uint256 maxLiquidationAmount = (userAssetAmount * 30) / 100; // 30% of user's position
        if (amount > maxLiquidationAmount) revert ExcessiveLiquidationAmount(amount, maxLiquidationAmount);
        
        // Verify the liquidator has enough xTokens
        if (assetToken.balanceOf(msg.sender) < amount) revert InsufficientBalance();
        
        // Check if there's already a liquidation request
        UserRequest storage request = userRequests[user];
        
        // If the current request is better than the previous one, cancel the previous one
        if (request.requestType == RequestType.LIQUIDATE) {

            if(request.amount >= amount) revert BetterLiquidationRequestExists();
            cycleTotalRedemptions -= request.amount;
            // Refund the previous liquidator's tokens
            assetToken.transfer(liquidationInitiators[user], request.amount);
            emit LiquidationCancelled(user, liquidationInitiators[user], request.amount);

        } else if (request.requestType != RequestType.NONE) {
            // Cannot liquidate if there's a non-liquidation request pending
            revert RequestPending();
        }
        
        // Transfer xTokens from liquidator to pool
        assetToken.transferFrom(msg.sender, address(this), amount);
        
        // Create the liquidation request
        request.requestType = RequestType.LIQUIDATE;
        request.amount = amount;
        request.collateralAmount = 0;
        request.requestCycle = poolCycleManager.cycleIndex();

        // Store the liquidator's address
        liquidationInitiators[user] = msg.sender;
        
        cycleTotalRedemptions += amount;
        
        emit LiquidationRequested(user, msg.sender, amount, poolCycleManager.cycleIndex());
    }

    // --------------------------------------------------------------------------------
    //                            INTEREST MANAGEMENT
    // --------------------------------------------------------------------------------

    /**
     * @notice Calculate interest debt for a user (in asset tokens)
     * @param user User address
     * @return interestDebt Amount of interest debt in reserve tokens
     */
    function getInterestDebt(address user) public view returns (uint256 interestDebt) {
        UserPosition storage position = userPositions[user];
        uint256 assetAmount = position.assetAmount;
        uint256 scaledAssetAmount = scaledAssetBalance[user];

        if (assetAmount == 0) return 0;

        uint256 interest = poolCycleManager.cumulativePoolInterest();
        uint256 debt = Math.mulDiv(scaledAssetAmount, interest, PRECISION) - assetAmount;

        return debt;
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
     * @notice Calculate interest rate based on pool utilization (including cycle changes)
     * @dev This function gives the expected interest rate for the next cycle
     * @dev It takes into account the new deposits, redemptions & liquidity changes in the cycle
     * @return rate interest rate (scaled by 10000)
     */
    function getCycleInterestRate() public view returns (uint256 rate) {
        uint256 utilization = getCyclePoolUtilization();
        return poolStrategy.calculateInterestRate(utilization);
    }

    /**
     * @notice Calculate pool utilization ratio
     * @return utilization Pool utilization as a percentage (scaled by 10000)
     */
    function getPoolUtilization() public view returns (uint256 utilization) {
        uint256 totalLiquidity = poolLiquidityManager.totalLPLiquidityCommited();
        if (totalLiquidity == 0) return 0;
        uint256 utilisedLiquidity = getUtilisedLiquidity();
        
        return Math.min((utilisedLiquidity * BPS) / totalLiquidity, BPS);
    }

    /**
     * @notice Calculate pool utilization ratio (including cycle changes)
     * @dev This function gives the expected utilization for the next cycle
     * @dev It takes into account the new deposits, redemptions & liquidity changes in the cycle
     * @return utilization Pool utilization as a percentage (scaled by 10000)
     */    
    function getCyclePoolUtilization() public view returns (uint256 utilization) {
        uint256 cycleTotalLiquidity = poolLiquidityManager.getCycleTotalLiquidityCommited();
        if (cycleTotalLiquidity == 0) return 0;
        uint256 cycleUtilisedLiquidity = getCycleUtilisedLiquidity();
        
        return Math.min((cycleUtilisedLiquidity * BPS) / cycleTotalLiquidity, BPS);
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
     * @notice Calculate utilised liquidity (including cycle changes)
     * @dev This function gives the expected utilised liquidity for the next cycle
     * @dev It takes into account the new deposits, redemptions & liquidity changes in the cycle
     * @return cycleUtilisedLiquidity Total utilised liquidity
     */
    function getCycleUtilisedLiquidity() public view returns (uint256) {      
        (uint256 healthyRatio, , ) = poolStrategy.getLPLiquidityParams();
        uint256 totalRatio = BPS + healthyRatio;
        uint256 utilisedLiquidity = getUtilisedLiquidity();
        uint256 cycleRedemtionsInReserveToken = Math.mulDiv(cycleTotalRedemptions, assetOracle.assetPrice(), PRECISION * reserveToAssetDecimalFactor);
        uint256 nettChange = 0;
        uint256 cycleUtilisedLiquidity = 0;
        if (cycleTotalDeposits > cycleRedemtionsInReserveToken) {
            nettChange = cycleTotalDeposits - cycleRedemtionsInReserveToken;
            nettChange = Math.mulDiv(nettChange, totalRatio, BPS);
            cycleUtilisedLiquidity = utilisedLiquidity + nettChange;
        } else {
            nettChange = cycleRedemtionsInReserveToken - cycleTotalDeposits;
            nettChange = Math.mulDiv(nettChange, totalRatio, BPS);
            cycleUtilisedLiquidity = utilisedLiquidity - nettChange;
        }
        
        return cycleUtilisedLiquidity;
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
     * @notice Transfers rebalance amount from the pool to the LP during negative rebalance
     * @param lp Address of the LP to whom rebalance amount is owed
     * @param amount Amount of reserve tokens to transfer to the LP
     */
    function transferRebalanceAmount(address lp, uint256 amount) external onlyPoolCycleManager {
        if (amount == 0) revert InvalidAmount();

        // Check if we have enough reserve tokens for the transfer
        uint256 reserveBalance = reserveToken.balanceOf(address(this));
        if (reserveBalance < amount) revert InsufficientBalance();

        // Transfer the rebalance amount to the LP
        reserveToken.transfer(lp, amount);
        
        emit RebalanceAmountTransferred(lp, amount, poolCycleManager.cycleIndex());
    }

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
            + cycleTotalDeposits
            - Math.mulDiv(cycleTotalRedemptions, rebalancePrice, PRECISION * reserveToAssetDecimalFactor);

        if (rebalanceAmount > 0) {
            poolReserveBalance += uint256(rebalanceAmount);
        } else if (rebalanceAmount < 0) {
            poolReserveBalance -= uint256(-rebalanceAmount);
        }

        if (assetBalance > 0) {
            assetToken.burn(address(this), assetBalance, reserveBalanceInAssetToken);
        }

        cycleTotalDeposits = 0;
        cycleTotalRedemptions = 0;
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
     * @return requestType Type of request
     * @return amount Amount involved in the request
     * @return collateralAmount Collateral amount involved in the request
     * @return requestCycle Cycle when request was made
     */
    function userRequest(address user) external view returns (
        RequestType requestType,
        uint256 amount,
        uint256 collateralAmount,
        uint256 requestCycle
    ) {
        UserRequest storage request = userRequests[user];
        return (request.requestType, request.amount, request.collateralAmount, request.requestCycle);
    }

    /**
     * @notice Calculate redemption values based on asset amount
     * @param user Address of the user
     * @param assetAmount Amount of asset tokens to redeem
     * @param rebalancePrice Price at which redemption occurs
     * @return reserveAmount Equivalent reserve tokens for the asset amount
     * @return collateralAmount Collateral amount to return
     * @return scaledAssetAmount Asset amount scaled by pool interest
     * @return interestDebt Interest debt converted to reserve tokens
    */
    function _calculateRedemptionValues(
        address user,
        uint256 assetAmount,
        uint256 rebalancePrice
    ) internal view returns (
        uint256 reserveAmount,
        uint256 collateralAmount,
        uint256 scaledAssetAmount,
        uint256 interestDebt
    ) {
        // Convert asset to reserve using rebalance price
        reserveAmount = Math.mulDiv(
            assetAmount, 
            rebalancePrice, 
            PRECISION * reserveToAssetDecimalFactor
        );
        
        // Get pool interest for scaling
        uint256 poolInterest = poolCycleManager.cumulativePoolInterest();
        
        // Get user's position
        UserPosition storage position = userPositions[user];
        uint256 positionAssetAmount = position.assetAmount;
        uint256 collateralAmount = position.collateralAmount;
        uint256 scaledAssetAmount = scaledAssetBalance[user];
        
        uint256 userInterestDebt = getInterestDebt(user);
        // Calculate interest debt in reserve tokens
        interestDebt = Math.mulDiv(userInterestDebt, rebalancePrice, PRECISION * reserveToAssetDecimalFactor);
        
        // If partial redemption, calculate proportional interest debt
        if (positionAssetAmount > assetAmount) {
            interestDebt = Math.mulDiv(interestDebt, assetAmount, positionAssetAmount);
            collateralAmount = Math.mulDiv(collateralAmount, assetAmount, positionAssetAmount);
            scaledAssetAmount = Math.mulDiv(scaledAssetAmount, assetAmount, positionAssetAmount);
        }
        
        return (reserveAmount, collateralAmount, scaledAssetAmount, interestDebt);
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

    /**
     * @notice Returns the liquidation initiator for a user
     * @param user Address of the user
     * @return Address of the liquidation initiator
     */
    function getUserLiquidationIntiator(address user) external view returns (address) {
        return liquidationInitiators[user];
    }

}