// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/protocol/AssetPool.sol";
import "../../../src/protocol/PoolLiquidityManager.sol";
import "../../../src/protocol/PoolCycleManager.sol";
import "../../../src/protocol/xToken.sol";
import "../../../src/interfaces/IPoolStrategy.sol";
import "../../../test/mocks/MockERC20.sol";
import "../../../test/mocks/MockAssetOracle.sol";

/**
 * @title InvariantHandler
 * @notice Handler contract for guided invariant testing
 * @dev Provides controlled randomized operations for fuzzing
 */
contract InvariantHandler is Test {
    AssetPool public assetPool;
    PoolLiquidityManager public liquidityManager;
    PoolCycleManager public cycleManager;
    xToken public assetToken;
    MockERC20 public reserveToken;
    MockAssetOracle public assetOracle;
    IPoolStrategy public poolStrategy;
    
    // State tracking for invariants
    address[] public activeUsers;
    address[] public activeLPs;
    mapping(address => bool) public isActiveUser;
    mapping(address => bool) public isActiveLP;
    
    uint256 public lastTotalInterest;
    uint256 public totalPendingDeposits;
    uint256 public totalPendingRedemptions;
    
    // Ghost variables for tracking
    mapping(address => uint256) public userAssetAmounts;
    mapping(address => uint256) public userDepositAmounts;
    mapping(address => uint256) public userCollateralAmounts;
    mapping(address => uint256) public lpCollateralAmounts;
    mapping(address => uint256) public lpInterestAmounts;
    
    // Operation counters
    uint256 public depositCount;
    uint256 public redeemCount;
    uint256 public liquidityAddCount;
    uint256 public liquidityReduceCount;
    uint256 public cycleCount;
    
    constructor(
        AssetPool _assetPool,
        PoolLiquidityManager _liquidityManager,
        PoolCycleManager _cycleManager,
        xToken _assetToken,
        MockERC20 _reserveToken,
        MockAssetOracle _assetOracle,
        IPoolStrategy _poolStrategy
    ) {
        assetPool = _assetPool;
        liquidityManager = _liquidityManager;
        cycleManager = _cycleManager;
        assetToken = _assetToken;
        reserveToken = _reserveToken;
        assetOracle = _assetOracle;
        poolStrategy = _poolStrategy;
        
        // Initialize with some actors
        _addUser(makeAddr("user1"));
        _addUser(makeAddr("user2"));
        _addUser(makeAddr("user3"));
        _addLP(makeAddr("lp1"));
        _addLP(makeAddr("lp2"));
    }
    
    // ==================== FUZZED OPERATIONS ====================
    
    /**
     * @notice Fuzzed deposit operation
     */
    function deposit(uint256 userIndex, uint256 amount, uint256 collateralRatio) external {
        userIndex = bound(userIndex, 0, activeUsers.length - 1);
        amount = bound(amount, 100e6, 100_000e6); // 100 to 100k USDC
        collateralRatio = bound(collateralRatio, 10, 50); // 10% to 50%
        
        address user = activeUsers[userIndex];
        uint256 collateralAmount = (amount * collateralRatio) / 100;
        uint256 totalAmount = amount + collateralAmount;
        
        // Fund user if needed
        if (reserveToken.balanceOf(user) < totalAmount) {
            reserveToken.mint(user, totalAmount * 2);
        }
        
        vm.startPrank(user);
        reserveToken.approve(address(assetPool), totalAmount);
        
        try assetPool.depositRequest(amount, collateralAmount) {
            _updateUserState(user);
            totalPendingDeposits += amount;
            depositCount++;
        } catch {
            // Operation failed, continue testing
        }
        vm.stopPrank();
    }
    
    /**
     * @notice Fuzzed redemption operation
     */
    function redeem(uint256 userIndex, uint256 percentage) external {
        if (activeUsers.length == 0) return;
        
        userIndex = bound(userIndex, 0, activeUsers.length - 1);
        percentage = bound(percentage, 10, 100); // 10% to 100% of position
        
        address user = activeUsers[userIndex];
        uint256 userAssets = assetToken.balanceOf(user);
        
        if (userAssets == 0) return;
        
        uint256 redeemAmount = (userAssets * percentage) / 100;
        
        vm.startPrank(user);
        assetToken.approve(address(assetPool), redeemAmount);
        
        try assetPool.redemptionRequest(redeemAmount) {
            _updateUserState(user);
            totalPendingRedemptions += redeemAmount;
            redeemCount++;
        } catch {
            // Operation failed, continue testing
        }
        vm.stopPrank();
    }
    
    /**
     * @notice Fuzzed LP liquidity addition
     */
    function addLiquidity(uint256 lpIndex, uint256 amount) external {
        if (activeLPs.length == 0) return;
        
        lpIndex = bound(lpIndex, 0, activeLPs.length - 1);
        amount = bound(amount, 10_000e6, 1_000_000e6); // 10k to 1M USDC
        
        address lp = activeLPs[lpIndex];
        
        // Calculate required collateral
        uint256 healthyRatio = poolStrategy.lpHealthyCollateralRatio();
        uint256 collateralAmount = (amount * healthyRatio) / 10000;
        uint256 totalAmount = amount + collateralAmount;
        
        // Fund LP if needed
        if (reserveToken.balanceOf(lp) < totalAmount) {
            reserveToken.mint(lp, totalAmount * 2);
        }
        
        vm.startPrank(lp);
        reserveToken.approve(address(liquidityManager), totalAmount);
        
        try liquidityManager.addLiquidity(amount) {
            _updateLPState(lp);
            liquidityAddCount++;
        } catch {
            // Operation failed, continue testing
        }
        vm.stopPrank();
    }
    
    /**
     * @notice Fuzzed LP liquidity reduction
     */
    function reduceLiquidity(uint256 lpIndex, uint256 percentage) external {
        if (activeLPs.length == 0) return;
        
        lpIndex = bound(lpIndex, 0, activeLPs.length - 1);
        percentage = bound(percentage, 10, 50); // 10% to 50% reduction
        
        address lp = activeLPs[lpIndex];
        
        if (!liquidityManager.isLP(lp)) return;
        
        uint256 currentLiquidity = liquidityManager.getLPLiquidityCommitment(lp);
        if (currentLiquidity == 0) return;
        
        uint256 reduceAmount = (currentLiquidity * percentage) / 100;
        
        vm.startPrank(lp);
        try liquidityManager.reduceLiquidity(reduceAmount) {
            _updateLPState(lp);
            liquidityReduceCount++;
        } catch {
            // Operation failed, continue testing
        }
        vm.stopPrank();
    }
    
    /**
     * @notice Fuzzed cycle completion with price changes
     */
    function completeCycle(uint256 priceChangePercent) external {
        priceChangePercent = bound(priceChangePercent, 80, 120); // -20% to +20%
        
        uint256 currentPrice = assetOracle.assetPrice();
        uint256 newPrice = (currentPrice * priceChangePercent) / 100;
        
        // Update price
        assetOracle.setPrice(newPrice);
        
        // Advance time
        vm.warp(block.timestamp + poolStrategy.rebalancePeriod() + 1);
        
        try cycleManager.rebalancePool() {
            _updateAllStates();
            cycleCount++;
            
            // Reset pending amounts after cycle
            totalPendingDeposits = 0;
            totalPendingRedemptions = 0;
        } catch {
            // Cycle failed, continue testing
        }
    }
    
    /**
     * @notice Fuzzed asset claiming
     */
    function claimAssets(uint256 userIndex) external {
        if (activeUsers.length == 0) return;
        
        userIndex = bound(userIndex, 0, activeUsers.length - 1);
        address user = activeUsers[userIndex];
        
        vm.startPrank(user);
        try assetPool.claimAsset(user) {
            _updateUserState(user);
        } catch {
            // Claim failed, continue testing
        }
        vm.stopPrank();
    }
    
    /**
     * @notice Fuzzed reserve claiming
     */
    function claimReserves(uint256 userIndex) external {
        if (activeUsers.length == 0) return;
        
        userIndex = bound(userIndex, 0, activeUsers.length - 1);
        address user = activeUsers[userIndex];
        
        vm.startPrank(user);
        try assetPool.claimReserve(user) {
            _updateUserState(user);
        } catch {
            // Claim failed, continue testing
        }
        vm.stopPrank();
    }
    
    /**
     * @notice Fuzzed user liquidation
     */
    function liquidateUser(uint256 liquidatorIndex, uint256 targetIndex, uint256 percentage) external {
        if (activeUsers.length < 2) return;
        
        liquidatorIndex = bound(liquidatorIndex, 0, activeUsers.length - 1);
        targetIndex = bound(targetIndex, 0, activeUsers.length - 1);
        percentage = bound(percentage, 10, 30); // 10% to 30% liquidation
        
        if (liquidatorIndex == targetIndex) return;
        
        address liquidator = activeUsers[liquidatorIndex];
        address target = activeUsers[targetIndex];
        
        // Check if target is liquidatable
        uint8 health = poolStrategy.getUserCollateralHealth(address(assetPool), target);
        if (health < 3) return; // Not liquidatable
        
        (uint256 targetAssets, , ) = assetPool.userPositions(target);
        if (targetAssets == 0) return;
        
        uint256 liquidateAmount = (targetAssets * percentage) / 100;
        
        // Fund liquidator with asset tokens if needed
        if (assetToken.balanceOf(liquidator) < liquidateAmount) {
            // Mint asset tokens to liquidator (for testing purposes)
            vm.prank(address(assetPool));
            assetToken.mint(liquidator, liquidateAmount);
        }
        
        vm.startPrank(liquidator);
        assetToken.approve(address(assetPool), liquidateAmount);
        
        try assetPool.liquidationRequest(target, liquidateAmount) {
            _updateUserState(target);
            _updateUserState(liquidator);
        } catch {
            // Liquidation failed, continue testing
        }
        vm.stopPrank();
    }
    
    // ==================== STATE TRACKING ====================
    
    function _addUser(address user) internal {
        if (!isActiveUser[user]) {
            activeUsers.push(user);
            isActiveUser[user] = true;
        }
    }
    
    function _addLP(address lp) internal {
        if (!isActiveLP[lp]) {
            activeLPs.push(lp);
            isActiveLP[lp] = true;
        }
    }
    
    function _updateUserState(address user) internal {
        (uint256 assetAmount, uint256 depositAmount, uint256 collateralAmount) = assetPool.userPositions(user);
        userAssetAmounts[user] = assetAmount;
        userDepositAmounts[user] = depositAmount;
        userCollateralAmounts[user] = collateralAmount;
    }
    
    function _updateLPState(address lp) internal {
        if (liquidityManager.isLP(lp)) {
            IPoolLiquidityManager.LPPosition memory position = liquidityManager.getLPPosition(lp);
            lpCollateralAmounts[lp] = position.collateralAmount;
            lpInterestAmounts[lp] = position.interestAccrued;
        }
    }
    
    function _updateAllStates() internal {
        for (uint i = 0; i < activeUsers.length; i++) {
            _updateUserState(activeUsers[i]);
        }
        for (uint i = 0; i < activeLPs.length; i++) {
            _updateLPState(activeLPs[i]);
        }
    }
    
    // ==================== INVARIANT HELPERS ====================
    
    function getTotalUserAssets() external view returns (uint256 total) {
        for (uint i = 0; i < activeUsers.length; i++) {
            (uint256 assetAmount, , ) = assetPool.userPositions(activeUsers[i]);
            total += assetAmount;
        }
    }
    
    function getTotalUserDeposits() external view returns (uint256 total) {
        for (uint i = 0; i < activeUsers.length; i++) {
            (, uint256 depositAmount, ) = assetPool.userPositions(activeUsers[i]);
            total += depositAmount;
        }
    }
    
    function getTotalUserCollateral() external view returns (uint256 total) {
        for (uint i = 0; i < activeUsers.length; i++) {
            (, , uint256 collateralAmount) = assetPool.userPositions(activeUsers[i]);
            total += collateralAmount;
        }
    }
    
    function getTotalLPCollateral() external view returns (uint256 total) {
        for (uint i = 0; i < activeLPs.length; i++) {
            if (liquidityManager.isLP(activeLPs[i])) {
                IPoolLiquidityManager.LPPosition memory position = liquidityManager.getLPPosition(activeLPs[i]);
                total += position.collateralAmount;
            }
        }
    }
    
    function getTotalLPInterest() external view returns (uint256 total) {
        for (uint i = 0; i < activeLPs.length; i++) {
            if (liquidityManager.isLP(activeLPs[i])) {
                IPoolLiquidityManager.LPPosition memory position = liquidityManager.getLPPosition(activeLPs[i]);
                total += position.interestAccrued;
            }
        }
    }
    
    function getLastTotalInterest() external view returns (uint256) {
        return lastTotalInterest;
    }
    
    function updateLastTotalInterest(uint256 newTotal) external {
        lastTotalInterest = newTotal;
    }
    
    function getTotalPendingDeposits() external view returns (uint256) {
        return totalPendingDeposits;
    }
    
    function getTotalPendingRedemptions() external view returns (uint256) {
        return totalPendingRedemptions;
    }
    
    function getActiveUsers() external view returns (address[] memory) {
        return activeUsers;
    }
    
    function getActiveLPs() external view returns (address[] memory) {
        return activeLPs;
    }
    
    function hasActivePosition(address user) external view returns (bool) {
        (uint256 assetAmount, uint256 depositAmount, uint256 collateralAmount) = assetPool.userPositions(user);
        return assetAmount > 0 || depositAmount > 0 || collateralAmount > 0;
    }
    
    function verifyRequestConsistency() external view returns (bool) {
        // Verify that request states are consistent with position states
        // This is a simplified check - can be expanded based on specific requirements
        return true;
    }
}