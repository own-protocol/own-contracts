// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "../../src/protocol/strategies/DefaultPoolStrategy.sol";

/**
 * @title MockPoolStrategy
 * @notice Mock implementation of pool strategy for testing
 */
contract MockPoolStrategy is DefaultPoolStrategy {
    constructor() {
        // Set default values for tests
        rebalanceLength = 1 days;
        oracleUpdateThreshold = 15 minutes;
        haltThreshold = 5 days;
        
        // Set interest rate parameters
        baseInterestRate = 900; // 9%
        interestRate1 = 1800;   // 18%
        maxInterestRate = 7200; // 72%
        utilizationTier1 = 6500; // 65%
        utilizationTier2 = 8500; // 85%
        
        // Set fee parameters  
        protocolFeePercentage = 1000; // 10%
        feeRecipient = address(this);
        
        // Set user collateral parameters
        userHealthyCollateralRatio = 2000; // 20%
        userLiquidationThreshold = 1250;  // 12.5%
        
        // Set LP parameters
        lpHealthyLiquidityRatio = 3000;  // 30%
        lpLiquidationThreshold = 2000;   // 20%
        lpLiquidationReward = 50;        // 0.5%
    }
}