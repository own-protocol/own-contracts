// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../interfaces/ILPStaking.sol";
import "../interfaces/IAssetPool.sol";
import "../interfaces/IAssetOracle.sol";

/**
 * @title LPStaking
 * @notice Manages LP staking and collateral requirements for the asset pool
 */
contract LPStaking is ILPStaking, Ownable, ReentrancyGuard {
    // Minimum collateral ratio required (50%)
    uint256 public constant MIN_COLLATERAL_RATIO = 50_00;
    
    // Warning threshold for collateral ratio (30%)
    uint256 public constant COLLATERAL_THRESHOLD = 30_00;
    
    // Precision for calculations
    uint256 private constant PRECISION = 1e18;
    
    // Max price deviation allowed from oracle (5%)
    uint256 private constant MAX_PRICE_DEVIATION = 5_00;

    // Asset pool contract
    IAssetPool public immutable assetPool;
    
    // Asset oracle
    IAssetOracle public immutable assetOracle;
    
    // Reserve token (USDC, USDT etc)
    IERC20 public immutable reserveToken;

    // LP stake information
    mapping(address => StakeInfo) private lpStakes;

    constructor(
        address _assetPool,
        address _assetOracle,
        address _reserveToken,
        address _owner
    ) Ownable(_owner) {
        if (_assetPool == address(0) || _assetOracle == address(0) || _reserveToken == address(0))
            revert Unauthorized();
            
        assetPool = IAssetPool(_assetPool);
        assetOracle = IAssetOracle(_assetOracle);
        reserveToken = IERC20(_reserveToken);
    }

    /**
     * @notice Get LP's current stake info
     */
    function getStakeInfo(address lp) external view returns (StakeInfo memory) {
        return lpStakes[lp];
    }

    /**
     * @notice Calculate required collateral for given asset amount
     */
    function getRequiredCollateral(uint256 assetAmount) public view returns (uint256) {
        uint256 assetValue = (assetAmount * assetOracle.assetPrice()) / PRECISION;
        return (assetValue * MIN_COLLATERAL_RATIO) / 100_00;
    }

    /**
     * @notice Calculate current collateral ratio for an LP
     */
    function getCurrentRatio(address lp) public view returns (uint256) {
        StakeInfo storage info = lpStakes[lp];
        if (info.assetsHeld == 0) return 0;
        
        uint256 assetValue = (info.assetsHeld * assetOracle.assetPrice()) / PRECISION;
        return (info.stakedAmount * 100_00) / assetValue;
    }

    /**
     * @notice Stake collateral
     */
    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        
        reserveToken.transferFrom(msg.sender, address(this), amount);
        
        lpStakes[msg.sender].stakedAmount += amount;
        
        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Withdraw excess collateral
     */
    function withdraw(uint256 amount) external nonReentrant {
        StakeInfo storage info = lpStakes[msg.sender];
        
        if (amount == 0 || amount > info.stakedAmount) 
            revert ZeroAmount();
            
        uint256 assetValue = (info.assetsHeld * assetOracle.assetPrice()) / PRECISION;
        uint256 remainingRatio = ((info.stakedAmount - amount) * 100_00) / assetValue;
        
        if (remainingRatio < MIN_COLLATERAL_RATIO)
            revert InsufficientCollateral(remainingRatio, MIN_COLLATERAL_RATIO);
        
        info.stakedAmount -= amount;
        reserveToken.transfer(msg.sender, amount);
        
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Update LP's asset position from pool
     */
    function updateLPPosition(address lp, uint256 newAssetAmount) external {
        if (msg.sender != address(assetPool)) 
            revert Unauthorized();
            
        StakeInfo storage info = lpStakes[lp];
        info.assetsHeld = newAssetAmount;
        
        uint256 currentRatio = getCurrentRatio(lp);
        
        // Check minimum ratio
        if (currentRatio < MIN_COLLATERAL_RATIO)
            revert InsufficientCollateral(currentRatio, MIN_COLLATERAL_RATIO);
            
        // Check warning threshold
        if (currentRatio < COLLATERAL_THRESHOLD) {
            uint256 assetValue = (newAssetAmount * assetOracle.assetPrice()) / PRECISION;
            uint256 requiredTopUp = (assetValue * MIN_COLLATERAL_RATIO / 100_00) - info.stakedAmount;
            emit CollateralWarning(lp, currentRatio, requiredTopUp);
        }
        
        emit PositionUpdated(lp, newAssetAmount);
    }

    /**
     * @notice Submit rebalance price
     */
    function submitRebalancePrice(uint256 price) external {
        if (lpStakes[msg.sender].assetsHeld == 0)
            revert Unauthorized();
            
        uint256 oraclePrice = assetOracle.assetPrice();
        uint256 deviation = calculateDeviation(price, oraclePrice);
        
        if (deviation > MAX_PRICE_DEVIATION)
            revert PriceDeviationTooHigh(price, oraclePrice);
            
        lpStakes[msg.sender].lastRebalanceTime = block.timestamp;
        
        emit RebalancePriceSubmitted(msg.sender, price);
    }

    /**
     * @notice Deduct rebalance amount from stake
     */
    function deductRebalanceAmount(address lp, uint256 amount) external {
        if (msg.sender != address(assetPool))
            revert Unauthorized();
            
        StakeInfo storage info = lpStakes[lp];
        
        if (amount > info.stakedAmount)
            revert InsufficientCollateral(info.stakedAmount, amount);
            
        info.stakedAmount -= amount;
        reserveToken.transfer(address(assetPool), amount);
        
        // Check remaining ratio
        uint256 currentRatio = getCurrentRatio(lp);
        if (currentRatio < MIN_COLLATERAL_RATIO)
            revert InsufficientCollateral(currentRatio, MIN_COLLATERAL_RATIO);
            
        emit RebalanceDeducted(lp, amount);
    }

    /**
     * @notice Calculate deviation between two prices
     */
    function calculateDeviation(uint256 price1, uint256 price2) 
        internal pure returns (uint256) 
    {
        if (price1 > price2) {
            return ((price1 - price2) * 100_00) / price2;
        }
        return ((price2 - price1) * 100_00) / price2;
    }
}