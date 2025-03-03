// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/PoolLiquidityManager.sol";

contract PoolLiquidityManagerDeployScript is Script {
    function setUp() public {}

    function run() public {
        // Retrieve private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        PoolLiquidityManager poolLiquidityManager = new PoolLiquidityManager();
        console.log("PoolLiquidityManager deployed at:", address(poolLiquidityManager));

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log deployment addresses to console
        console.log("Deployment completed!");
        console.log("----------------------------------------------------");
        console.log("PoolLiquidityManager:", address(poolLiquidityManager));
        console.log("----------------------------------------------------");
    }
}