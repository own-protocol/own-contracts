// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/ILPLiquidityManager.sol";
import "../interfaces/IAssetPool.sol";
import "../interfaces/IAssetOracle.sol";

/**
 * @title LPLiquidityManager
 * @notice Manages LP collateral requirements for the asset pool
 */
contract LPLiquidityManager is ILPLiquidityManager, Ownable, ReentrancyGuard {
    // Minimum collateral ratio required (50%)
    uint256 public constant MIN_COLLATERAL_RATIO = 50_00;
    
    // Warning threshold for collateral ratio (30%)
    uint256 public constant COLLATERAL_THRESHOLD = 30_00;

    // Registration percentage (10%)
    uint256 public constant REGISTRATION_COLLATERAL_RATIO = 10_00;
    
    // Liquidation reward percentage (5%)
    uint256 public constant LIQUIDATION_REWARD_PERCENTAGE = 5_00;
    
    // Precision for calculations
    uint256 private constant PRECISION = 1e18;
    
    // Max price deviation allowed from oracle (3%)
    uint256 private constant MAX_PRICE_DEVIATION = 3_00;

    // Asset pool contract
    IAssetPool public immutable assetPool;
    
    // Asset oracle
    IAssetOracle public immutable assetOracle;
    
    // Reserve token (USDC, USDT etc)
    IERC20 public immutable reserveToken;

    // LP collateral information
    ILPRegistry public immutable lpRegistry;

    // LP collateral information
    mapping(address => CollateralInfo) private lpCollateral;

    constructor(
        address _assetPool,
        address _assetOracle,
        address _lpRegistry,
        address _reserveToken,
        address _owner
    ) Ownable(_owner) {
        if (_assetPool == address(0) || _assetOracle == address(0) || 
            _lpRegistry == address(0) || _reserveToken == address(0)) {
            revert ZeroAddress();
        }
            
        assetPool = IAssetPool(_assetPool);
        assetOracle = IAssetOracle(_assetOracle);
        lpRegistry = ILPRegistry(_lpRegistry);
        reserveToken = IERC20(_reserveToken);
    }

    /**
     * @notice Deposit collateral for LP
     * @param amount Amount of collateral to deposit
     */
    function deposit(uint256 amount) external nonReentrant {
        if (!lpRegistry.isLP(address(assetPool), msg.sender)) revert NotRegisteredLP();
        if (amount == 0) revert ZeroAmount();
        
        reserveToken.transferFrom(msg.sender, address(this), amount);
        lpCollateral[msg.sender].collateralAmount += amount;
        
        emit CollateralDeposited(msg.sender, amount);
    }

    /**
     * @notice Withdraw excess collateral if above minimum requirements
     * @param amount Amount of collateral to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant {
        CollateralInfo storage info = lpCollateral[msg.sender];
        if (!lpRegistry.isLP(address(assetPool), msg.sender)) revert NotRegisteredLP();
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
     * @notice Liquidate an LP below threshold
     * @param lp Address of the LP to liquidate
     */
    function liquidateLP(address lp) external nonReentrant {
        if (!lpRegistry.isLP(address(assetPool), msg.sender)) revert NotRegisteredLP();
        CollateralInfo storage info = lpCollateral[lp];
        
        // Check if LP is below threshold
        uint256 currentRatio = getCurrentRatio(lp);
        if (currentRatio >= COLLATERAL_THRESHOLD) revert NotEligibleForLiquidation();

        // Calculate liquidation amounts
        uint256 lpLiquidity = lpRegistry.getLPLiquidity(address(assetPool), lp);
        uint256 liquidationReward = (lpLiquidity * LIQUIDATION_REWARD_PERCENTAGE) / 100_00;
        
        // Transfer reward
        if (liquidationReward > info.collateralAmount) {
            liquidationReward = info.collateralAmount;
        }
        info.collateralAmount -= liquidationReward;
        reserveToken.transfer(msg.sender, liquidationReward);
        
        emit LPLiquidated(lp, msg.sender, liquidationReward);
    }

    /**
     * @notice Deduct rebalance amount from LP's collateral
     * @param lp Address of the LP
     * @param amount Amount to deduct
     */
    function deductRebalanceAmount(address lp, uint256 amount) external {
        if (msg.sender != address(assetPool)) revert Unauthorized();
            
        CollateralInfo storage info = lpCollateral[lp];
        if (amount > info.collateralAmount) revert InsufficientCollateral();
            
        info.collateralAmount -= amount;
        reserveToken.transfer(address(assetPool), amount);
        
        // Check remaining ratio
        uint256 currentRatio = getCurrentRatio(lp);
        if (currentRatio < MIN_COLLATERAL_RATIO) revert InsufficientCollateral();
        
        emit RebalanceDeducted(lp, amount);
    }

    /**
     * @notice Add rebalance amount to LP's collateral
     * @param lp Address of the LP
     * @param amount Amount to add
     */
    function addToCollateral(address lp, uint256 amount) external {
        if (msg.sender != address(assetPool)) revert Unauthorized();
        
        lpCollateral[lp].collateralAmount += amount;
        
        emit RebalanceAdded(lp, amount);
    }

    /**
     * @notice Calculate required collateral for an LP
     * @param lp Address of the LP
     */
    function getRequiredCollateral(address lp) public view returns (uint256) {
        uint256 totalSupply = IXToken(assetPool.assetToken()).totalSupply();
        uint256 assetPrice = assetOracle.assetPrice();
        uint256 lpShare = lpRegistry.getLPLiquidity(address(assetPool), lp);
        uint256 totalLiquidity = lpRegistry.getTotalLPLiquidity(address(assetPool));
        
        return (totalSupply * assetPrice * lpShare * MIN_COLLATERAL_RATIO) / 
               (totalLiquidity * 100_00 * PRECISION);
    }

    /**
     * @notice Calculate current collateral ratio for an LP
     * @param lp Address of the LP
     */
    function getCurrentRatio(address lp) public view returns (uint256) {
        CollateralInfo storage info = lpCollateral[lp];
        uint256 requiredCollateral = getRequiredCollateral(lp);
        
        if (requiredCollateral == 0) return 0;
        return (info.collateralAmount * 100_00) / requiredCollateral;
    }

    /**
     * @notice Check LP's collateral status
     * @param lp Address of the LP
     */
    function checkCollateralStatus(address lp) public {
        uint256 currentRatio = getCurrentRatio(lp);
        
        if (currentRatio < MIN_COLLATERAL_RATIO) {
            uint256 requiredTopUp = getRequiredCollateral(lp) - lpCollateral[lp].collateralAmount;
            emit CollateralWarning(lp, currentRatio, requiredTopUp);
            revert InsufficientCollateral();
        }
    }
    
    /**
     * @notice Get LP's current collateral info
     */
    function getCollateralInfo(address lp) external view returns (CollateralInfo memory) {
        return lpCollateral[lp];
    }
}