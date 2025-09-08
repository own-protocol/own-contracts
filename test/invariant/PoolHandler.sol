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

/**
 * @title PoolHandler
 * @notice Handler contract for invariant testing of Pool
 * @dev Fuzzes core protocol actions while maintaining the reserve conservation invariant
 */
contract PoolHandler is Test {
    AssetPool public assetPool;
    PoolLiquidityManager public liquidityManager;
    PoolCycleManager public cycleManager;
    MockERC20 public reserveToken;
    xToken public assetToken;
    
    // Track actors for realistic fuzzing
    address[] public users;
    address[] public lps;
    
    // Constants
    uint256 constant MAX_AMOUNT = 1e12; // Reasonable max to prevent overflow
    uint256 constant MIN_AMOUNT = 1e3;  // Minimum viable amount
    uint256 constant BPS = 10000;
    
    // Stats for debugging
    uint256 public depositRequestCalls;
    uint256 public redemptionRequestCalls;
    uint256 public addLiquidityCalls;
    uint256 public claimCalls;
    
    constructor(
        AssetPool _assetPool,
        PoolLiquidityManager _liquidityManager, 
        PoolCycleManager _cycleManager,
        MockERC20 _reserveToken,
        xToken _assetToken,
        address[] memory _users,
        address[] memory _lps
    ) {
        assetPool = _assetPool;
        liquidityManager = _liquidityManager;
        cycleManager = _cycleManager;
        reserveToken = _reserveToken;
        assetToken = _assetToken;
        users = _users;
        lps = _lps;
    }
    
    modifier useActor(address[] memory actors, uint256 actorSeed) {
        vm.startPrank(actors[bound(actorSeed, 0, actors.length - 1)]);
        _;
        vm.stopPrank();
    }
    
    modifier validAmount(uint256 amount) {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        _;
    }
    
    /// @notice User deposits funds
    function depositRequest(uint256 userSeed, uint256 amount, uint256 collateralRatio) 
        external 
        useActor(users, userSeed)
        validAmount(amount)
    {
        // Bound collateral ratio to reasonable range (10% - 50%)
        collateralRatio = bound(collateralRatio, 1000, 5000);
        uint256 collateralAmount = (amount * collateralRatio) / BPS;
        
        // Ensure user has enough balance
        address user = users[bound(userSeed, 0, users.length - 1)];
        uint256 totalNeeded = amount + collateralAmount;
        if (reserveToken.balanceOf(user) < totalNeeded) {
            reserveToken.mint(user, totalNeeded);
        }
        
        try assetPool.depositRequest(amount, collateralAmount) {
            depositRequestCalls++;
        } catch {
            // Ignore failed calls - they shouldn't break invariants
        }
    }
    
    /// @notice User redeems assets
    function redemptionRequest(uint256 userSeed, uint256 amount) 
        external 
        useActor(users, userSeed)
        validAmount(amount)
    {
        address user = users[bound(userSeed, 0, users.length - 1)];
        uint256 userBalance = assetToken.balanceOf(user);
        
        if (userBalance == 0) return;
        
        amount = bound(amount, 1, userBalance);
        
        try assetPool.redemptionRequest(amount) {
            redemptionRequestCalls++;
        } catch {
            // Ignore failed calls
        }
    }
    
    /// @notice LP adds liquidity
    function addLiquidity(uint256 lpSeed, uint256 amount) 
        external 
        useActor(lps, lpSeed)
        validAmount(amount)
    {
        address lp = lps[bound(lpSeed, 0, lps.length - 1)];
        
        // Ensure LP has enough balance
        if (reserveToken.balanceOf(lp) < amount) {
            reserveToken.mint(lp, amount);
        }
        
        try liquidityManager.addLiquidity(amount) {
            addLiquidityCalls++;
        } catch {
            // Ignore failed calls
        }
    }
    
    /// @notice User claims assets after deposit
    function claimAsset(uint256 userSeed) 
        external 
        useActor(users, userSeed)
    {
        address user = users[bound(userSeed, 0, users.length - 1)];
        
        try assetPool.claimAsset(user) {
            claimCalls++;
        } catch {
            // Ignore failed calls
        }
    }
    
    /// @notice User claims reserves after redemption
    function claimReserve(uint256 userSeed) 
        external 
        useActor(users, userSeed)
    {
        address user = users[bound(userSeed, 0, users.length - 1)];
        
        try assetPool.claimReserve(user) {
            claimCalls++;
        } catch {
            // Ignore failed calls
        }
    }
    
    /// @notice Get total system reserves for invariant checking
    function getSystemReserves() external view returns (uint256) {
        return reserveToken.balanceOf(address(assetPool)) + 
               reserveToken.balanceOf(address(liquidityManager));
    }
    
    /// @notice Get total accounted reserves for invariant checking  
    function getAccountedReserves() external view returns (uint256) {
        return assetPool.aggregatePoolReserves() + 
               liquidityManager.aggregatePoolReserves();
    }
}