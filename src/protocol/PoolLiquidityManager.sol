// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
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
    using SafeERC20 for IERC20Metadata;
    
    // Total liquidity committed by LPs
    uint256 public totalLPLiquidityCommited;

    // Total lp principal (includes both collateral and interest)
    uint256 public totalLPPrincipal;

    // Combined reserve balance of the liquidity manager (including collateral and interest)
    uint256 public aggregatePoolReserves;
    
    // Number of acitve LPs
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
    mapping(address => bool) public isLP;

    // Mapping to track active LPs
    mapping(address => bool) public isLPActive;

    // Mapping to track LP delegates
    mapping(address => address) public lpDelegates;

    // Mapping to track liquidation initiators
    mapping(address => address) public liquidationInitiators;

    // Reserve yield earned per token to date (if isYieldBearing).
    uint256 public reserveYieldIndex;

    // Interest index of the LP, used to calculate reserve yield on their positions
    mapping(address => uint256) public lpReserveYieldIndex;

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
        if (!isLP[msg.sender]) revert NotRegisteredLP();
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
        address _poolLiquidityManager,
        address _poolStrategy
    ) external initializer {
        if (_reserveToken == address(0) || _assetToken == address(0) || _assetPool == address(0) || 
            _poolCycleManager == address(0) || _assetOracle == address(0)) {
            revert ZeroAddress();
        }
            
        reserveToken = IERC20Metadata(_reserveToken);
        assetToken = IXToken(_assetToken);
        assetOracle = IAssetOracle(_assetOracle);
        assetPool = IAssetPool(_assetPool);
        poolCycleManager = IPoolCycleManager(_poolCycleManager);
        poolLiquidityManager = IPoolLiquidityManager(_poolLiquidityManager);
        poolStrategy = IPoolStrategy(_poolStrategy);
        reserveYieldIndex = 1e18;

        _initializeDecimalFactor(address(reserveToken), address(assetToken));
        
    }

    /**
     * @notice Add liquidity to the pool
     * @param amount The amount of liquidity to add
     */
    function addLiquidity(uint256 amount) public nonReentrant {
        if (amount == 0) revert InvalidAmount();

        // Check minimum commitment requirement
        uint256 minimumRequired = poolStrategy.lpMinCommitment();
        if (minimumRequired > 0) {
            uint256 scaledMinimum = minimumRequired * (10 ** reserveToken.decimals());
            if (amount < scaledMinimum) {
                revert InvalidAmount();
            }
        }

        if (!_isPoolActive()) revert InvalidCycleState();
        // Calculate additional required collateral
        uint256 requiredCollateral = Math.mulDiv(amount, poolStrategy.lpHealthyCollateralRatio(), BPS);
        
        if (poolStrategy.isYieldBearing()) {
            // Handle yield-bearing deposit
            _handleYieldBearingDeposit(msg.sender, requiredCollateral, msg.sender);
        } else {
            // Transfer required collateral
            reserveToken.safeTransferFrom(msg.sender, address(this), requiredCollateral);
        }

        uint8 collateralHealth = poolStrategy.getLPLiquidityHealth(address(this), msg.sender);
        if (collateralHealth == 1) revert InsufficientCollateralHealth(collateralHealth);

        LPPosition storage position = lpPositions[msg.sender];
        
        if (isLP[msg.sender]) {
            LPRequest storage request = lpRequests[msg.sender];
            if (request.requestType != RequestType.NONE) revert RequestPending();  
             if (!isLPActive[msg.sender]) {
                isLPActive[msg.sender] = true;
                lpCount++;
            }              
        } else {
            isLP[msg.sender] = true;
            isLPActive[msg.sender] = true;
            lpCount++;

            emit LPAdded(msg.sender, amount, requiredCollateral);
        }

        position.collateralAmount += requiredCollateral; 
        cycleTotalAddLiquidityAmount += amount;
        totalLPPrincipal += requiredCollateral;
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

        // Check if the LP is maintaining liquidity commitment
        uint256 minimumRequired = poolStrategy.lpMinCommitment();     
        if (minimumRequired > 0) {
            uint256 scaledMinimum = minimumRequired * (10 ** reserveToken.decimals());
            uint256 balanceCommitment = position.liquidityCommitment - amount;
            if (balanceCommitment != 0 && balanceCommitment < scaledMinimum) {
                revert InvalidAmount();
            }
        }

        uint256 availableLiquidity = poolStrategy.calculateCycleAvailableLiquidity(address(assetPool));
        // Allowed reduction is lower (50%) when its being utilized
        uint256 allowedReduction = assetToken.totalSupply() > 0 ? availableLiquidity / 2 : availableLiquidity;
        // Ensure there is available liquidity for the operation
        if (allowedReduction == 0) revert UtilizationTooHighForOperation();
        // Ensure reduction amount doesn't exceed allowed reduction
        if (amount > allowedReduction) revert OperationExceedsAvailableLiquidity(amount, allowedReduction);

        uint8 collateralHealth = poolStrategy.getLPLiquidityHealth(address(this), msg.sender);
        if (collateralHealth == 1) revert InsufficientCollateralHealth(collateralHealth);

        // Create the reduction request
        _createRequest(msg.sender, RequestType.REDUCE_LIQUIDITY, amount);
        
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
        
        address delegate = lpDelegates[lp];
        address fromAccount = (delegate != address(0) && msg.sender == delegate) ? lp : msg.sender;
        if (poolStrategy.isYieldBearing()) {
            _handleYieldBearingDeposit(lp, amount, fromAccount);
        } else {
            reserveToken.safeTransferFrom(fromAccount, address(this), amount);
        }

        lpPositions[lp].collateralAmount += amount;

        totalLPPrincipal += amount;
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

        uint256 reserveYield = 0;
        if (poolStrategy.isYieldBearing()) {
           reserveYield = _handleYieldBearingWithdrawal(msg.sender, amount);
        }
        
        uint256 totalAmount = amount + reserveYield;
        position.collateralAmount -= amount;
        totalLPPrincipal -= amount;
        aggregatePoolReserves -= amount;
        reserveToken.safeTransfer(msg.sender, totalAmount);

        emit CollateralReduced(msg.sender, totalAmount);
    }

    /**
     * @notice Register as an LP, add liquidity & set delegate
     * @param amount Amount of liquidity to add
     * @param delegate Address of the delegate (use address(0) to remove)
     */
    function registerLP(uint256 amount, address delegate) external {
        addLiquidity(amount);
        setDelegate(delegate);
    }

    /**
     * @notice Claim interest accrued on LP position
     */
    function claimInterest() external nonReentrant onlyRegisteredLP {
        LPPosition storage position = lpPositions[msg.sender];
        uint256 interestAccrued = position.interestAccrued;
        if (interestAccrued == 0) revert NoInterestAccrued();
        
        uint256 reserveYield = 0;
        if (poolStrategy.isYieldBearing()) {
           reserveYield = _handleYieldBearingWithdrawal(msg.sender, interestAccrued);
        }

        uint256 totalAmount = interestAccrued + reserveYield;
        position.interestAccrued = 0;
        aggregatePoolReserves -= interestAccrued;
        totalLPPrincipal -= interestAccrued;
        reserveToken.safeTransfer(msg.sender, totalAmount);

        emit InterestClaimed(msg.sender, totalAmount);
    }

    /**
    * @notice Set a delegate address that can rebalance on behalf of the LP
    * @param delegate Address of the delegate (use address(0) to remove)
    */
    function setDelegate(address delegate) public onlyRegisteredLP {
        lpDelegates[msg.sender] = delegate;
        emit DelegateSet(msg.sender, delegate);
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
     * @notice Exit the pool and withdraw all funds
     */
    function exitPool() external nonReentrant onlyRegisteredLP {
        if (!_isPoolHalted() && isLPActive[msg.sender]) revert InvalidCycleState();
        _removeLP(msg.sender);
    }

    /**
     * @notice Add interest amount to LP's position
     * @param lp Address of the LP
     * @param amount Amount to add
     */
    function addToInterest(address lp, uint256 amount) external onlyAssetPool {
        if (!isLPActive[lp]) revert NotRegisteredLP();

        if (poolStrategy.isYieldBearing()) {
           _updateReserveYieldIndex();
           _updateLPReserveYieldIndex(lp, amount);
        }
        
        lpPositions[lp].interestAccrued += amount;
        aggregatePoolReserves += amount;
        totalLPPrincipal += amount;

        emit InterestDistributedToLP(lp, amount, poolCycleManager.cycleIndex());
    }

    /**
     * @notice Add rebalance amount to LP's position
     * @dev During settle pool, we use this to add the rebalance amount to LP's position
     * @param lp Address of the LP
     * @param amount Amount to add
     */
    function addToCollateral(address lp, uint256 amount) external onlyAssetPool {
        if (!isLPActive[lp]) revert NotRegisteredLP();

        if (poolStrategy.isYieldBearing()) {
           _updateReserveYieldIndex();
           _updateLPReserveYieldIndex(lp, amount);
        }
        
        lpPositions[lp].collateralAmount += amount;
        totalLPPrincipal += amount;
        aggregatePoolReserves += amount;

        emit RebalanceAmountTransferred(lp, amount, poolCycleManager.cycleIndex());
    }

    /**
     * @notice Deduct collateral from LP's position
     * @dev This is used to deduct collateral during lp settlement
     * @param lp Address of the LP
     * @param amount Amount to deduct
     */
    function deductFromCollateral(address lp, uint256 amount) external onlyPoolCycleManager {
        if (!isLPActive[lp]) revert NotRegisteredLP();
        
        LPPosition storage position = lpPositions[lp];
        if (position.collateralAmount < amount) revert InvalidAmount();

        uint256 reserveYield = 0;
        if (poolStrategy.isYieldBearing()) {
            // Handle yield-bearing withdrawal
           reserveYield = _handleYieldBearingWithdrawal(lp, amount);
           _updateLPReserveYieldIndex(lp, reserveYield);
        }

        position.collateralAmount = position.collateralAmount + reserveYield - amount;
        totalLPPrincipal = totalLPPrincipal + reserveYield - amount;
        aggregatePoolReserves = aggregatePoolReserves + reserveYield - amount;

        reserveToken.safeTransfer(address(assetPool), amount);
    }

    /**
     * @notice Resolves an LP request after a rebalance cycle
     * @dev This should be called after a rebalance to clear pending request flags
     * @dev If the transfer function fails because the address is blacklisted within the token contract etc,
     * @dev we handle it gracefully by sending the tokens to the fee recipient instead.
     * @dev This ensures that the pool does not get stuck with untransferable tokens.
     * @param lp Address of the LP
     */
    function resolveRequest(address lp) external onlyPoolCycleManager {
        if (!isLPActive[lp]) revert NotRegisteredLP();
        
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
                lpCount--;
                isLPActive[lp] = false;
            }
        } else if (request.requestType == RequestType.LIQUIDATE) {
            // Transfer liquidation reward to liquidator
            uint256 liquidationAmount = request.requestAmount;
            uint256 rewardAmount = Math.mulDiv(liquidationAmount, poolStrategy.lpLiquidationReward(), BPS);
            position.liquidityCommitment -= liquidationAmount;
            uint256 transferAmount = rewardAmount;
            if (position.collateralAmount < rewardAmount) {
                transferAmount = position.collateralAmount;
            }

            if (transferAmount > 0) {
                uint256 reserveYield = 0;
                if (poolStrategy.isYieldBearing()) {
                    reserveYield = _handleYieldBearingWithdrawal(lp, transferAmount);
                } 

                uint256 totalAmount = transferAmount + reserveYield;
                position.collateralAmount -= transferAmount;
                totalLPPrincipal -= transferAmount;
                aggregatePoolReserves -= transferAmount;

                // If the liquidator can't receive funds, send the reward to the fee recipient
                // Transfer the reward to the liquidator using low-level call to handle transfer failures
                (bool success, bytes memory data) =
                    address(reserveToken).call(
                        abi.encodeWithSelector(IERC20.transfer.selector, liquidationInitiators[lp], totalAmount)
                    );
                
                // Check if transfer succeeded (handles tokens that return false or no return value)
                bool transferSucceeded = success && (data.length == 0 || abi.decode(data, (bool)));

                // If transfer failed, send to fee recipient instead
                if (!transferSucceeded) {
                    reserveToken.safeTransfer(poolStrategy.feeRecipient(), totalAmount);
                }
            }
            emit LPLiquidationExecuted(lp, liquidationInitiators[lp], liquidationAmount, transferAmount);

            if(position.liquidityCommitment == 0) {
                lpCount--;
                isLPActive[lp] = false;
                delete liquidationInitiators[lp]; // Clear liquidator
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
        uint256 cycleTotalLiquidity = _safeSubtract(totalLPLiquidityCommited + cycleTotalAddLiquidityAmount,
            cycleTotalReduceLiquidityAmount
        );

        return cycleTotalLiquidity;
    }

    /**
     * @notice Calculate Lp's current asset holding value (in reserve token)
     * @param lp Address of the LP
     */
    function getLPAssetHoldingValue(address lp) public view returns (uint256) {
        if (!isLPActive[lp]) return 0;
        
        uint256 poolValue = assetPool.getUtilisedLiquidity();
        uint256 lpShare = getLPLiquidityShare(lp);
        uint256 lpAssetHolding = Math.mulDiv(lpShare, poolValue, PRECISION);
        
        return lpAssetHolding;
    }

    /**
     * @notice Get LP's current liquidity share of the pool
     * @param lp Address of the LP
     */
    function getLPLiquidityShare(address lp) public view returns (uint256) {
        if (!isLPActive[lp]) return 0;
        // If no total liquidity, return 0
        if (totalLPLiquidityCommited == 0) return 0;
        return Math.mulDiv(lpPositions[lp].liquidityCommitment, PRECISION, totalLPLiquidityCommited);
    }

    /**
     * @notice Get LP's current asset share of the pool
     * @param lp Address of the LP
     */
    function getLPAssetShare(address lp) public view returns (uint256) {
        if (!isLPActive[lp]) return 0;
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
        if (!isLPActive[lp]) return 0;
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
     * @notice Returns the current liquidity commited by the LP
     * @param lp The address of the LP
     * @return uint256 The current liquidity amount
     */
    function getLPLiquidityCommitment(address lp) public view returns (uint256) {
        return lpPositions[lp].liquidityCommitment;
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
    function _validateLiquidation(address lp, uint256 liquidationAmount) internal {
        if (!isLP[lp] || lp == msg.sender) revert InvalidLiquidation();
        if (liquidationAmount == 0) revert InvalidAmount();

        if (!_isPoolActive()) revert InvalidCycleState();
    
        // Check if LP is liquidatable
        uint8 liquidityHealth = poolStrategy.getLPLiquidityHealth(address(this), lp);
        if (liquidityHealth != 1) revert NotEligibleForLiquidation();

        // Get LP position details
        LPPosition storage position = lpPositions[lp];
        if (liquidationAmount > position.liquidityCommitment) revert InvalidAmount();

        LPRequest storage request = lpRequests[lp];
        // If there is an existing liquidation request, check if the current request is better 
        if (request.requestType == RequestType.LIQUIDATE) {
            if (request.requestAmount >= liquidationAmount){
                revert BetterLiquidationRequestExists();
            } else {
                // Remove previous liquidation amount if exists
                cycleTotalReduceLiquidityAmount -= request.requestAmount;
            }     
        }

        // Allowed reduction is higher (75%) in case of liquidation
        uint256 allowedReduction = (poolStrategy.calculateCycleAvailableLiquidity(address(assetPool)) * 3) / 4;
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
            
            uint256 reserveYield = 0;
            if (poolStrategy.isYieldBearing()) {
                reserveYield = _handleYieldBearingWithdrawal(lp, collateralAmount);
            }

            position.collateralAmount = 0;
            totalLPPrincipal -= collateralAmount;
            aggregatePoolReserves -= collateralAmount;
            reserveToken.safeTransfer(lp, collateralAmount + reserveYield);

            emit CollateralReduced(lp, collateralAmount + reserveYield);
        }
        
        // Transfer any remaining interest
        if (position.interestAccrued > 0) {
            uint256 interestAmount = position.interestAccrued;

            uint256 reserveYield = 0;
            if (poolStrategy.isYieldBearing()) {
                reserveYield = _handleYieldBearingWithdrawal(lp, interestAmount);
            }

            position.interestAccrued = 0;
            totalLPPrincipal -= interestAmount;
            aggregatePoolReserves -= interestAmount;
            reserveToken.safeTransfer(lp, interestAmount + reserveYield);

            emit InterestClaimed(lp, interestAmount + reserveYield);
        }
        
        // If LP has liquidity commitment, reduce the count. If the commitment is zero, lp count is already reduced
        if (getLPLiquidityCommitment(lp) > 0) {
            lpCount--;
            isLPActive[lp] = false;
        }

        // Mark LP as removed
        isLP[lp] = false;
        // Clean up storage
        delete lpPositions[lp];
        // We keep lpRequests for historical reference
        
        emit LPRemoved(lp);
    }

    /**
     * @notice Handle deposit for yield-bearing tokens with yield calculation
     * @param lp Address of the LP depositing
     * @param amount Amount being deposited
     * @param depositor Address of the actual depositor (can be different from lp)
     */
    function _handleYieldBearingDeposit(address lp, uint256 amount, address depositor) internal {
        // Update the reserve yield index
        _updateReserveYieldIndex();
        // Transfer amount from depositor to this contract
        reserveToken.safeTransferFrom(depositor, address(this), amount);
        // Update the LP's reserve yield index
        _updateLPReserveYieldIndex(lp, amount);
    }

    /**
     * @notice Handle withdrawal for yield-bearing tokens with yield calculation
     * @param lp Address of the lp
     * @param amount amount being withdrawn
     * @return reserveYield The calculated yield amount
     */
    function _handleYieldBearingWithdrawal(
        address lp, 
        uint256 amount
    ) internal returns (uint256) {
        _updateReserveYieldIndex();
        uint256 lpReserve = _getLPTotalReserveAmount(lp);
        uint256 totalYield = Math.mulDiv(lpReserve, reserveYieldIndex - lpReserveYieldIndex[lp], PRECISION);
        uint256 reserveYield = Math.mulDiv(totalYield, amount, lpReserve);
        aggregatePoolReserves = _safeSubtract(aggregatePoolReserves, reserveYield);

        // Deduct protocol fee from the yield
        return _deductProtocolFee(lp, reserveYield);
    }

    /**
     * @notice Update the reserve yield index
     */
    function _updateReserveYieldIndex() internal {
        uint256 newReserveBalance = reserveToken.balanceOf(address(this));         
        uint256 yIndex = poolStrategy.calculateYieldAccrued(
            aggregatePoolReserves,
            newReserveBalance,
            totalLPPrincipal
        );
        aggregatePoolReserves = newReserveBalance;
        reserveYieldIndex += yIndex;
    }

    /**
     * @notice Get the total reserve amount for an LP
     * @param lp Address of the LP
     * @return Total reserve amount including collateral and interest accrued
     */
    function _getLPTotalReserveAmount(address lp) internal view returns (uint256) {
        LPPosition storage position = lpPositions[lp];
        return position.collateralAmount + position.interestAccrued;
    }

    /**
     * @notice Update the LP's reserve yield index
     * @param lp Address of the LP
     * @param amount Amount to update
     */
    function _updateLPReserveYieldIndex(address lp, uint256 amount) internal {
        uint256 oldPrincipal = _getLPTotalReserveAmount(lp);
        uint256 newPrincipal = oldPrincipal + amount;
        uint256 newLPIndex;
        {
            // Isolate newLPIndex computation to limit locals in outer scope
            uint256 uIndex = lpReserveYieldIndex[lp];
            uint256 weightedOld = (oldPrincipal == 0) ? 0 : Math.mulDiv(oldPrincipal, uIndex, newPrincipal);
            uint256 weightedNew = Math.mulDiv(amount, reserveYieldIndex, newPrincipal);
            newLPIndex = (oldPrincipal == 0) ? reserveYieldIndex : weightedOld + weightedNew;
        }
        lpReserveYieldIndex[lp] = newLPIndex;
    }

    /**
     * @notice Deduct protocol fee
     * @param lp Address of the lp
     * @param amount Amount on which the fee needs to be deducted
     */
    function _deductProtocolFee(address lp, uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;
        uint256 protocolFee = poolStrategy.protocolFee();
        uint256 protocolFeeAmount = (protocolFee > 0) ? Math.mulDiv(amount, protocolFee, BPS) : 0;
            
        if (protocolFeeAmount > 0) {   
            reserveToken.safeTransfer(poolStrategy.feeRecipient(), protocolFeeAmount);
            emit FeeDeducted(lp, protocolFeeAmount);
        }

        return amount - protocolFeeAmount;
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