// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;

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
contract AssetPool is IAssetPool, PoolStorage, ReentrancyGuard {
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
     * @notice Total active user deposits
     */
    uint256 public totalUserDeposits;

    /**
     * @notice Total active user collateral
     */
    uint256 public totalUserCollateral;

    /**
     * @notice Amount of reserve tokens backing the asset token
     */
    uint256 public reserveBackingAsset;

    /**
     * @notice Current reserve balance of the pool (including rebalance amount, collateral, interestDebt).
     */
    uint256 public aggregatePoolReserves;

    /**
     * @notice Yield accrued  by the pool reserve tokens (if isYieldBearing)
     */
    uint256 public reserveYieldAccrued;

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
    constructor() {
        // Disable implementation initializers
        _disableInitializers();
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
     */
    function initialize(
        address _reserveToken,
        string memory _assetTokenSymbol,
        address _assetOracle,
        address _poolCycleManager,
        address _poolLiquidityManager,
        address _poolStrategy
    ) external initializer {
        if (_reserveToken == address(0) || _assetOracle == address(0) || 
            _poolLiquidityManager == address(0) || _poolCycleManager == address(0)) 
            revert ZeroAddress();

        poolCycleManager =IPoolCycleManager(_poolCycleManager);
        reserveToken = IERC20Metadata(_reserveToken);
        assetToken = new xToken(_assetTokenSymbol, _assetTokenSymbol, _poolCycleManager);
        poolLiquidityManager = IPoolLiquidityManager(_poolLiquidityManager);
        assetOracle = IAssetOracle(_assetOracle);
        poolStrategy = IPoolStrategy(_poolStrategy);
        reserveYieldAccrued = 1e18;

        _initializeDecimalFactor(address(reserveToken), address(assetToken));

    }

    // --------------------------------------------------------------------------------
    //                           USER COLLATERAL FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Allows users to deposit additional collateral
     * @param user Address of the user
     * @param amount Amount of collateral to deposit
     */
    function addCollateral(address user, uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();

        UserPosition storage position = userPositions[user];
        
        _handleDeposit(user, amount);

        // Update user's position
        position.collateralAmount += amount;
        totalUserCollateral += amount;
        aggregatePoolReserves += amount;

        UserRequest storage request = userRequests[user];
        if (request.requestType == RequestType.LIQUIDATE 
            && poolCycleManager.cycleState() == IPoolCycleManager.CycleState.POOL_ACTIVE) {

            uint256 collateralHealth = poolStrategy.getUserCollateralHealth(address(this), user);
            if (collateralHealth == 3) {
                uint256 requestAmount = request.amount;
                address liquidationInitiator = liquidationInitiators[user];
                // Cancel liquidation request if collateral is added
                cycleTotalRedemptions -= requestAmount;
                // Refund the liquidator's tokens
                assetToken.transfer(liquidationInitiator, requestAmount);

                delete userRequests[user];
                delete liquidationInitiators[user];

                emit LiquidationCancelled(user, liquidationInitiator, requestAmount);
            }
        }
        
        emit CollateralDeposited(user, amount);
    }

    /**
     * @notice Allows users to withdraw excess collateral
     * @param amount Amount of collateral to withdraw
     */
    function reduceCollateral(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        
        UserPosition storage position = userPositions[msg.sender];
        uint256 collateral = position.collateralAmount;
        if (collateral < amount) revert InsufficientBalance();
        
        // Calculate required collateral
        uint256 requiredCollateral = poolStrategy.calculateUserRequiredCollateral(address(this), msg.sender);
        uint256 excessCollateral = 0;
        
        if (collateral > requiredCollateral) {
            excessCollateral = collateral - requiredCollateral;
        }
        
        if (amount > excessCollateral) revert ExcessiveWithdrawal();

        uint256 reserveYield = _handleWithdrawal(msg.sender, amount, position);
        
        // Update user's position
        position.collateralAmount -= amount;
        totalUserCollateral -= amount;
        aggregatePoolReserves -= amount;
        
        // Transfer collateral to user
        reserveToken.transfer(msg.sender, amount + reserveYield);
        
        emit CollateralWithdrawn(msg.sender, amount + reserveYield);
    }

    // --------------------------------------------------------------------------------
    //                           USER REQUEST FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Process a deposit request
     * @param amount Amount of reserve tokens to deposit
     * @param collateralAmount Amount of collateral to provide
     */
    function depositRequest(uint256 amount, uint256 collateralAmount) external nonReentrant {
        _requireActivePool();
        if (amount == 0) revert InvalidAmount();
        if (collateralAmount == 0) revert InvalidAmount();
        
        UserRequest storage request = userRequests[msg.sender];
        if (request.amount > 0) revert RequestPending();

        // Check if pool has enough liquidity to accept the deposit
        uint256 availableLiquidity = poolStrategy.calculateCycleAvailableLiquidity(address(this));

        uint256 currentCycle = poolCycleManager.cycleIndex();

        if (availableLiquidity < amount) revert InsufficientLiquidity();

        uint256 healthyRatio = poolStrategy.userHealthyCollateralRatio();
        
        // Calculate minimum required collateral & ensure provided collateral meets minimum requirement
        if (collateralAmount < Math.mulDiv(amount, healthyRatio, BPS)) revert InsufficientCollateral();

        uint256 totalDeposit = amount + collateralAmount;

        _handleDeposit(msg.sender, totalDeposit);
        
        // Update request state
        request.requestType = RequestType.DEPOSIT;
        request.amount = amount;
        request.collateralAmount = collateralAmount;
        request.requestCycle = currentCycle;
        cycleTotalDeposits += amount;

        // Update total user deposits and collateral
        totalUserDeposits += amount;
        totalUserCollateral += collateralAmount;
        aggregatePoolReserves += totalDeposit;
        
        emit DepositRequested(msg.sender, amount, currentCycle);
    }

    /**
     * @notice Process a redemption request
     * @param amount Amount of asset tokens to redeem
     */
    function redemptionRequest(uint256 amount) external nonReentrant {
        _requireActivePool();
        if (amount == 0) revert InvalidAmount();

        UserPosition memory position = userPositions[msg.sender];
        if (position.assetAmount < amount || assetToken.balanceOf(msg.sender) < amount)
            revert InsufficientBalance();
        
        UserRequest storage request = userRequests[msg.sender];
        if (request.requestType != RequestType.NONE) revert RequestPending();

        uint256 currentCycle = poolCycleManager.cycleIndex();
        
        // Transfer asset tokens from user to pool
        assetToken.transferFrom(msg.sender, address(this), amount);
        
        // Update request state
        request.requestType = RequestType.REDEEM;
        request.amount = amount;
        request.requestCycle = currentCycle;
        cycleTotalRedemptions += amount;
        
        emit RedemptionRequested(msg.sender, amount, currentCycle);
    }

    /**
     * @notice Initiates a liquidation request for an underwater position
     * @param user Address of the user whose position is to be liquidated
     * @param amount Amount of asset to liquidate (must be <= 30% of user's position)
     */
    function liquidationRequest(address user, uint256 amount) external nonReentrant {
        _requireActivePool();
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
        
        uint256 currentCycle = poolCycleManager.cycleIndex();
        // Transfer xTokens from liquidator to pool
        assetToken.transferFrom(msg.sender, address(this), amount);
        
        // Create the liquidation request
        request.requestType = RequestType.LIQUIDATE;
        request.amount = amount;
        request.requestCycle = currentCycle;

        // Store the liquidator's address
        liquidationInitiators[user] = msg.sender;
        
        cycleTotalRedemptions += amount;
        
        emit LiquidationRequested(user, msg.sender, amount, currentCycle);
    }

    /**
     * @notice Claim asset tokens after a deposit request
     * @param user Address of the user
     */
    function claimAsset(address user) external nonReentrant {
        _requireActiveOrHaltedPool();
        UserRequest storage request = userRequests[user];
        uint256 amount = request.amount;
        uint256 collateralAmount = request.collateralAmount;
        uint256 requestCycle = request.requestCycle;
        
        if (requestCycle >= poolCycleManager.cycleIndex()) revert NothingToClaim();
        if (request.requestType != RequestType.DEPOSIT) revert NothingToClaim();
        
        // Get the rebalance price from the pool cycle manager
        uint256 rebalancePrice = poolCycleManager.cycleRebalancePrice(requestCycle);
        uint256 poolInterest = poolCycleManager.cyclePoolInterest(requestCycle);
        
        // Clear request
        delete userRequests[user];

        UserPosition storage position = userPositions[user];
        
        uint256 assetAmount = _convertReserveToAsset(amount, rebalancePrice);
        uint256 scaledAssetAmount = Math.mulDiv(assetAmount, PRECISION, poolInterest);

        // Update user's position
        position.assetAmount += assetAmount;
        position.depositAmount += amount;
        position.collateralAmount += collateralAmount;
        scaledAssetBalance[user] += scaledAssetAmount;
        
        // Mint tokens
        assetToken.mint(user, assetAmount);
        
        emit AssetClaimed(user, assetAmount, requestCycle);
    }

    /**
     * @notice Claim reserve tokens after a redemption request or liquidation request
     * @param user Address of the user
     */
    function claimReserve(address user) external nonReentrant {
        _requireActiveOrHaltedPool();
        UserRequest storage request = userRequests[user];
        RequestType requestType = request.requestType;
        uint256 amount = request.amount;
        uint256 requestCycle = request.requestCycle;
        
        if (requestCycle >= poolCycleManager.cycleIndex()) revert NothingToClaim();
        if (requestType != RequestType.REDEEM && requestType != RequestType.LIQUIDATE) revert NothingToClaim();
        
        // Get the rebalance price from the pool cycle manager
        uint256 rebalancePrice = poolCycleManager.cycleRebalancePrice(requestCycle);
        
        // Clear request
        delete userRequests[user];

        UserPosition storage position = userPositions[user];
        
        RedemptionValues memory r = _calculateRedemptionValues(user, amount, rebalancePrice, requestCycle);

        uint256 totalAmount = r.reserveAmount + r.collateralAmount;

        uint256 reserveYield = _handleWithdrawal(user, totalAmount, position);

        totalAmount += reserveYield;

        if(position.assetAmount == amount) {
            delete userPositions[user];
            scaledAssetBalance[user] = 0;
        } else {
            position.assetAmount -= amount;
            position.depositAmount -= r.depositAmount;
            position.collateralAmount -= r.collateralAmount;
            scaledAssetBalance[user] -= r.scaledAssetAmount;
        }

        totalAmount -= r.interestDebt;

        // Update total user deposits and collateral
        totalUserDeposits -= r.depositAmount;
        totalUserCollateral -= r.collateralAmount;
        aggregatePoolReserves = _safeSubtract(aggregatePoolReserves, totalAmount);

        // Transfer reserve tokens
        if (requestType == RequestType.REDEEM) {
           _safeTransferBalance(user, totalAmount);
        } else if (requestType == RequestType.LIQUIDATE) {
            // Liquidation case - transfer reserve tokens to the liquidator
            address liquidator = liquidationInitiators[user];
            if (liquidator == address(0)) revert InvalidLiquidationRequest();
            _safeTransferBalance(liquidator, totalAmount);
            // Clear liquidation initiator
            delete liquidationInitiators[user];

            emit LiquidationClaimed(user, liquidator, amount, totalAmount, r.collateralAmount);
        }
        
        emit ReserveWithdrawn(user, totalAmount, requestCycle);
    }

    /**
     * @notice When pool is halted exit the pool
     * @param amount Amount of the asset tokens to burn
     */
    function exitPool(uint256 amount) external nonReentrant {
        _requireHaltedPool();
        if (amount == 0) revert InvalidAmount();
        UserRequest memory request = userRequests[msg.sender];
        if (request.requestType != RequestType.NONE) revert RequestPending();
        UserPosition storage position = userPositions[msg.sender];
        if (position.assetAmount < amount) revert InsufficientBalance();
        
        uint256 userBalance = assetToken.balanceOf(msg.sender);
        if (userBalance < amount) revert InsufficientBalance();

        assetToken.burn(msg.sender, amount);

        uint256 cycle = poolCycleManager.cycleIndex() - 1;
        // Get the rebalance price from the pool cycle manager
        uint256 rebalancePrice = poolCycleManager.cycleRebalancePrice(cycle);

        RedemptionValues memory r = _calculateRedemptionValues(msg.sender, amount, rebalancePrice, cycle);

        uint256 totalAmount = r.reserveAmount + r.collateralAmount;

        uint256 reserveYield = _handleWithdrawal(msg.sender, totalAmount, position);

        totalAmount += reserveYield;

        if(position.assetAmount == amount) {
            delete userPositions[msg.sender];
            scaledAssetBalance[msg.sender] = 0;
        } else {
            position.assetAmount -= amount;
            position.depositAmount -= r.depositAmount;
            position.collateralAmount -= r.collateralAmount;
            scaledAssetBalance[msg.sender] -= r.scaledAssetAmount;
        }
        // Update total user deposits and collateral
        totalUserDeposits -= r.depositAmount;
        totalUserCollateral -= r.collateralAmount;
        totalAmount -= r.interestDebt;
        aggregatePoolReserves = _safeSubtract(aggregatePoolReserves, totalAmount);

        _safeTransferBalance(msg.sender, totalAmount);

        emit ReserveWithdrawn(msg.sender, totalAmount, cycle);
    }


    // --------------------------------------------------------------------------------
    //                            INTEREST MANAGEMENT
    // --------------------------------------------------------------------------------

    /**
     * @notice Get interest debt for a user (in asset tokens)
     * @param user User address
     * @param cycle Cycle index
     * @return interestDebt Amount of interest debt in reserve tokens
     */
    function getInterestDebt(address user, uint256 cycle) public view returns (uint256 interestDebt) {
        UserPosition storage position = userPositions[user];
        uint256 assetAmount = position.assetAmount;
        uint256 scaledAssetAmount = scaledAssetBalance[user];
        if (assetAmount == 0) return 0;

        uint256 cycleInterest = poolCycleManager.cyclePoolInterest(cycle);
        uint256 assetWithInterest = Math.mulDiv(scaledAssetAmount, cycleInterest, PRECISION);
        if(assetWithInterest < assetAmount) return 0;

        return assetWithInterest - assetAmount;
    }

    /**
     * @notice Calculate pool value
     * @return value Pool value in reserve tokens
     */
    function getPoolValue() public view returns (uint256 value) {
        uint256 prevCycle = poolCycleManager.cycleIndex() - 1;
        uint256 assetSupply = assetToken.totalSupply();
        uint256 assetPrice = poolCycleManager.cycleRebalancePrice(prevCycle);

        return _convertAssetToReserve(assetSupply, assetPrice);
    }

    // --------------------------------------------------------------------------------
    //                               EXTERNAL FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @notice Transfers rebalance amount from the pool to the LP during negative rebalance
     * @param lp Address of the LP to whom rebalance amount is owed
     * @param amount Amount of reserve tokens to transfer to the LP
     * @param isSettle Boolean If the function is called during settlement
     */
    function transferRebalanceAmount(address lp, uint256 amount, bool isSettle) external {
        _requirePoolCycleManager();
        if (amount == 0) revert InvalidAmount();

        // Check if we have enough reserve tokens for the transfer
        uint256 reserveBalance = reserveToken.balanceOf(address(this));
        if (reserveBalance < amount) revert InsufficientBalance();
        aggregatePoolReserves -= amount;

        if (isSettle) {
            poolLiquidityManager.addToCollateral(lp, amount);    
            // Transfer the rebalance amount to the liquidity manager
            reserveToken.transfer(address(poolLiquidityManager), amount);  
        } else {
            // Transfer the rebalance amount to the LP
            reserveToken.transfer(lp, amount);
        }
    }

    /**
     * @notice Deducts interest from the pool and transfers it to the liquidity manager
     * @param lp Address of the LP to whom interest is owed
     * @param amount Amount of interest to deduct
     * @param isSettle Boolean If the function is called during settlement
     */
    function deductInterest(address lp, uint256 amount, bool isSettle) external {
        _requirePoolCycleManager();
        if (amount == 0) revert InvalidAmount();

        // Check if we have enough reserve tokens for the interest
        uint256 reserveBalance = reserveToken.balanceOf(address(this));

        if(reserveBalance < amount) revert InsufficientBalance();

        aggregatePoolReserves -= amount;

       if (isSettle) {
            // During settlement, all interest goes to the protocol as penalty
            reserveToken.transfer(poolStrategy.feeRecipient(), amount);
            emit FeeDeducted(lp, amount);
        } else {
            uint256 lpCycleInterest = _deductProtocolFee(lp, amount);
            poolLiquidityManager.addToInterest(lp, lpCycleInterest);
            // Transfer remaining interest to liquidity manager for the LP
            reserveToken.transfer(address(poolLiquidityManager), lpCycleInterest);
        }
    }

    /**
     * @notice Update cycle data at the end of a cycle
     */
    function updateCycleData(uint256 rebalancePrice, int256 rebalanceAmount) external {
        _requirePoolCycleManager();
        uint256 assetBalance = assetToken.balanceOf(address(this));
        reserveBackingAsset = reserveBackingAsset 
            + cycleTotalDeposits
            - _convertAssetToReserve(cycleTotalRedemptions, rebalancePrice);

        if (rebalanceAmount > 0) {
            reserveBackingAsset += uint256(rebalanceAmount);
            aggregatePoolReserves += uint256(rebalanceAmount);
        } else if (rebalanceAmount < 0) {
            reserveBackingAsset -= uint256(-rebalanceAmount);
            aggregatePoolReserves -= uint256(-rebalanceAmount);
        }

        if (assetBalance > 0) {
            assetToken.burn(address(this), assetBalance);
        }

        cycleTotalDeposits = 0;
        cycleTotalRedemptions = 0;
    }

    // --------------------------------------------------------------------------------
    //                               INTERNAL FUNCTIONS
    // --------------------------------------------------------------------------------

    /**
     * @dev Checks if the caller is the pool cycle manager
     * @dev Use at the beginning of functions that should only be called by the cycle manager
     */
    function _requirePoolCycleManager() internal view {
        if (msg.sender != address(poolCycleManager)) revert NotPoolCycleManager();
    }

    /**
     * @dev Checks if the cycle state is active
     * @dev Use at the beginning of functions that should only execute in active pool state
     */
    function _requireActivePool() internal view {
        if (poolCycleManager.cycleState() != IPoolCycleManager.CycleState.POOL_ACTIVE) revert("Pool not active");
    }

    /**
     * @dev Checks if the cycle state is halted
     * @dev Use at the beginning of functions that should only execute in halted pool state
     */
    function _requireHaltedPool() internal view {
        if (poolCycleManager.cycleState() != IPoolCycleManager.CycleState.POOL_HALTED) revert("Pool not halted");
    }

    /**
     * @dev Checks if the cycle state is active or halted
     * @dev Use at the beginning of functions that can execute in either active or halted pool state
     */
    function _requireActiveOrHaltedPool() internal view {
        IPoolCycleManager.CycleState state = poolCycleManager.cycleState();
        if (state != IPoolCycleManager.CycleState.POOL_ACTIVE && state != IPoolCycleManager.CycleState.POOL_HALTED) {
            revert("Pool not active or halted");
        }
    }

    /**
     * @notice Handle deposit for reserve tokens
     * @param user Address of the user depositing
     * @param amount Amount being deposited
     */
    function _handleDeposit(address user, uint256 amount) internal {
        if (poolStrategy.isYieldBearing()) {
            uint256 reserveBalanceBefore = reserveToken.balanceOf(address(this));
            // Transfer collateral from user to this contract
            reserveToken.transferFrom(user, address(this), amount);
            
            uint256 yieldAccrued = poolStrategy.calculateYieldAccrued(
                aggregatePoolReserves, 
                reserveBalanceBefore,
                totalUserDeposits + totalUserCollateral
            );
            
            // Use multiplication to compound the yield, consistent with _accrueInterest
            reserveYieldAccrued = Math.mulDiv(reserveYieldAccrued, PRECISION + yieldAccrued, PRECISION);
            
            // Update scaled reserve balance for interest calculation
            scaledReserveBalance[user] += Math.mulDiv(amount, PRECISION, reserveYieldAccrued);
        } else {
            // Transfer collateral from user to this contract
            reserveToken.transferFrom(user, address(this), amount);
        }
    }

    /**
     * @notice Handle withdrawal for reserve tokens
     * @param user Address of the user withdrawing
     * @param amount Amount being withdrawn
     * @param position User's position data
     * @return reserveYield The calculated yield amount
    */
    function _handleWithdrawal(
        address user, 
        uint256 amount, 
        UserPosition memory position
    ) internal returns (uint256) {
        if (poolStrategy.isYieldBearing()){
            // Capture reserve balance before any transfers
            uint256 reserveBalanceBefore = reserveToken.balanceOf(address(this));
            
            uint256 yieldAccrued = poolStrategy.calculateYieldAccrued(
                aggregatePoolReserves,
                reserveBalanceBefore,
                totalUserDeposits + totalUserCollateral
            );
            
            // Use multiplication to compound the yield, consistent with _accrueInterest
            reserveYieldAccrued = Math.mulDiv(reserveYieldAccrued, PRECISION + yieldAccrued, PRECISION);
            
            // Update scaled reserve balance for interest calculation
            uint256 scaledBalance = Math.mulDiv(
                scaledReserveBalance[user],
                amount,
                position.depositAmount + position.collateralAmount
            );
            
            scaledReserveBalance[user] -= scaledBalance;
            uint256 reserveYield = _safeSubtract(Math.mulDiv(scaledBalance, reserveYieldAccrued, PRECISION), amount);
            
            // Deduct protocol fee from the yield
            return _deductProtocolFee(user, reserveYield);
        } else {
            return 0;
        }
    }

    /**
     * @notice Calculate redemption values based on asset amount
     * @param user Address of the user
     * @param assetAmount Amount of asset tokens to redeem
     * @param rebalancePrice Price at which redemption occurs
     * @param requestCycle Cycle when the request was made
     * @return RedemptionValues Struct containing redemption values
    */
    function _calculateRedemptionValues(
        address user,
        uint256 assetAmount,
        uint256 rebalancePrice,
        uint256 requestCycle
    ) internal view returns (RedemptionValues memory) {

        RedemptionValues memory r;
        // Convert asset to reserve using rebalance price
        r.reserveAmount = _convertAssetToReserve(assetAmount, rebalancePrice);
        
        // Get user's position
        UserPosition storage position = userPositions[user];
        uint256 positionAssetAmount = position.assetAmount;
        r.depositAmount = position.depositAmount;
        r.collateralAmount = position.collateralAmount;
        r.scaledAssetAmount = scaledAssetBalance[user];
        
        r.interestDebt = getInterestDebt(user, requestCycle);
        // Calculate interest debt in reserve tokens
        r.interestDebt = _convertAssetToReserve(r.interestDebt, rebalancePrice);
        
        // If partial redemption, calculate proportional interest debt
        if (positionAssetAmount > assetAmount) {
            r.interestDebt = Math.mulDiv(r.interestDebt, assetAmount, positionAssetAmount);
            r.depositAmount = Math.mulDiv(r.depositAmount, assetAmount, positionAssetAmount);
            r.collateralAmount = Math.mulDiv(r.collateralAmount, assetAmount, positionAssetAmount);
            r.scaledAssetAmount = Math.mulDiv(r.scaledAssetAmount, assetAmount, positionAssetAmount);
        }
        
        return r;
    }

    /**
     * @notice Deduct protocol fee
     * @param user Address of the user
     * @param amount Amount on which the fee needs to be deducted
     */
    function _deductProtocolFee(address user, uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;
        uint256 protocolFee = poolStrategy.protocolFee();
        uint256 protocolFeeAmount = (protocolFee > 0) ? Math.mulDiv(amount, protocolFee, BPS) : 0;
            
        if (protocolFeeAmount > 0) {   
            reserveToken.transfer(poolStrategy.feeRecipient(), protocolFeeAmount);
            emit FeeDeducted(user, protocolFeeAmount);
        }

        return amount - protocolFeeAmount;
    }

    /**
     * @notice Safely transfers the balance of reserve to a specified address
     * @param to Address to which the tokens will be transferred
     * @param amount Amount of tokens to transfer
     */
    function _safeTransferBalance(address to, uint256 amount) internal {
        uint256 balance = reserveToken.balanceOf(address(this));
        uint256 transferAmount = balance < amount ? balance : amount;
        reserveToken.transfer(to, transferAmount);
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