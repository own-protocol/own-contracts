// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/DefaultInterestRateStrategy.sol";

contract DefaultInterestRateStrategyDeployScript is Script {
    function setUp() public {}

    function run() public {
        // Retrieve private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Define parameters for DefaultInterestRateStrategy
        uint256 baseRate = 6_00;
        uint256 maxRate = 36_00;
        uint256 utilTier1 = 50_00;
        uint256 utilTier2 = 75_00;
        uint256 maxUtil = 95_00;
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        DefaultInterestRateStrategy interestRateStrategy = new DefaultInterestRateStrategy(
            baseRate,
            maxRate,
            utilTier1,
            utilTier2,
            maxUtil
        );
        
        console.log("DefaultInterestRateStrategy deployed at:", address(interestRateStrategy));

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log deployment addresses and parameters to console
        console.log("Deployment completed!");
        console.log("----------------------------------------------------");
        console.log("DefaultInterestRateStrategy:", address(interestRateStrategy));
    }
}