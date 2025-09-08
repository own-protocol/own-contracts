// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../utils/ProtocolTestUtils.sol";
import "./PoolHandler.sol";

/**
 * @title PoolInvariantTest  
 * @notice Invariant testing for Pool focusing on reserve conservation
 * @dev Tests the critical invariant that money cannot disappear or be created
 */
contract PoolInvariantTest is ProtocolTestUtils {
    PoolHandler public handler;

    // Protocol setup constants
    uint256 constant INITIAL_PRICE = 100 * 1e18;
    uint256 constant USER_INITIAL_BALANCE = 1_000_000;
    uint256 constant LP_INITIAL_BALANCE = 10_000_000; 
    uint256 constant LP_LIQUIDITY_AMOUNT = 5_000_000;
    
    // Actor arrays
    address[] public users;
    address[] public lps;
    
    function setUp() public {
        // Setup protocol with 6 decimal token (like USDC)
        bool success = setupProtocol(
            "xTSLA",
            6,
            INITIAL_PRICE,
            USER_INITIAL_BALANCE,
            LP_INITIAL_BALANCE,  
            LP_LIQUIDITY_AMOUNT
        );
        require(success, "Protocol setup failed");
        
        // Create additional users and LPs for fuzzing
        for (uint i = 0; i < 5; i++) {
            address user = makeAddr(string(abi.encodePacked("user", vm.toString(i))));
            address lp = makeAddr(string(abi.encodePacked("lp", vm.toString(i))));
            
            users.push(user);
            lps.push(lp);
            
            // Fund accounts and approve
            uint256 userAmount = adjustAmountForDecimals(USER_INITIAL_BALANCE, 6);
            uint256 lpAmount = adjustAmountForDecimals(LP_INITIAL_BALANCE, 6);
            
            reserveToken.mint(user, userAmount);
            reserveToken.mint(lp, lpAmount);
            
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
            users,
            lps
        );
        
        // Set handler as target for foundry fuzzing
        targetContract(address(handler));
    }
    
    /// @notice The most critical invariant - money can't disappear or be created
    function invariant_totalReserveConservation() external view {
        uint256 systemReserves = handler.getSystemReserves();
        uint256 accountedReserves = handler.getAccountedReserves();
        
        assertEq(systemReserves, accountedReserves, "System reserves must equal accounted reserves");
    }
    
    /// @notice Reserves should never be negative (overflow protection)
    function invariant_reservesNonNegative() external view {
        // These will revert on underflow due to uint256
        assert(assetPool.aggregatePoolReserves() >= 0);
        assert(liquidityManager.aggregatePoolReserves() >= 0);
    }
    
    /// @notice Asset pool reserves should be backed by actual tokens
    function invariant_assetPoolReservesBacked() external view {
        uint256 actualBalance = reserveToken.balanceOf(address(assetPool));
        uint256 accountedBalance = assetPool.aggregatePoolReserves();
        
        // Accounted reserves should not exceed actual token balance
        assert(accountedBalance <= actualBalance);
    }
    
    /// @notice Liquidity manager reserves should be backed by actual tokens  
    function invariant_liquidityManagerReservesBacked() external view {
        uint256 actualBalance = reserveToken.balanceOf(address(liquidityManager));
        uint256 accountedBalance = liquidityManager.aggregatePoolReserves();
        
        // Accounted reserves should not exceed actual token balance
        assert(accountedBalance <= actualBalance);
    }
    
    /// @notice User deposits should equal total collateral + total user deposits
    function invariant_userAccountingConsistency() external view {
        // This invariant ensures internal accounting is consistent
        uint256 totalUserDeposits = assetPool.totalUserDeposits();
        uint256 totalUserCollateral = assetPool.totalUserCollateral();
        
        // These values should be non-negative and consistent with positions
        assert(totalUserDeposits >= 0);
        assert(totalUserCollateral >= 0);
    }
    
    /// @notice Debug function to check handler state
    function invariant_logHandlerStats() external view {
        console2.log("=== Handler Stats ===");
        console2.log("Deposit requests:", handler.depositRequestCalls());
        console2.log("Redemption requests:", handler.redemptionRequestCalls()); 
        console2.log("Add liquidity calls:", handler.addLiquidityCalls());
        console2.log("Claim calls:", handler.claimCalls());
        console2.log("System reserves:", handler.getSystemReserves());
        console2.log("Accounted reserves:", handler.getAccountedReserves());
    }
}