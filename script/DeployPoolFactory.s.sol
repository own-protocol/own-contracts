// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/AssetPoolFactory.sol";

contract AssetPoolDeployScript is Script {
    address constant assetPool = 0x105B599CDbC0B6EFa4C04C8dbbc4313894487713;
    address constant cycleManager = 0x66B2079cfdB9f387Bc08E36ca25097ADeD661e2b;
    address constant liquidityManager = 0x66B2079cfdB9f387Bc08E36ca25097ADeD661e2b;
    

    function setUp() public {}

    function run() public {
        // Retrieve private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy AssetPoolFactory contract
        AssetPoolFactory poolFactory = new AssetPoolFactory(assetPool, cycleManager, liquidityManager);
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