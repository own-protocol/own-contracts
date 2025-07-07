// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/interfaces/IAssetPoolWithPoolStorage.sol";
import "../src/protocol/AssetPoolFactory.sol";

contract CreatePoolScript is Script {
    // Pool configuration
    address constant DEPOSIT_TOKEN = 0x7bD1331A7c4E32F3aD9Ca14Ad0E7FAb0d4F380Ec; // USDC on base sepolia
    string constant ASSET_SYMBOL = "xTSLA";
    address constant PRICE_ORACLE = 0xF2fF3c044fEEDA0FE91A65ba3f056d7D81E6c6dc;
    address constant POOL_STRATEGY = 0xD0aD5937B8365C90404145FFEc361b2C817B0c52;

    // Deployed contract addresses (replace with actual addresses after deployment)
    address constant ASSET_POOL_FACTORY = 0x59409659e34158244AF69c3E3aE15Ded8bA941A4;

    function setUp() public pure {
        // Validate addresses
        require(ASSET_POOL_FACTORY == 0x59409659e34158244AF69c3E3aE15Ded8bA941A4, "AssetPoolFactory address not set");
        require(DEPOSIT_TOKEN == 0x7bD1331A7c4E32F3aD9Ca14Ad0E7FAb0d4F380Ec, "Deposit token address not set");
        require(PRICE_ORACLE == 0xF2fF3c044fEEDA0FE91A65ba3f056d7D81E6c6dc, "Oracle address not set");
        require(POOL_STRATEGY == 0xD0aD5937B8365C90404145FFEc361b2C817B0c52, "Interest rate strategy address not set");
    }

    function run() public {
        // Retrieve private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Get contract instances
        AssetPoolFactory factory = AssetPoolFactory(ASSET_POOL_FACTORY);

        // Create the pool
        address poolAddress = factory.createPool(
            DEPOSIT_TOKEN,
            ASSET_SYMBOL,
            PRICE_ORACLE,
            POOL_STRATEGY
        );


        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log deployment information
        console.log("Pool Deployment Completed!");
        console.log("----------------------------------------------------");
        console.log("New Pool Address:", poolAddress);
        console.log("Deposit Token:", DEPOSIT_TOKEN);
        console.log("Asset Token Symbol:", ASSET_SYMBOL);
        console.log("Price Oracle:", PRICE_ORACLE);
        console.log("Pool Strategy:", POOL_STRATEGY);
        console.log("----------------------------------------------------");

        // Verify the pool was created correctly
        IAssetPoolWithPoolStorage pool = IAssetPoolWithPoolStorage(poolAddress);
        
        require(address(pool.reserveToken()) == DEPOSIT_TOKEN, "Deposit token not set correctly");
    }
}