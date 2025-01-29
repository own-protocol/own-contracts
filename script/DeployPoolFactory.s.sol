// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/AssetPoolFactory.sol";

contract AssetPoolDeployScript is Script {
    address constant lpRegistry = 0xfA6bD97e1662Df409d15EEaa5654BDA6b319D721; 
    address constant assetPoolImplementation = 0x6D2a971099314b2dB9a78138ac1b3Bd52AfB597e;

    function setUp() public {}

    function run() public {
        // Retrieve private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy AssetPoolFactory with the LPRegistry address
        AssetPoolFactory poolFactory = new AssetPoolFactory(lpRegistry, assetPoolImplementation);
        console.log("AssetPoolFactory deployed at:", address(poolFactory));

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log deployment addresses to console
        console.log("Deployment completed!");
        console.log("----------------------------------------------------");
        console.log("AssetPoolFactory:", address(poolFactory));
        console.log("----------------------------------------------------");
    }
}