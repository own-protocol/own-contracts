// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
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
contract PoolLiquidityManager is IPoolLiquidityManager, PoolStorage, ReentrancyGuard {
    
    // Total liquidity committed by LPs
    uint256 public totalLPLiquidityCommited;

    // Total lp collateral
    uint256 public totalLPCollateral;
    
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

        _initializeDecimalFactor(address(reserveToken), address(assetToken));
        
    }

    /**
     * @notice Add liquidity to the pool
     * @param amount The amount of liquidity to add
     */
    function addLiquidity(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();

        if (!_isCycleActive()) revert InvalidCycleState();

        (uint256 healthyRatio, ,) = poolStrategy.getLPLiquidityParams();
        // Calculate additional required collateral
        uint256 requiredCollateral = Math.mulDiv(amount, healthyRatio, BPS);
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

        position.collateralAmount += requiredCollateral; 
        cycleTotalAddLiquidityAmount += amount;
        totalLPCollateral += requiredCollateral;

        _createRequest(msg.sender, RequestType.ADD_LIQUIDITY, amount);

        emit LiquidityAdditionRequested(msg.sender, amount, poolCycleManager.cycleIndex());
    }

    /**
     * @notice Remove an lp's liquidity
     * @param amount The amount of liquidity to reduce
     */
    function reduceLiquidity(uint256 amount) external nonReentrant onlyRegisteredLP {
        if (amount == 0) revert InvalidAmount();

        if (!_isCycleActive()) revert InvalidCycleState();

        LPRequest storage request = lpRequests[msg.sender];
        if (request.requestType != RequestType.NONE) revert RequestPending();
        
        LPPosition storage position = lpPositions[msg.sender];
        if (amount > position.liquidityCommitment) revert InvalidAmount();

        // Calculate allowed reduction amount
        uint256 allowedReduction = calculateAvailableLiquidity() / 2;
        // Ensure there is available liquidity for the operation
        if (allowedReduction == 0) revert UtilizationTooHighForOperation();
        // Ensure reduction amount doesn't exceed allowed reduction
        if (amount > allowedReduction) revert OperationExceedsAvailableLiquidity(amount, allowedReduction);

        uint8 collateralHealth = poolStrategy.getLPLiquidityHealth(address(this), msg.sender);
        if (collateralHealth < 2) revert InsufficientCollateralHealth(collateralHealth);

        // Create the reduction request
        _createRequest(msg.sender, RequestType.REDUCE_LIQUIDITY, allowedReduction);
        
        cycleTotalReduceLiquidityAmount += amount;
        
        emit LiquidityReductionRequested(msg.sender, amount, poolCycleManager.cycleIndex());
    }

    /**
     * @notice Add additional collateral beyond the minimum
     * @param amount Amount of collateral to deposit
     */
    function addCollateral(uint256 amount) external nonReentrant onlyRegisteredLP {
        if (amount == 0) revert ZeroAmount();
        
        reserveToken.transferFrom(msg.sender, address(this), amount);
        lpPositions[msg.sender].collateralAmount += amount;

        totalLPCollateral += amount;
        uint8 liquidityHealth = poolStrategy.getLPLiquidityHealth(address(this), msg.sender);
        if (liquidityHealth == 1) revert InsufficientCollateralHealth(liquidityHealth);

        emit CollateralAdded(msg.sender, amount);

        LPRequest storage request = lpRequests[msg.sender];
        if (request.requestType == RequestType.LIQUIDATE && _isCycleActive()) {
            // Position is no longer liquidatable, cancel the liquidation request
            cycleTotalReduceLiquidityAmount -= request.requestAmount;
            delete liquidationInitiators[msg.sender];
            request.requestType = RequestType.NONE;
            emit LiquidationCancelled(msg.sender);
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
        
        position.collateralAmount -= amount;
        totalLPCollateral -= amount;
        reserveToken.transfer(msg.sender, amount);
        
        emit CollateralReduced(msg.sender, amount);
    }

    /**
     * @notice Claim interest accrued on LP position
     */
    function claimInterest() external nonReentrant onlyRegisteredLP {
        LPPosition storage position = lpPositions[msg.sender];
        uint256 interestAccrued = position.interestAccrued;
        if (interestAccrued == 0) revert NoInterestAccrued();
        
        position.interestAccrued = 0;
        reserveToken.transfer(msg.sender, interestAccrued);
        
        emit InterestClaimed(msg.sender, interestAccrued);
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
     * @notice Add interest amount to LP's position
     * @param lp Address of the LP
     * @param amount Amount to add
     */
    function addToInterest(address lp, uint256 amount) external onlyPoolCycleManager {
        if (!registeredLPs[lp]) revert NotRegisteredLP();
        
        lpPositions[lp].interestAccrued += amount;
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

            (,, uint256 liquidationReward) = poolStrategy.getLPLiquidityParams();
            // Transfer liquidation reward to liquidator
            uint256 liquidationAmount = request.requestAmount;
            uint256 rewardAmount = Math.mulDiv(liquidationAmount, liquidationReward, BPS);

            position.liquidityCommitment -= liquidationAmount;
            position.collateralAmount -= rewardAmount;
            totalLPCollateral -= rewardAmount;

            reserveToken.transfer(liquidationInitiators[lp], rewardAmount);

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

        uint256 lpAssetHolding = Math.mulDiv(lpShare, poolValue * reserveToAssetDecimalFactor, PRECISION);
        
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
     * @notice Get LP's current liquidity position
     * @param lp Address of the LP
     */
    function getLPPosition(address lp) external view returns (LPPosition memory) {
        return lpPositions[lp];
    }

    /**
     * @notice Get LP's current request
     * @param lp Address of the LP
     */
    function getLPRequest(address lp) external view returns (LPRequest memory) {
        return lpRequests[lp];
    }

    /**
     * @notice Get LP's current liquidation initiator
     * @param lp Address of the LP
     */
    function getLPLiquidationIntiator(address lp) external view returns (address) {
        return liquidationInitiators[lp];
    }

    /**
     * @notice Check if an address is a registered LP
     * @param lp The address to check
     * @return bool True if the address is a registered LP
     */
    function isLP(address lp) external view returns (bool) {
        return registeredLPs[lp];
    }
    
    /**
     * @notice Returns the number of LPs registered
     * @return uint256 The number of registered LPs
     */
    function getLPCount() external view returns (uint256) {
        return lpCount;
    }
    
    /**
     * @notice Returns the current liquidity commited by the LP
     * @param lp The address of the LP
     * @return uint256 The current liquidity amount
     */
    function getLPLiquidityCommitment(address lp) external view returns (uint256) {
        return lpPositions[lp].liquidityCommitment;
    }

    /**
     * @notice Returns the reserve to asset decimal factor
     */
    function getReserveToAssetDecimalFactor() external view returns (uint256) {
        return reserveToAssetDecimalFactor;
    }

    /**
     * @notice Check if the current cycle is active
     * @return True if the cycle is active, false otherwise
    */
    function _isCycleActive() internal view returns (bool) {
        return poolCycleManager.cycleState() == IPoolCycleManager.CycleState.POOL_ACTIVE;
    }

    /**
     * @notice Validate liquidation request
     * @param lp Address of the LP to liquidate
     * @param liquidationAmount Amount of liquidity to liquidate
     */
    function _validateLiquidation(address lp, uint256 liquidationAmount) internal view {
        if (!registeredLPs[lp] || lp == msg.sender) revert InvalidLiquidation();
        if (liquidationAmount == 0) revert InvalidAmount();
    
        // Check if LP is liquidatable
        uint8 liquidityHealth = poolStrategy.getLPLiquidityHealth(address(this), lp);
        if (liquidityHealth != 1) revert NotEligibleForLiquidation();

        LPRequest storage request = lpRequests[lp];
        if (request.requestType != RequestType.NONE) revert RequestPending();

        // Get LP position details
        LPPosition storage position = lpPositions[lp];
        if (liquidationAmount > position.liquidityCommitment) revert InvalidAmount();

        // Get LP liquidity parameters
        (uint256 healthyRatio, , uint256 liquidationReward) = poolStrategy.getLPLiquidityParams();

        // Calculate liquidation reward
        uint256 rewardAmount = Math.mulDiv(liquidationAmount, liquidationReward, BPS);
        if (position.collateralAmount < rewardAmount) revert InsufficientCollateral();
        uint256 collateralAfterReward = position.collateralAmount - rewardAmount;

        // Calculate if position will be healthy after liquidation
        uint256 remainingLiquidity =  position.liquidityCommitment - liquidationAmount;
        uint256 requiredCollateral = Math.mulDiv(remainingLiquidity, healthyRatio, BPS);
        if (collateralAfterReward < requiredCollateral) revert InsufficientCollateral();
        
        // Determine allowed reduction amount (same logic as reduceLiquidity)
        uint256 allowedReduction = calculateAvailableLiquidity() / 2;
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
        
        // Transfer any remaining interest
        if (position.interestAccrued > 0) {
            uint256 interestAmount = position.interestAccrued;
            position.interestAccrued = 0;
            reserveToken.transfer(lp, interestAmount);

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