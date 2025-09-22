// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import "../../src/protocol/AssetPool.sol";
import "../../src/protocol/PoolLiquidityManager.sol";
import "../../src/protocol/PoolCycleManager.sol";
import "../../src/interfaces/IAssetPool.sol";
import "../../src/interfaces/IPoolLiquidityManager.sol";
import "../../src/interfaces/IPoolCycleManager.sol";
import "../../src/protocol/xToken.sol";
import "../mocks/MockERC20.sol";
import "../mocks/MockAssetOracle.sol";

/**
 * @title PoolHandler
 * @notice Cycle-aware pool handler for invariant testing
 */
contract PoolHandler is Test {
    AssetPool public pool;
    PoolLiquidityManager public liquidityManager;
    PoolCycleManager public cycleManager;
    MockERC20 public reserveToken;
    xToken public assetToken;
    MockAssetOracle public oracle;
    address public owner;
    
    address[] public users;
    address[] public lps;
    
    uint256 constant MAX_AMOUNT = 1e12;
    uint256 constant MIN_AMOUNT = 1e3;
    uint256 constant BPS = 10000;
    uint256 constant PRECISION = 1e18;
    
    // Tracking
    uint256 public depositCalls;
    uint256 public redeemCalls;
    uint256 public addLiquidityCalls;
    uint256 public claimCalls;
    uint256 public cycleCalls;
    
    constructor(
        AssetPool _pool,
        PoolLiquidityManager _liquidityManager, 
        PoolCycleManager _cycleManager,
        MockERC20 _reserveToken,
        xToken _assetToken,
        MockAssetOracle _oracle,
        address _owner,
        address[] memory _users,
        address[] memory _lps
    ) {
        pool = _pool;
        liquidityManager = _liquidityManager;
        cycleManager = _cycleManager;
        reserveToken = _reserveToken;
        assetToken = _assetToken;
        oracle = _oracle;
        owner = _owner;
        users = _users;
        lps = _lps;
    }
    
    function _boundAmount(uint256 amount) internal pure returns (uint256) {
        return bound(amount, MIN_AMOUNT, MAX_AMOUNT);
    }
    
    function _getUser(uint256 seed) internal view returns (address) {
        return users[bound(seed, 0, users.length - 1)];
    }
    
    function _getLP(uint256 seed) internal view returns (address) {
        return lps[bound(seed, 0, lps.length - 1)];
    }
    
    function _ensureBalance(address user, uint256 amount) internal {
        if (reserveToken.balanceOf(user) < amount) {
            reserveToken.mint(user, amount * 2);
        }
    }
    
    // User deposits (only in ACTIVE state)
    function deposit(uint256 userSeed, uint256 amount, uint256 collateralRatio) external {
        if (!_isActive()) return;
        
        amount = _boundAmount(amount);
        collateralRatio = bound(collateralRatio, 1000, 5000); // 10-50%
        uint256 collateral = (amount * collateralRatio) / BPS;
        uint256 total = amount + collateral;
        
        address user = _getUser(userSeed);
        _ensureBalance(user, total);
        
        vm.startPrank(user);
        try pool.depositRequest(amount, collateral) {
            depositCalls++;
        } catch {}
        vm.stopPrank();
    }
    
    // User redeems (only in ACTIVE state)
    function redeem(uint256 userSeed, uint256 amount) external {
        if (!_isActive()) return;
        
        address user = _getUser(userSeed);
        uint256 balance = assetToken.balanceOf(user);
        if (balance == 0) return;
        
        amount = bound(amount, 1, balance);
        
        vm.startPrank(user);
        try pool.redemptionRequest(amount) {
            redeemCalls++;
        } catch {}
        vm.stopPrank();
    }
    
    // LP adds liquidity (only in ACTIVE state)
    function addLiquidity(uint256 lpSeed, uint256 amount) external {
        if (!_isActive()) return;
        
        amount = _boundAmount(amount);
        address lp = _getLP(lpSeed);
        _ensureBalance(lp, amount);
        
        vm.startPrank(lp);
        try liquidityManager.addLiquidity(amount) {
            addLiquidityCalls++;
        } catch {}
        vm.stopPrank();
    }
    
    // Claim assets (any state except during transitions)
    function claimAsset(uint256 userSeed) external {
        address user = _getUser(userSeed);
        
        vm.startPrank(user);
        try pool.claimAsset(user) {
            claimCalls++;
        } catch {}
        vm.stopPrank();
    }
    
    // Claim reserves (any state except during transitions)
    function claimReserve(uint256 userSeed) external {
        address user = _getUser(userSeed);
        
        vm.startPrank(user);
        try pool.claimReserve(user) {
            claimCalls++;
        } catch {}
        vm.stopPrank();
    }
    
    // Start offchain rebalance (owner only, from ACTIVE)
    function startOffchainRebalance(uint256 priceSeed) external {
        if (!_isActive()) return;
        
        uint256 price = bound(priceSeed, PRECISION / 2, PRECISION * 2); // 0.5x to 2x
        
        vm.startPrank(owner);
        oracle.setMarketOpen(true);
        oracle.setOHLCData(price, price, price, price, block.timestamp);
        try cycleManager.initiateOffchainRebalance() {
            cycleCalls++;
        } catch {}
        vm.stopPrank();
    }
    
    // Start onchain rebalance (owner only, from OFFCHAIN_REBALANCING)
    function startOnchainRebalance(uint256 priceSeed) external {
        if (cycleManager.cycleState() != IPoolCycleManager.CycleState.POOL_REBALANCING_OFFCHAIN) return;
        
        uint256 price = bound(priceSeed, PRECISION / 2, PRECISION * 2);
        
        vm.warp(block.timestamp + 1 hours); // Simulate time passage
        
        vm.startPrank(owner);
        oracle.setMarketOpen(false);
        oracle.setOHLCData(price, price, price, price, block.timestamp);
        try cycleManager.initiateOnchainRebalance() {
            cycleCalls++;
        } catch {}
        vm.stopPrank();
    }
    
    // LP rebalances (only in ONCHAIN_REBALANCING)
    function rebalance(uint256 lpSeed, uint256 priceSeed) external {
        if (cycleManager.cycleState() != IPoolCycleManager.CycleState.POOL_REBALANCING_ONCHAIN) return;
        
        address lp = _getLP(lpSeed);
        uint256 price = bound(priceSeed, PRECISION / 2, PRECISION * 2);
        
        vm.startPrank(lp);
        try cycleManager.rebalancePool(lp, price) {
            cycleCalls++;
        } catch {}
        vm.stopPrank();
    }
    
    // Time progression
    function skipTime(uint256 timeSeed) external {
        uint256 timeSkip = bound(timeSeed, 1 minutes, 24 hours);
        vm.warp(block.timestamp + timeSkip);
    }
    
    // Price updates
    function updatePrice(uint256 priceSeed) external {
        uint256 price = bound(priceSeed, PRECISION / 2, PRECISION * 2);
        
        vm.startPrank(owner);
        oracle.setOHLCData(price, price, price, price, block.timestamp);
        vm.stopPrank();
    }
    
    function _isActive() internal view returns (bool) {
        return cycleManager.cycleState() == IPoolCycleManager.CycleState.POOL_ACTIVE;
    }
    
    // Invariant helpers
    function getSystemReserves() external view returns (uint256) {
        return reserveToken.balanceOf(address(pool)) + 
               reserveToken.balanceOf(address(liquidityManager));
    }
    
    function getAccountedReserves() external view returns (uint256) {
        return pool.aggregatePoolReserves() + 
               liquidityManager.aggregatePoolReserves();
    }
    
    function getCycleState() external view returns (uint8) {
        return uint8(cycleManager.cycleState());
    }
}