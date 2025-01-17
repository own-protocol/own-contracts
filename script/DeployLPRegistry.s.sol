// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/LPRegistry.sol";

contract LPRegistryDeployScript is Script {
    function setUp() public {}

    function run() public {
        // Retrieve private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        LPRegistry lpRegistry = new LPRegistry();
        console.log("LPRegistry deployed at:", address(lpRegistry));

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log deployment addresses to console
        console.log("Deployment completed!");
        console.log("----------------------------------------------------");
        console.log("LPRegistry:", address(lpRegistry));
        console.log("----------------------------------------------------");
    }
}