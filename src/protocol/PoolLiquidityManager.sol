// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {IAssetPool} from "../interfaces/IAssetPool.sol";
import {IAssetOracle} from "../interfaces/IAssetOracle.sol";
import {IXToken} from "../interfaces/IXToken.sol";
import {IPoolCycleManager} from "../interfaces/IPoolCycleManager.sol";
import {IPoolLiquidityManager} from "../interfaces/IPoolLiquidityManager.sol";
import {IPoolStrategy} from "../interfaces/IPoolStrategy.sol";
import {PoolStorage} from "./PoolStorage.sol";

/**
 * @title PoolLiquidityManager
 * @notice Manages LP liquidity requirements and registry for the asset pool
 */
contract PoolLiquidityManager is IPoolLiquidityManager, PoolStorage, ReentrancyGuard, Multicall {
    
    // Total liquidity committed by LPs
    uint256 public totalLPLiquidityCommited;

    // Total lp collateral
    uint256 public totalLPCollateral;

    // Combined reserve balance of the liquidity manager (including collateral and interest)
    uint256 public aggregatePoolReserves;
    
    // Number of registered LPs
    uint256 public lpCount;

    // Add liquidity requests for the current cycle
    uint256 public cycleTotalAddLiquidityAmount;

    // Reduce liquidity requests for the current cycle
    uint256 public cycleTotalReduceLiquidityAmount;

    // Mapping to track LP requests
    mapping(address => LPRequest) private lpRequests;

    // Mapping of LP addresses to their liquidity positions
    mapping(address => LPPosition) private lpPositions;
    
    // Mapping to check if an address is a registered LP
    mapping(address => bool) public registeredLPs;

    // Mapping to track liquidation initiators
    mapping(address => address) public liquidationInitiators;

    // Yield accrued  by the pool reserve tokens (if isYieldBearing)
    uint256 public reserveYieldAccrued;

    // Scaled reserve balance of an LP
    mapping(address => uint256) public scaledReserveBalance;

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
     * @dev Ensures the caller is the asset pool
     */
    modifier onlyAssetPool() {
        if (msg.sender != address(assetPool)) revert NotAssetPool();
        _;
    }

    /**
     * @notice Modifier to ensure the caller is a registered LP
     */
    modifier onlyRegisteredLP() {
        if (!registeredLPs[msg.sender]) revert NotRegisteredLP();
        _;
    }

    /**
     * @dev Empty constructor
     * Used for the implementation contract only, not for clones
     */
    constructor() {
        // This disables initialization of the implementation contract
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract - replaces the constructor for clones
     * @param _reserveToken Address of the reserve token
     * @param _assetToken Address of the asset token
     * @param _assetOracle Address of the asset oracle
     * @param _assetPool Address of the asset pool
     * @param _poolCycleManager Address of the pool cycle manager
     * @param _poolStrategy Address of the pool strategy
     */
    function initialize(
        address _reserveToken,
        address _assetToken,
        address _assetOracle,
        address _assetPool,
        address _poolCycleManager,
        address _poolStrategy
    ) external initializer {
        if (_reserveToken == address(0) || _assetToken == address(0) || _assetPool == address(0) || 
            _poolCycleManager == address(0) || _assetOracle == address(0)) {
            revert ZeroAddress();
        }
            
        reserveToken = IERC20Metadata(_reserveToken);
        assetToken = IXToken(_assetToken);
        assetPool = IAssetPool(_assetPool);
        poolCycleManager = IPoolCycleManager(_poolCycleManager);
        poolStrategy = IPoolStrategy(_poolStrategy);
        assetOracle = IAssetOracle(_assetOracle);
        reserveYieldAccrued = 1e18;

        _initializeDecimalFactor(address(reserveToken), address(assetToken));
        
    }

    /**
     * @notice Add liquidity to the pool
     * @param amount The amount of liquidity to add
     */
    function addLiquidity(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();

        if (!_isPoolActive()) revert InvalidCycleState();
        // Calculate additional required collateral
        uint256 requiredCollateral = Math.mulDiv(amount, poolStrategy.lpHealthyCollateralRatio(), BPS);
        // Transfer required collateral
        reserveToken.transferFrom(msg.sender, address(this), requiredCollateral);

        uint8 collateralHealth = poolStrategy.getLPLiquidityHealth(address(this), msg.sender);
        if (collateralHealth < 3) revert InsufficientCollateralHealth(collateralHealth);

        LPPosition storage position = lpPositions[msg.sender]; 
        
        if (registeredLPs[msg.sender]) {
            LPRequest storage request = lpRequests[msg.sender];
            if (request.requestType != RequestType.NONE) revert RequestPending();              
        } else {
            registeredLPs[msg.sender] = true;
            lpCount++;

            emit LPAdded(msg.sender, amount, requiredCollateral);
        }

        if (poolStrategy.isYieldBearing()) {
            _updateScaledReserveBalance(msg.sender, requiredCollateral);
        }

        position.collateralAmount += requiredCollateral; 
        cycleTotalAddLiquidityAmount += amount;
        totalLPCollateral += requiredCollateral;
        aggregatePoolReserves += requiredCollateral;

        _createRequest(msg.sender, RequestType.ADD_LIQUIDITY, amount);

        emit LiquidityAdditionRequested(msg.sender, amount, poolCycleManager.cycleIndex());
    }

    /**
     * @notice Remove an lp's liquidity
     * @param amount The amount of liquidity to reduce
     */
    function reduceLiquidity(uint256 amount) external nonReentrant onlyRegisteredLP {
        if (amount == 0) revert InvalidAmount();

        if (!_isPoolActive()) revert InvalidCycleState();

        LPRequest storage request = lpRequests[msg.sender];
        if (request.requestType != RequestType.NONE) revert RequestPending();
        
        LPPosition storage position = lpPositions[msg.sender];
        if (amount > position.liquidityCommitment) revert InvalidAmount();

        // Alowed reduction is lower (50%) in case of normal reduction
        uint256 allowedReduction = calculateAvailableLiquidity() / 2;
        // Ensure there is available liquidity for the operation
        if (allowedReduction == 0) revert UtilizationTooHighForOperation();
        // Ensure reduction amount doesn't exceed allowed reduction
        if (amount > allowedReduction) revert OperationExceedsAvailableLiquidity(amount, allowedReduction);
        if (amount < allowedReduction) {
            allowedReduction = amount;
        }

        uint8 collateralHealth = poolStrategy.getLPLiquidityHealth(address(this), msg.sender);
        if (collateralHealth < 2) revert InsufficientCollateralHealth(collateralHealth);

        // Create the reduction request
        _createRequest(msg.sender, RequestType.REDUCE_LIQUIDITY, allowedReduction);
        
        cycleTotalReduceLiquidityAmount += amount;
        
        emit LiquidityReductionRequested(msg.sender, amount, poolCycleManager.cycleIndex());
    }

    /**
     * @notice Add additional collateral beyond the minimum
     * @param lp Address of the LP
     * @param amount Amount of collateral to deposit
     */
    function addCollateral(address lp, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        
        reserveToken.transferFrom(lp, address(this), amount);
        lpPositions[lp].collateralAmount += amount;

        if (poolStrategy.isYieldBearing()) {
            _updateScaledReserveBalance(lp, amount);
        }

        totalLPCollateral += amount;
        aggregatePoolReserves += amount;

        emit CollateralAdded(lp, amount);

        LPRequest storage request = lpRequests[lp];
        if (request.requestType == RequestType.LIQUIDATE && _isPoolActive()) {
            uint8 liquidityHealth = poolStrategy.getLPLiquidityHealth(address(this), lp);
            if (liquidityHealth == 3) {
                // Position is no longer liquidatable, cancel the liquidation request
                cycleTotalReduceLiquidityAmount -= request.requestAmount;
                delete liquidationInitiators[lp];
                request.requestType = RequestType.NONE;
                emit LiquidationCancelled(lp);
            }
        }
    }

    /**
     * @notice Remove excess collateral if above minimum requirements
     * @param amount Amount of collateral to reduce
     */
    function reduceCollateral(uint256 amount) external nonReentrant onlyRegisteredLP {
        LPPosition storage position = lpPositions[msg.sender];
        uint256 lpCollateral = position.collateralAmount;
        if (amount == 0 || amount > lpCollateral) revert InvalidWithdrawalAmount();
        
        uint256 requiredCollateral = poolStrategy.calculateLPRequiredCollateral(address(this), msg.sender);
        if (lpCollateral - amount < requiredCollateral) {
            revert InsufficientCollateral();
        }

        uint256 reserveYield = _calculateReserveYield(msg.sender, amount);
        
        position.collateralAmount -= amount;
        totalLPCollateral -= amount;
        aggregatePoolReserves -= amount;
        reserveToken.transfer(msg.sender, amount + reserveYield);
        
        emit CollateralReduced(msg.sender, amount + reserveYield);
    }

    /**
     * @notice Claim interest accrued on LP position
     */
    function claimInterest() external nonReentrant onlyRegisteredLP {
        LPPosition storage position = lpPositions[msg.sender];
        uint256 interestAccrued = position.interestAccrued;
        if (interestAccrued == 0) revert NoInterestAccrued();
        
        uint256 reserveYield = _calculateReserveYield(msg.sender, interestAccrued);

        position.interestAccrued = 0;
        aggregatePoolReserves -= interestAccrued;
        reserveToken.transfer(msg.sender, interestAccrued + reserveYield);
        
        emit InterestClaimed(msg.sender, interestAccrued + reserveYield);
    }

    /**
     * @notice Liquidate an LP below threshold 
     * @param lp Address of the LP to liquidate
     * @param liquidationAmount Amount of liquidity to liquidate
    */
    function liquidateLP(address lp, uint256 liquidationAmount) external nonReentrant {
        // Validate liquidation request
        _validateLiquidation(lp, liquidationAmount);

        // Create the liquidation request
        _createRequest(lp, RequestType.LIQUIDATE, liquidationAmount);

        // Store liquidator to reward them when request is resolved
        liquidationInitiators[lp] = msg.sender;

        cycleTotalReduceLiquidityAmount += liquidationAmount;

        emit LPLiquidationRequested(lp, poolCycleManager.cycleIndex(), liquidationAmount);
    }

    /**
     * @notice When the pool is halted exit pool
     */
    function exitPool() external nonReentrant onlyRegisteredLP {

        if (!_isPoolHalted()) revert InvalidCycleState();

        _removeLP(msg.sender);
    }

    /**
     * @notice Add interest amount to LP's position
     * @param lp Address of the LP
     * @param amount Amount to add
     */
    function addToInterest(address lp, uint256 amount) external onlyAssetPool {
        if (!registeredLPs[lp]) revert NotRegisteredLP();

        if (poolStrategy.isYieldBearing()) {
            _updateScaledReserveBalance(lp, amount);
        }
        
        lpPositions[lp].interestAccrued += amount;
        aggregatePoolReserves += amount;
    }

    /**
     * @notice Add rebalance amount to LP's position
     * @dev During settle pool, we use this to add the rebalance amount to LP's position
     * @param lp Address of the LP
     * @param amount Amount to add
     */
    function addToCollateral(address lp, uint256 amount) external onlyAssetPool {
        if (!registeredLPs[lp]) revert NotRegisteredLP();

        if (poolStrategy.isYieldBearing()) {
            _updateScaledReserveBalance(lp, amount);
        }
        
        lpPositions[lp].collateralAmount += amount;
        totalLPCollateral += amount;
        aggregatePoolReserves += amount;
    }

    /**
     * @notice Deduct collateral from LP's position
     * @dev This is used to deduct collateral during lp settlement
     * @param lp Address of the LP
     * @param amount Amount to deduct
     */
    function deductFromCollateral(address lp, uint256 amount) external onlyPoolCycleManager {
        if (!registeredLPs[lp]) revert NotRegisteredLP();
        
        LPPosition storage position = lpPositions[lp];
        if (position.collateralAmount < amount) revert InvalidAmount();

        uint256 reserveYield = _calculateReserveYield(lp, amount);

        position.collateralAmount -= amount;
        totalLPCollateral -= amount;
        aggregatePoolReserves -= amount;

        reserveToken.transfer(address(assetPool), amount + reserveYield);
    }

    /**
     * @notice Resolves an LP request after a rebalance cycle
     * @dev This should be called after a rebalance to clear pending request flags
     * @param lp Address of the LP
     */
    function resolveRequest(address lp) external onlyPoolCycleManager {
        if (!registeredLPs[lp]) revert NotRegisteredLP();
        
        LPRequest storage request = lpRequests[lp];
        LPPosition storage position = lpPositions[lp];

        if (request.requestType == RequestType.ADD_LIQUIDITY) {
            // Update LP position
            position.liquidityCommitment += request.requestAmount;
            emit LiquidityAdded(lp, request.requestAmount);

        } else if (request.requestType == RequestType.REDUCE_LIQUIDITY) {
            // Update LP position
            position.liquidityCommitment -= request.requestAmount;
            emit LiquidityReduced(lp, request.requestAmount);

            if(position.liquidityCommitment == 0) {
                _removeLP(lp);
            }
        } else if (request.requestType == RequestType.LIQUIDATE) {
            // Transfer liquidation reward to liquidator
            uint256 liquidationAmount = request.requestAmount;
            uint256 rewardAmount = Math.mulDiv(liquidationAmount, poolStrategy.lpLiquidationReward(), BPS);
            position.liquidityCommitment -= liquidationAmount;
            if (position.collateralAmount >= rewardAmount){
                position.collateralAmount -= rewardAmount;
                totalLPCollateral -= rewardAmount;
                aggregatePoolReserves -= rewardAmount;

                uint256 reserveYield = _calculateReserveYield(lp, rewardAmount);

                reserveToken.transfer(liquidationInitiators[lp], rewardAmount + reserveYield);
            }
            emit LPLiquidationExecuted(lp, liquidationInitiators[lp], liquidationAmount, rewardAmount);

            if(position.liquidityCommitment == 0) {
                _removeLP(lp);
            }
        }
        
        // Mark request as resolved
        request.requestType = RequestType.NONE;
    }

    /**
     * @notice Update cycle data at the end of a cycle
     */
    function updateCycleData() external onlyPoolCycleManager {
        totalLPLiquidityCommited += cycleTotalAddLiquidityAmount;
        totalLPLiquidityCommited -= cycleTotalReduceLiquidityAmount;
        // Reset cycle data
        cycleTotalAddLiquidityAmount = 0;
        cycleTotalReduceLiquidityAmount = 0;
    }

    /**
     * @notice Get the total nett liquidity committed by LPs (including cycle changes)
     * @return uint256 Total liquidity committed
     */
    function getCycleTotalLiquidityCommited() public view returns (uint256) {
        if (totalLPLiquidityCommited == 0) return 0;
        uint256 cycleTotalLiquidity = totalLPLiquidityCommited
            + cycleTotalAddLiquidityAmount
            - cycleTotalReduceLiquidityAmount;

        return cycleTotalLiquidity;
    }

    /**
     * @notice Calculate Lp's current asset holding value (in reserve token)
     * @param lp Address of the LP
     */
    function getLPAssetHoldingValue(address lp) public view returns (uint256) {
        if (!registeredLPs[lp]) return 0;
        
        uint256 poolValue = assetPool.getPoolValue();
        uint256 lpShare = getLPLiquidityShare(lp);

        uint256 lpAssetHolding = Math.mulDiv(lpShare, poolValue, PRECISION);
        
        return lpAssetHolding;
    }

    /**
     * @notice Get LP's current liquidity share of the pool
     * @param lp Address of the LP
     */
    function getLPLiquidityShare(address lp) public view returns (uint256) {
        if (!registeredLPs[lp]) return 0;
        // If no total liquidity, return 0
        if (totalLPLiquidityCommited == 0) return 0;
        return Math.mulDiv(lpPositions[lp].liquidityCommitment, PRECISION, totalLPLiquidityCommited);
    }

    /**
     * @notice Get LP's current asset share of the pool
     * @param lp Address of the LP
     */
    function getLPAssetShare(address lp) public view returns (uint256) {
        if (!registeredLPs[lp]) return 0;
        // If no total liquidity, return 0
        if (totalLPLiquidityCommited == 0) return 0;
        uint256 assetSupply = assetToken.totalSupply();
        return Math.mulDiv(assetSupply, lpPositions[lp].liquidityCommitment, totalLPLiquidityCommited);
    }
    
    /**
     * @notice Get LP's projected asset share after the current cycle completes based on expected rebalance price
     * @param lp Address of the LP
     * @param expectedRebalancePrice The expected rebalance price provided by the LP
     * @return LP's projected share of the asset supply after cycle completion
     */
    function getLPCycleAssetShare(address lp, uint256 expectedRebalancePrice) public view returns (uint256) {
        // If not a registered LP or no request pending, return current share
        if (!registeredLPs[lp]) return 0;
        // If rebalance price is zero, revert
        if (expectedRebalancePrice == 0) revert InvalidAmount();
        
        // Calculate the projected total liquidity after the cycle
        uint256 cycleTotalLiquidity = getCycleTotalLiquidityCommited();
        if (cycleTotalLiquidity == 0) return 0;
        
        // Calculate the LP's projected liquidity commitment after the cycle
        uint256 lpCycleLiquidity = lpPositions[lp].liquidityCommitment;
        LPRequest storage request = lpRequests[lp];
        
        // Adjust the LP's liquidity based on their pending request
        if (request.requestType == RequestType.ADD_LIQUIDITY) {
            lpCycleLiquidity += request.requestAmount;
        } else if (request.requestType == RequestType.REDUCE_LIQUIDITY || 
                request.requestType == RequestType.LIQUIDATE) {
            lpCycleLiquidity -= request.requestAmount;
        }
        
        // If LP will have zero liquidity after the cycle, return 0
        if (lpCycleLiquidity == 0) return 0;
        
        // Calculate the projected asset supply after the cycle
        // Need to consider both the current asset supply and cycle changes
        uint256 currentAssetSupply = assetToken.totalSupply();
        
        // Get deposits and redemptions from the asset pool
        uint256 cycleDeposits = assetPool.cycleTotalDeposits();
        uint256 cycleRedemptions = assetPool.cycleTotalRedemptions();
        
        // Convert deposits to asset tokens using the expected rebalance price
        uint256 depositAssetAmount = 0;
        if (cycleDeposits > 0 && expectedRebalancePrice > 0) {
            depositAssetAmount = _convertReserveToAsset(cycleDeposits, expectedRebalancePrice);
        }
        
        // Calculate projected asset supply
        uint256 projectedAssetSupply = currentAssetSupply + depositAssetAmount - cycleRedemptions;
        
        // Calculate the LP's share of the projected asset supply
        return Math.mulDiv(projectedAssetSupply, lpCycleLiquidity, cycleTotalLiquidity);
    }

    /**
     * @notice Get LP's projected asset share after the current cycle completes based on current oracle price
     * @param lp Address of the LP
     * @return LP's projected share of the asset supply after cycle completion
     */
    function getLPCycleAssetShare(address lp) public view returns (uint256) {
        return getLPCycleAssetShare(lp, assetOracle.assetPrice());
    }

    /**
     * @notice Get LP's current liquidity position
     * @param lp Address of the LP
     */
    function getLPPosition(address lp) public view returns (LPPosition memory) {
        return lpPositions[lp];
    }

    /**
     * @notice Get LP's current collateral amount
     * @param lp Address of the LP
     */
    function getLPCollateral(address lp) public view returns (uint256) {
        return lpPositions[lp].collateralAmount;
    }

    /**
     * @notice Get LP's current request
     * @param lp Address of the LP
     */
    function getLPRequest(address lp) public view returns (LPRequest memory) {
        return lpRequests[lp];
    }

    /**
     * @notice Get LP's current liquidation initiator
     * @param lp Address of the LP
     */
    function getLPLiquidationIntiator(address lp) public view returns (address) {
        return liquidationInitiators[lp];
    }

    /**
     * @notice Check if an address is a registered LP
     * @param lp The address to check
     * @return bool True if the address is a registered LP
     */
    function isLP(address lp) public view returns (bool) {
        return registeredLPs[lp];
    }
    
    /**
     * @notice Returns the number of LPs registered
     * @return uint256 The number of registered LPs
     */
    function getLPCount() public view returns (uint256) {
        return lpCount;
    }
    
    /**
     * @notice Returns the current liquidity commited by the LP
     * @param lp The address of the LP
     * @return uint256 The current liquidity amount
     */
    function getLPLiquidityCommitment(address lp) public view returns (uint256) {
        return lpPositions[lp].liquidityCommitment;
    }

    /**
     * @notice Returns the reserve to asset decimal factor
     */
    function getReserveToAssetDecimalFactor() public view returns (uint256) {
        return reserveToAssetDecimalFactor;
    }

    /**
     * @notice Check if the current cycle is active
     * @return True if the cycle is active, false otherwise
    */
    function _isPoolActive() internal view returns (bool) {
        return poolCycleManager.cycleState() == IPoolCycleManager.CycleState.POOL_ACTIVE;
    }

    /**
     * @notice Check if the pool is halted
     * @return True if the pool is halted, false otherwisw
    */
    function _isPoolHalted() internal view returns (bool) {
        return poolCycleManager.cycleState() == IPoolCycleManager.CycleState.POOL_HALTED;
    }

    /**
     * @notice Validate liquidation request
     * @param lp Address of the LP to liquidate
     * @param liquidationAmount Amount of liquidity to liquidate
     */
    function _validateLiquidation(address lp, uint256 liquidationAmount) internal view {
        if (!registeredLPs[lp] || lp == msg.sender) revert InvalidLiquidation();
        if (liquidationAmount == 0) revert InvalidAmount();

        if (!_isPoolActive()) revert InvalidCycleState();
    
        // Check if LP is liquidatable
        uint8 liquidityHealth = poolStrategy.getLPLiquidityHealth(address(this), lp);
        if (liquidityHealth != 1) revert NotEligibleForLiquidation();

        LPRequest storage request = lpRequests[lp];
        if (request.requestType != RequestType.NONE) revert RequestPending();

        // Get LP position details
        LPPosition storage position = lpPositions[lp];
        if (liquidationAmount > position.liquidityCommitment) revert InvalidAmount();
        
        // Allowed reduction is higher (75%) in case of liquidation
        uint256 allowedReduction = (calculateAvailableLiquidity() * 3) / 4;
        if (allowedReduction == 0) revert UtilizationTooHighForOperation();

        // Ensure liquidation amount doesn't exceed allowed reduction
        if (liquidationAmount > allowedReduction) {
            revert OperationExceedsAvailableLiquidity(liquidationAmount, allowedReduction);
        }
    }

    /**
     * @notice Internal function to finalize LP removal
     * @param lp Address of the LP to remove
     */
    function _removeLP(address lp) internal {
        LPPosition storage position = lpPositions[lp];

        if (position.collateralAmount > 0) {
            uint256 collateralAmount = position.collateralAmount;
            position.collateralAmount = 0;
            totalLPCollateral -= collateralAmount;
            aggregatePoolReserves -= collateralAmount;

            uint256 reserveYield = _calculateReserveYield(lp, collateralAmount);

            reserveToken.transfer(lp, collateralAmount + reserveYield);

            emit CollateralReduced(lp, collateralAmount);
        }
        
        // Transfer any remaining interest
        if (position.interestAccrued > 0) {
            uint256 interestAmount = position.interestAccrued;
            position.interestAccrued = 0;
            aggregatePoolReserves -= interestAmount;

            uint256 reserveYield = _calculateReserveYield(lp, interestAmount);

            reserveToken.transfer(lp, interestAmount + reserveYield);

            emit InterestClaimed(lp, interestAmount);
        }
        
        // Mark LP as removed
        registeredLPs[lp] = false;
        lpCount--;
        
        // Clean up storage
        delete lpPositions[lp];
        // We keep lpRequests for historical reference
        
        emit LPRemoved(lp);
    }

    /**
     * @notice Update scaled reserve balance
     * @param lp Address of the lp
     * @param amount Unscaled amount
     */
    function _updateScaledReserveBalance(address lp, uint256 amount) internal {
        reserveYieldAccrued += poolStrategy.calculateYieldAccrued(
            aggregatePoolReserves, 
            reserveToken.balanceOf(address(this)),
            aggregatePoolReserves
        );
        // Update scaled reserve balance for interest calculation
        scaledReserveBalance[lp] += Math.mulDiv(amount, PRECISION, reserveYieldAccrued);
    }

    /**
     * @notice Calculate reserve yield & update scaled reserve balance
     * @param lp Address of the lp
     * @param amount Unscaled amount
     */
    function _calculateReserveYield(address lp, uint256 amount) internal returns (uint256) {
        uint256 reserveYield = 0;
        LPPosition memory position = lpPositions[lp];

        if (poolStrategy.isYieldBearing()) {
            reserveYieldAccrued += poolStrategy.calculateYieldAccrued(
                aggregatePoolReserves, 
                reserveToken.balanceOf(address(this)),
                aggregatePoolReserves
            );
            // Update scaled reserve balance for interest calculation
            uint256 scaledBalance = Math.mulDiv(
                scaledReserveBalance[lp], 
                amount, 
                position.collateralAmount + position.interestAccrued
            );
            scaledReserveBalance[lp] -= scaledBalance;
            reserveYield = Math.mulDiv(scaledBalance, reserveYieldAccrued, PRECISION) - amount;
            reserveYield = _deductProtocolFee(lp, reserveYield);
        }
        return reserveYield;
    }

    /**
     * @notice Deduct protocol fee
     * @param lp Address of the lp
     * @param amount Amount on which the fee needs to be deducted
     */
    function _deductProtocolFee(address lp, uint256 amount) internal returns (uint256) {
        uint256 protocolFee = poolStrategy.protocolFee();
        uint256 protocolFeeAmount = (protocolFee > 0) ? Math.mulDiv(amount, protocolFee, BPS) : 0;
            
        if (protocolFeeAmount > 0) {   
            reserveToken.transfer(poolStrategy.feeRecipient(), protocolFeeAmount);
            emit FeeDeducted(lp, protocolFeeAmount);
        }

        return amount - protocolFeeAmount;
    }

    /**
     * @notice Calculate available liquidity for operations based on current utilization
     * @return availableLiquidity Maximum amount of liquidity available for operations
    */
    function calculateAvailableLiquidity() public view returns (uint256 availableLiquidity) {
        availableLiquidity =  getCycleTotalLiquidityCommited() - assetPool.getCycleUtilisedLiquidity();

        return availableLiquidity;
    }

    /**
     * @notice Create a new LP request
     * @param lp Address of the LP
     * @param requestType Type of request
     * @param amount Amount involved in the request
    */
    function _createRequest(address lp, RequestType requestType, uint256 amount) internal {
        LPRequest storage request = lpRequests[lp];
        
        request.requestType = requestType;
        request.requestAmount = amount;
        request.requestCycle = poolCycleManager.cycleIndex();
    }

}