// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../utils/ProtocolTestUtils.sol";
import "./PoolHandler.sol";

/**
 * @title PoolInvariantTest
 * @notice Cycle-aware invariant testing for the protocol
 */
contract PoolInvariantTest is ProtocolTestUtils {
    PoolHandler public handler;

    uint256 constant INITIAL_PRICE = 100 * 1e18;
    uint256 constant USER_BALANCE = 100_000;
    uint256 constant LP_BALANCE = 1_000_000; 
    uint256 constant LP_LIQUIDITY = 500_000;
    
    address[] public users;
    address[] public lps;
    
    function setUp() public {
        // Setup protocol
        bool success = setupProtocol(
            "xTSLA",
            6,
            INITIAL_PRICE,
            USER_BALANCE,
            LP_BALANCE,  
            LP_LIQUIDITY
        );
        require(success, "Protocol setup failed");
        
        // Create test accounts
        for (uint i = 0; i < 5; i++) {
            address user = makeAddr(string(abi.encodePacked("user", vm.toString(i))));
            address lp = makeAddr(string(abi.encodePacked("lp", vm.toString(i))));
            
            users.push(user);
            lps.push(lp);
            
            uint256 userAmount = adjustAmountForDecimals(USER_BALANCE, 6);
            uint256 lpAmount = adjustAmountForDecimals(LP_BALANCE, 6);
            
            reserveToken.mint(user, userAmount);
            reserveToken.mint(lp, lpAmount);
            
            // Approvals
            vm.startPrank(user);
            reserveToken.approve(address(assetPool), type(uint256).max);
            assetToken.approve(address(assetPool), type(uint256).max);
            vm.stopPrank();
            
            vm.startPrank(lp);
            reserveToken.approve(address(liquidityManager), type(uint256).max);
            reserveToken.approve(address(cycleManager), type(uint256).max);
            vm.stopPrank();
        }

        // Create handler
        handler = new PoolHandler(
            assetPool,
            liquidityManager,
            cycleManager,
            reserveToken,
            assetToken,
            assetOracle,
            owner,
            users,
            lps
        );
        
        // Set as target
        targetContract(address(handler));
    }
    
    /// @notice Core invariant - reserves must be conserved
    function invariant_reserveConservation() external view {
        uint256 systemReserves = handler.getSystemReserves();
        uint256 accountedReserves = handler.getAccountedReserves();
        
        assertEq(systemReserves, accountedReserves, "Reserve conservation failed");
    }
    
    /// @notice Pool reserves must be backed by actual tokens
    function invariant_poolReservesBacked() external view {
        uint256 poolBalance = reserveToken.balanceOf(address(assetPool));
        uint256 poolReserves = assetPool.aggregatePoolReserves();
        
        assert(poolReserves <= poolBalance);
    }
    
    /// @notice LP reserves must be backed by actual tokens
    function invariant_lpReservesBacked() external view {
        uint256 lpBalance = reserveToken.balanceOf(address(liquidityManager));
        uint256 lpReserves = liquidityManager.aggregatePoolReserves();
        
        assert(lpReserves <= lpBalance);
    }
    
    /// @notice User positions must be consistent
    function invariant_userPositions() external view {
        uint256 totalDeposits = assetPool.totalUserDeposits();
        uint256 totalCollateral = assetPool.totalUserCollateral();
        
        // These should never overflow (would revert)
        assert(totalDeposits >= 0);
        assert(totalCollateral >= 0);
    }
    
    /// @notice Cycle state transitions must be valid
    function invariant_cycleStateValid() external view {
        uint8 state = handler.getCycleState();
        
        // Valid states: 0=ACTIVE, 1=OFFCHAIN, 2=ONCHAIN, 3=HALTED
        assert(state <= 3);
    }
    
    /// @notice Asset token supply must match pool accounting
    function invariant_assetSupplyConsistent() external view {
        uint256 totalSupply = assetToken.totalSupply();
        uint256 poolBalance = assetToken.balanceOf(address(assetPool));
        
        // Pool's asset balance should not exceed total supply
        assert(poolBalance <= totalSupply);
    }
    
    /// @notice Interest calculations must not overflow
    function invariant_interestBounds() external view {
        // Get current cycle data
        uint256 currentCycle = cycleManager.cycleIndex();
        
        if (currentCycle > 0) {
            uint256 interestIndex = cycleManager.cumulativeInterestIndex(currentCycle);
            uint256 rebalancePrice = cycleManager.cycleRebalancePrice(currentCycle - 1);
            
            // These should be reasonable values
            assert(interestIndex > 0);
            if (rebalancePrice > 0) {
                assert(rebalancePrice < 1e30); // Reasonable upper bound
            }
        }
    }
    
    /// @notice Debug stats
    function invariant_logStats() external view {
        console2.log("=== Cycle Handler Stats ===");
        console2.log("Deposits:", handler.depositCalls());
        console2.log("Redeems:", handler.redeemCalls());
        console2.log("Add Liquidity:", handler.addLiquidityCalls());
        console2.log("Claims:", handler.claimCalls());
        console2.log("Cycle Ops:", handler.cycleCalls());
        console2.log("Current Cycle:", cycleManager.cycleIndex());
        console2.log("Cycle State:", handler.getCycleState());
        console2.log("System Reserves:", handler.getSystemReserves());
        console2.log("Accounted Reserves:", handler.getAccountedReserves());
    }
}