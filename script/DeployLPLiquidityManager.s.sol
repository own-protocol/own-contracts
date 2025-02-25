// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/LPLiquidityManager.sol";

contract LPLiquidityManagerDeployScript is Script {
    function setUp() public {}

    function run() public {
        // Retrieve private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        LPLiquidityManager lpManager = new LPLiquidityManager();
        console.log("LPLiquidityManager deployed at:", address(lpManager));

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log deployment addresses to console
        console.log("Deployment completed!");
        console.log("----------------------------------------------------");
        console.log("LPLiquidityManager:", address(lpManager));
        console.log("----------------------------------------------------");
    }
}