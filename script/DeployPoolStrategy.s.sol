// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/strategies/DefaultPoolStrategy.sol";

contract DeployPoolStrategyScript is Script {
    // Strategy parameters - adjust these as needed
    uint256 constant REBALANCE_LENGTH = 60 minutes;       // 1 hour for onchain rebalancing period
    uint256 constant ORACLE_UPDATE_THRESHOLD = 15 minutes; // 15 minutes for oracle update threshold
    
    // Interest rate parameters
    uint256 constant BASE_INTEREST_RATE = 600;         // 6.00% base interest rate
    uint256 constant INTEREST_RATE1 = 1200;            // 12.00% tier 1 interest rate
    uint256 constant MAX_INTEREST_RATE = 4800;         // 48.00% maximum interest rate
    uint256 constant UTILIZATION_TIER1 = 7500;         // 75.00% first utilization tier
    uint256 constant UTILIZATION_TIER2 = 8500;         // 85.00% second utilization tier

    // Fee parameters
    uint256 constant PROTOCOL_FEE = 1000;              // 10.00% fee on interest
    
    // User collateral parameters
    uint256 constant USER_HEALTHY_RATIO = 2000;        // 20.00% healthy collateral ratio
    uint256 constant USER_LIQUIDATION_THRESHOLD = 1250; // 12.50% liquidation threshold
    
    // LP parameters
    uint256 constant LP_HEALTHY_RATIO = 2000;          // 20.00% healthy collateral ratio
    uint256 constant LP_LIQUIDATION_THRESHOLD = 1500;  // 15.00% liquidation threshold
    uint256 constant LP_LIQUIDATION_REWARD = 50;       // 0.50% liquidation reward
    uint256 constant LP_MIN_COMMITMENT = 100;         // Minimum LP commitment amount

    // Halt parameters
    uint256 constant HALT_THRESHOLD = 5 days;          // 5 days for halting the pool
    uint256 constant HALT_LIQUIDITY_PERCENT = 7000;    // 70.00% liquidity commitment to halt (scaled by 10000)
    uint256 constant HALT_FEE_PERCENT = 500;           // 5.00% fee on halted liquidity (scaled by 10000)
    uint256 constant HALT_REQUEST_THRESHOLD = 20;      // 20 cycles before halting the pool
    
    function run() public {
        // Get deployer private key from the environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address feeRecipient = 0xb914b344D8a2C88598A9C5905C9342a9678a67db;  // Set the fee recipient address here
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the DefaultPoolStrategy contract
        DefaultPoolStrategy poolStrategy = new DefaultPoolStrategy();
        
        // Set cycle parameters
        poolStrategy.setCycleParams(
            REBALANCE_LENGTH,
            ORACLE_UPDATE_THRESHOLD
        );

        // Set halt parameters
        poolStrategy.setHaltParams(
            HALT_THRESHOLD,
            HALT_LIQUIDITY_PERCENT,
            HALT_FEE_PERCENT,
            HALT_REQUEST_THRESHOLD
        );

        // Set interest rate parameters
        poolStrategy.setInterestRateParams(
            BASE_INTEREST_RATE,
            INTEREST_RATE1,
            MAX_INTEREST_RATE,
            UTILIZATION_TIER1,
            UTILIZATION_TIER2
        );
        
        // Set fee parameters
        poolStrategy.setProtocolFeeParams(
            PROTOCOL_FEE,
            feeRecipient
        );
        
        // Set user collateral parameters
        poolStrategy.setUserCollateralParams(
            USER_HEALTHY_RATIO,
            USER_LIQUIDATION_THRESHOLD
        );
        
        // Set LP liquidity parameters
        poolStrategy.setLPLiquidityParams(
            LP_HEALTHY_RATIO,
            LP_LIQUIDATION_THRESHOLD,
            LP_LIQUIDATION_REWARD,
            LP_MIN_COMMITMENT
        );
        
        // Optionally set yield-bearing flag if needed
        // poolStrategy.setIsYieldBearing();
        
        // Stop broadcasting transactions
        vm.stopBroadcast();
        
        // Log deployment addresses and important parameters
        console.log("Deployment completed!");
        console.log("----------------------------------------------------");
        console.log("DefaultPoolStrategy deployed at:", address(poolStrategy));
        console.log("----------------------------------------------------");
        console.log("Parameters:");
        console.log("Rebalance Length:", REBALANCE_LENGTH, "seconds");
        console.log("Oracle Update Threshold:", ORACLE_UPDATE_THRESHOLD, "seconds");
        console.log("Halt Threshold:", HALT_THRESHOLD, "seconds");
        console.log("Base Interest Rate:", BASE_INTEREST_RATE / 100, "%");
        console.log("Tier 1 Interest Rate:", INTEREST_RATE1 / 100, "%");
        console.log("Max Interest Rate:", MAX_INTEREST_RATE / 100, "%");
        console.log("Protocol Fee:", PROTOCOL_FEE / 100, "%");
        console.log("Fee Recipient:", feeRecipient);
    }
}