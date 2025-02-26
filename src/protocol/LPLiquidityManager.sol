// SPDX-License-Identifier: GPL-3.0-or-later
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import "../interfaces/IAssetPool.sol";
import "../interfaces/IAssetOracle.sol";
import "../interfaces/IXToken.sol";
import "../interfaces/ILPLiquidityManager.sol";

/**
 * @title LPLiquidityManager
 * @notice Manages LP collateral requirements and registry for the asset pool
 */
contract LPLiquidityManager is ILPLiquidityManager, Ownable, ReentrancyGuard, Initializable {
    
    // Healthy collateral ratio (50%)
    uint256 public constant HEALTHY_COLLATERAL_RATIO = 50_00;
    // Collateral threshold for liquidation (30%)   
    uint256 public constant COLLATERAL_THRESHOLD = 30_00; 
    // Registration percentage (20%) 
    uint256 public constant REGISTRATION_COLLATERAL_RATIO = 20_00;
    // Liquidation reward percentage (5%)
    uint256 public constant LIQUIDATION_REWARD_PERCENTAGE = 5_00;
    
    // Precision for calculations
    uint256 private constant PRECISION = 1e18;

    // Asset pool contract
    IAssetPool public assetPool;
    
    // Asset oracle
    IAssetOracle public assetOracle;
    
    // Reserve token (USDC, USDT etc)
    IERC20 public reserveToken;

    // Total liquidity in the pool
    uint256 public totalLPLiquidity;
    
    // Number of registered LPs
    uint256 public lpCount;

    // Mapping of LP addresses to their collateral info
    mapping(address => CollateralInfo) private lpInfo;
    
    // Mapping to check if an address is a registered LP
    mapping(address => bool) public registeredLPs;

    /**
     * @notice Modifier to ensure the caller is a registered LP
     */
    modifier onlyRegisteredLP() {
        if (!registeredLPs[msg.sender]) revert NotRegisteredLP();
        _;
    }

    /**
     * @dev Empty constructor that transfers ownership to the deployer
     * Used for the implementation contract only, not for clones
     */
    constructor() Ownable(msg.sender) {
        // This disables initialization of the implementation contract
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract - replaces the constructor for clones
     * @param _assetPool Address of the asset pool
     * @param _assetOracle Address of the asset oracle
     * @param _reserveToken Address of the reserve token
     * @param _owner Address of the owner
     */
    function initialize(
        address _assetPool,
        address _assetOracle,
        address _reserveToken,
        address _owner
    ) external initializer {
        if (_assetPool == address(0) || _assetOracle == address(0) || 
            _reserveToken == address(0) || _owner == address(0)) {
            revert ZeroAddress();
        }
            
        assetPool = IAssetPool(_assetPool);
        assetOracle = IAssetOracle(_assetOracle);
        reserveToken = IERC20(_reserveToken);
        
        // Initialize Ownable
        _transferOwnership(_owner);
    }

    /**
     * @notice Register as a liquidity provider
     * @param liquidityAmount The amount of liquidity to provide
     */
    function registerLP(uint256 liquidityAmount) external nonReentrant {
        if (registeredLPs[msg.sender]) revert AlreadyRegistered();
        if (liquidityAmount == 0) revert InvalidAmount();
        
        // Calculate required collateral (20% of liquidity)
        uint256 requiredCollateral = Math.mulDiv(liquidityAmount, REGISTRATION_COLLATERAL_RATIO, 100_00);
        
        // Transfer collateral from LP to contract
        reserveToken.transferFrom(msg.sender, address(this), requiredCollateral);
        
        // Update LP info
        registeredLPs[msg.sender] = true;
        lpInfo[msg.sender] = CollateralInfo({
            collateralAmount: requiredCollateral,
            liquidityAmount: liquidityAmount
        });
        
        // Update pool stats
        totalLPLiquidity += liquidityAmount;
        lpCount++;
        
        emit LPRegistered(msg.sender, liquidityAmount, requiredCollateral);
    }

    /**
     * @notice Remove LP from registry
     * @param lp The address of the LP to remove
     */
    function removeLP(address lp) external {
        if (msg.sender != lp) revert Unauthorized();
        if (!registeredLPs[lp]) revert NotRegisteredLP();
        
        CollateralInfo storage info = lpInfo[lp];
        if (info.liquidityAmount > 0) revert("LP has active liquidity");
        
        // Refund any remaining collateral
        if (info.collateralAmount > 0) {
            uint256 refundAmount = info.collateralAmount;
            info.collateralAmount = 0;
            reserveToken.transfer(lp, refundAmount);
        }
        
        // Remove LP
        registeredLPs[lp] = false;
        lpCount--;
        
        emit LPRemoved(lp);
    }

    /**
     * @notice Increase your liquidity amount
     * @param amount The amount of liquidity to add
     */
    function increaseLiquidity(uint256 amount) external nonReentrant onlyRegisteredLP {
        if (amount == 0) revert InvalidAmount();
        
        CollateralInfo storage info = lpInfo[msg.sender];
        
        // Calculate additional required collateral (20% of new liquidity)
        uint256 additionalCollateral = Math.mulDiv(amount, REGISTRATION_COLLATERAL_RATIO, 100_00);
        
        // Transfer additional collateral
        reserveToken.transferFrom(msg.sender, address(this), additionalCollateral);
        
        // Update LP info
        info.liquidityAmount += amount;
        info.collateralAmount += additionalCollateral;
        
        // Update total liquidity
        totalLPLiquidity += amount;
        
        emit LiquidityIncreased(msg.sender, amount);
    }

    /**
     * @notice Decrease your liquidity amount
     * @param amount The amount of liquidity to remove
     */
    function decreaseLiquidity(uint256 amount) external nonReentrant onlyRegisteredLP {
        if (amount == 0) revert InvalidAmount();
        
        CollateralInfo storage info = lpInfo[msg.sender];
        if (amount > info.liquidityAmount) revert InsufficientLiquidity();
        
        // Calculate releasable collateral (20% of removed liquidity)
        uint256 releasableCollateral = Math.mulDiv(amount, REGISTRATION_COLLATERAL_RATIO, 100_00);
        
        // Update LP info
        info.liquidityAmount -= amount;
        
        // Ensure remaining collateral meets minimum requirements for remaining liquidity
        uint256 requiredCollateral = getRequiredCollateral(msg.sender);
        
        // Can only release excess collateral if remaining above minimum required
        if (info.collateralAmount - releasableCollateral >= requiredCollateral) {
            info.collateralAmount -= releasableCollateral;
            reserveToken.transfer(msg.sender, releasableCollateral);
        }
        
        // Update total liquidity
        totalLPLiquidity -= amount;
        
        emit LiquidityDecreased(msg.sender, amount);
    }

    /**
     * @notice Deposit additional collateral beyond the minimum
     * @param amount Amount of collateral to deposit
     */
    function deposit(uint256 amount) external nonReentrant onlyRegisteredLP {
        if (amount == 0) revert ZeroAmount();
        
        reserveToken.transferFrom(msg.sender, address(this), amount);
        lpInfo[msg.sender].collateralAmount += amount;
        
        emit CollateralDeposited(msg.sender, amount);
    }

    /**
     * @notice Withdraw excess collateral if above minimum requirements
     * @param amount Amount of collateral to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant onlyRegisteredLP {
        CollateralInfo storage info = lpInfo[msg.sender];
        if (amount == 0 || amount > info.collateralAmount) revert InvalidWithdrawalAmount();
        
        uint256 requiredCollateral = getRequiredCollateral(msg.sender);
        if (info.collateralAmount - amount < requiredCollateral) {
            revert InsufficientCollateral();
        }
        
        info.collateralAmount -= amount;
        reserveToken.transfer(msg.sender, amount);
        
        emit CollateralWithdrawn(msg.sender, amount);
    }

    /**
    * @notice Liquidate an LP below threshold - Gas optimized version
    * @param lp Address of the LP to liquidate
    */
    function liquidateLP(address lp) external nonReentrant onlyRegisteredLP {
        if (!registeredLPs[lp] || lp == msg.sender) revert InvalidLiquidation();
        
        CollateralInfo memory targetInfo = lpInfo[lp];
        uint256 lpLiquidity = targetInfo.liquidityAmount;
        uint256 lpCollateral = targetInfo.collateralAmount;
        
        if (lpLiquidity == 0) revert NoLiquidityToLiquidate();
        
        uint256 lpAssetHolding = getLPAssetHolding(lp);
        
        // Check liquidation eligibility
         // we need to convert the assetHolding to the same decimal factor as the reserve token i.e collateral
        if (lpCollateral * 100_00 * assetPool.reserveToAssetDecimalFactor() >= lpAssetHolding * COLLATERAL_THRESHOLD) {
            revert NotEligibleForLiquidation();
        }
        
        // Calculate liquidation reward
        uint256 liquidationReward = lpCollateral * LIQUIDATION_REWARD_PERCENTAGE / 100_00;
        
        // Calculate remaining collateral
        uint256 remainingCollateral = lpCollateral - liquidationReward;
        
        // Calculate liquidator's new position requirements
        CollateralInfo memory callerInfo = lpInfo[msg.sender];
        uint256 callerAssetHolding = getLPAssetHolding(msg.sender);
        
        // Add target LP's asset holding to caller's
        uint256 newCallerAssetHolding = callerAssetHolding + lpAssetHolding;
         // we need to convert the assetHolding to the same decimal factor as the reserve token i.e collateral
        uint256 newRequiredCollateral = newCallerAssetHolding * COLLATERAL_THRESHOLD / 100_00 * assetPool.reserveToAssetDecimalFactor();
        
        // Check if additional collateral is needed
        uint256 additionalCollateralNeeded = 0;
        if (newRequiredCollateral > callerInfo.collateralAmount) {
            additionalCollateralNeeded = newRequiredCollateral - callerInfo.collateralAmount;
            
            // Transfer additional collateral in one go if needed
            reserveToken.transferFrom(msg.sender, address(this), additionalCollateralNeeded);
        }
        
        lpInfo[msg.sender].liquidityAmount = callerInfo.liquidityAmount + lpLiquidity;
        lpInfo[msg.sender].collateralAmount = callerInfo.collateralAmount + additionalCollateralNeeded + liquidationReward;
        
        // Reset liquidated LP's position
        delete lpInfo[lp];
        
        if (remainingCollateral > 0) {
            reserveToken.transfer(lp, remainingCollateral);
        }
        
        emit LPLiquidated(lp, msg.sender, liquidationReward);
    }

    /**
     * @notice Deduct rebalance amount from LP's collateral
     * @param lp Address of the LP
     * @param amount Amount to deduct
     */
    function deductRebalanceAmount(address lp, uint256 amount) external {
        if (msg.sender != address(assetPool)) revert Unauthorized();
        if (!registeredLPs[lp]) revert NotRegisteredLP();
            
        CollateralInfo storage info = lpInfo[lp];
        if (amount > info.collateralAmount) revert InsufficientCollateral();
            
        info.collateralAmount -= amount;
        reserveToken.transfer(address(assetPool), amount);
        
        // Check remaining ratio
        uint256 currentRatio = getCurrentRatio(lp);
        if (currentRatio < COLLATERAL_THRESHOLD) revert InsufficientCollateral();
        
        emit RebalanceDeducted(lp, amount);
    }

    /**
     * @notice Add rebalance amount to LP's collateral
     * @param lp Address of the LP
     * @param amount Amount to add
     */
    function addToCollateral(address lp, uint256 amount) external {
        if (msg.sender != address(assetPool)) revert Unauthorized();
        if (!registeredLPs[lp]) revert NotRegisteredLP();
        
        lpInfo[lp].collateralAmount += amount;
        
        emit RebalanceAdded(lp, amount);
    }

    /**
     * @notice Calculate Lp's current asset holding
     * @param lp Address of the LP
     */
    function getLPAssetHolding(address lp) public view returns (uint256) {
        if (!registeredLPs[lp]) return 0;
        
        CollateralInfo storage info = lpInfo[lp];
        
        uint256 totalSupply = IXToken(assetPool.assetToken()).totalSupply();
        uint256 assetPrice = assetOracle.assetPrice();
        
        // Calculate LP's share of total supply based on their proportion of total liquidity
        uint256 lpShare = info.liquidityAmount;
        
        // If no total liquidity, no collateral required
        if (totalLPLiquidity == 0) return 0;

        uint256 lpAssetHolding = Math.mulDiv(
            Math.mulDiv(totalSupply, assetPrice, PRECISION),
            lpShare,
            totalLPLiquidity
        );
        
        return lpAssetHolding;
    }

    /**
     * @notice Calculate required collateral for an LP
     * @param lp Address of the LP
     */
    function getRequiredCollateral(address lp) public view returns (uint256) {
        if (!registeredLPs[lp]) return 0;
        
        uint256 lpAssetHolding = getLPAssetHolding(lp);

        if (lpAssetHolding == 0) return 0;
        
        // we need to convert the assetHolding to the same decimal factor as the reserve token i.e collateral
        return Math.mulDiv(lpAssetHolding, COLLATERAL_THRESHOLD, 100_00 * assetPool.reserveToAssetDecimalFactor());
    }

    /**
     * @notice Calculate current collateral ratio for an LP
     * @param lp Address of the LP
     */
    function getCurrentRatio(address lp) public view returns (uint256) {
        if (!registeredLPs[lp]) return 0;
        
        CollateralInfo storage info = lpInfo[lp];
        uint256 lpAssetHolding = getLPAssetHolding(lp);

        if (lpAssetHolding == 0 && info.collateralAmount > 0) return HEALTHY_COLLATERAL_RATIO;
        if (lpAssetHolding == 0) return 0;
        
         // we need to convert the assetHolding to the same decimal factor as the reserve token i.e collateral
        return Math.mulDiv(info.collateralAmount, 100_00 * assetPool.reserveToAssetDecimalFactor(), lpAssetHolding);
    }

    /**
    * @notice Check LP's collateral health
    * @param lp Address of the LP
    * @return uint8 3 = Great (>= HEALTHY_COLLATERAL_RATIO), 
    *               2 = Good (>= COLLATERAL_THRESHOLD but < HEALTHY_COLLATERAL_RATIO), 
    *               1 = Bad (< COLLATERAL_THRESHOLD)
    */
    function checkCollateralHealth(address lp) public view returns (uint8) {
        if (!registeredLPs[lp]) revert NotRegisteredLP();
        
        uint256 currentRatio = getCurrentRatio(lp);
        
        if (currentRatio >= HEALTHY_COLLATERAL_RATIO) {
            return 3; // Great: At or above healthy ratio
        } else if (currentRatio >= COLLATERAL_THRESHOLD) {
            return 2; // Good: At or above minimum threshold but below healthy ratio
        } else {
            return 1; // Bad: Below minimum threshold
        }
    }
    
    /**
     * @notice Get LP's current collateral and liquidity info
     * @param lp Address of the LP
     */
    function getLPInfo(address lp) external view returns (CollateralInfo memory) {
        return lpInfo[lp];
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
     * @notice Returns the current liquidity amount for an LP
     * @param lp The address of the LP
     * @return uint256 The current liquidity amount
     */
    function getLPLiquidity(address lp) external view returns (uint256) {
        return lpInfo[lp].liquidityAmount;
    }
    
    /**
     * @notice Returns the total liquidity amount
     * @return uint256 The total liquidity amount
     */
    function getTotalLPLiquidity() external view returns (uint256) {
        return totalLPLiquidity;
    }
}