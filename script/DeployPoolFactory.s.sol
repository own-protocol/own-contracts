// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/AssetPoolFactory.sol";

contract AssetPoolFactoryDeployScript is Script {
    address constant assetPool = 0x63a0Bc7cf9603f5D3bcAE4C35500526a72A790AE;
    address constant cycleManager = 0x3B10A2343fFC0C452AeE1580fBcFB27cA05572f1;
    address constant liquidityManager = 0xACdf42f5A525EF0a0E3D749d6000471cf1100a81;
    address constant protocolRegistry = 0x811Ad5f758DB53d8dD3B18890a0cfe5a389e3C72;
    

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