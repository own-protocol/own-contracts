// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/ProtocolRegistry.sol";

contract DeployProtocolRegistryScript is Script {
    function setUp() public {}

    function run() public {
        // Retrieve private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Get the deployer address
        address deployer = vm.addr(deployerPrivateKey);

        // Deploy the ProtocolRegistry contract
        ProtocolRegistry registry = new ProtocolRegistry(deployer);
        console.log("ProtocolRegistry deployed at:", address(registry));

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log deployment addresses to console
        console.log("Deployment completed!");
        console.log("----------------------------------------------------");
        console.log("ProtocolRegistry:", address(registry));
        console.log("----------------------------------------------------");
    }
}