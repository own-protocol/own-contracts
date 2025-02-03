// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/AssetPoolImplementation.sol";

contract AssetPoolImplementationDeployScript is Script {
    function setUp() public {}

    function run() public {
        // Retrieve private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        AssetPoolImplementation assetPoolImplementation = new AssetPoolImplementation();
        console.log("AssetPoolImplementation deployed at:", address(assetPoolImplementation));

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log deployment addresses to console
        console.log("Deployment completed!");
        console.log("----------------------------------------------------");
        console.log("AssetPoolImplementation:", address(assetPoolImplementation));
        console.log("----------------------------------------------------");
    }
}