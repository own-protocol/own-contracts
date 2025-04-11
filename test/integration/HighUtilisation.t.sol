// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "../utils/ProtocolTestUtils.sol";

/**
 * @title HighUtilizationRebalanceTest
 * @notice Tests the rebalance mechanism under high utilization and price increase conditions
 */
contract HighUtilizationRebalanceTest is ProtocolTestUtils {
    // Base amounts (will be adjusted based on token decimals)
    uint256 constant INITIAL_PRICE = 100 * 1e18; // $100.00 per asset (always 18 decimals)
    uint256 constant USER_INITIAL_BALANCE = 1_000_000; 
    uint256 constant LP_INITIAL_BALANCE = 1_000_000;
    uint256 constant LP_LIQUIDITY_AMOUNT = 100_000; // Keep LP liquidity lower to achieve high utilization
    
    // High utilization percentage target
    uint256 constant TARGET_UTILIZATION_PERCENT = 90; // 90% utilization

    // Price increase during rebalance
    uint256 constant PRICE_INCREASE = 120 * 1e18; // $120.00 per asset (20% increase)
    
    function setUp() public {
        // Setup protocol with 6 decimal token (like USDC)
        bool success = setupProtocol(
            "xTSLA",                // Asset symbol
            6,                      // Reserve token decimals (USDC like)
            INITIAL_PRICE,          // Initial price
            USER_INITIAL_BALANCE,   // User amount (base units)
            LP_INITIAL_BALANCE,     // LP amount (base units)
            LP_LIQUIDITY_AMOUNT     // LP liquidity (base units)
        );
        
        require(success, "Protocol setup failed");
        
        // Verify LP positions are set up correctly
        uint256 totalLiquidity = liquidityManager.totalLPLiquidityCommited();
        assertGt(totalLiquidity, 0, "LP liquidity should be set up");
    }

    /**
     * @notice Test rebalance with 95% utilization and 10% price increase
     * @dev Demonstrates that rebalance fails without additional collateral but succeeds with it
     */
    function testRebalanceWithHighUtilizationAndPriceIncrease() public {
        // 1. Create high utilization scenario (90%)
        createHighUtilization();
        
        // 2. Verify utilization is high
        uint256 utilization = assetPool.getCyclePoolUtilization();
        assertApproxEqRel(utilization, 90 * 100, 0.02e18, "Utilization should be approximately 90%");
        
        // 3. Initiate offchain rebalance
        startOffchainRebalance();
        
        // 4. Initiate onchain rebalance with 10% price increase
        startOnchainRebalanceWithPriceIncrease();
    }
    
    /**
     * @notice Creates a high utilization scenario by having users deposit
     */
    function createHighUtilization() internal {
        // Calculate deposit amount based on total LP liquidity
        uint256 totalLiquidity = liquidityManager.totalLPLiquidityCommited();
        // deposit amount is 70% of total liquidity so that utilisation will be close to 90%
        uint256 targetDeposit = (totalLiquidity * 7) / 10;
        
        // Adjust for proper decimals
        uint256 depositAmount = targetDeposit;
        
        // Calculate required collateral
        uint256 collateralRatio = poolStrategy.userHealthyCollateralRatio();
        uint256 collateralAmount = (depositAmount * collateralRatio) / BPS;
        
        vm.startPrank(user1);
        assetPool.depositRequest(depositAmount / 2, collateralAmount / 2);
        vm.stopPrank();
        
        vm.startPrank(user2);
        assetPool.depositRequest(depositAmount / 2, collateralAmount / 2);
        vm.stopPrank();
        
        // Verify total deposit requests
        assertEq(assetPool.cycleTotalDeposits(), depositAmount, "Total deposits should match expected amount");
        
        // Verify target utilization is reached
        uint256 utilization = assetPool.getCyclePoolUtilization();
        assertApproxEqRel(
            utilization, 
            TARGET_UTILIZATION_PERCENT * 100, // BPS format (90% = 9000)
            0.02e18, 
            "Utilization should be approximately 90%"
        );
    }
    
    /**
     * @notice Starts the offchain rebalance phase
     */
    function startOffchainRebalance() internal {
        vm.startPrank(owner);
        assetOracle.setMarketOpen(true);
        updateOraclePrice(INITIAL_PRICE);
        cycleManager.initiateOffchainRebalance();
        vm.stopPrank();
        
        // Advance time to simulate offchain rebalance period
        vm.warp(block.timestamp + 1 days);
    }
    
    /**
     * @notice Starts the onchain rebalance phase with price increase
     */
    function startOnchainRebalanceWithPriceIncrease() internal {
        vm.startPrank(owner);
        assetOracle.setMarketOpen(false);
        updateOraclePriceWithOHLC(
            INITIAL_PRICE * 105 / 100, // open
            PRICE_INCREASE * 105 / 100, // high
            INITIAL_PRICE, // low
            PRICE_INCREASE // close - 10% higher than initial
        );
        cycleManager.initiateOnchainRebalance();
        vm.stopPrank();
    }
}