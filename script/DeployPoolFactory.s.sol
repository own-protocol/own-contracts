// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/AssetPoolFactory.sol";

contract AssetPoolDeployScript is Script {
    address constant assetPool = 0x3A91E1E6Fd53Bf1efF573dBd551DA930f4937ea3;
    address constant cycleManager = 0xda22816E7FeAD4a4639cC892d7Dfa0d1eCDB362C;
    address constant liquidityManager = 0x3C6F5423287FCf768E2393735778a65f94d521e7;
    address constant protocolRegistry = 0xCEaBF7ed92bCA91920316f015C92F61a4F8bE761;
    

    function setUp() public {}

    function run() public {
        // Retrieve private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy AssetPoolFactory contract
        AssetPoolFactory poolFactory = new AssetPoolFactory(
            assetPool, cycleManager, liquidityManager, protocolRegistry);
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