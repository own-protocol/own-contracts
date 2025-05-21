// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/interfaces/IAssetPoolWithPoolStorage.sol";
import "../src/protocol/AssetPoolFactory.sol";

contract CreatePoolScript is Script {
    // Pool configuration
    address constant DEPOSIT_TOKEN = 0x2cDAEADd29E6Ba0C3AF2551296D9729fB3c7eD99; // USDC on base sepolia
    string constant ASSET_SYMBOL = "xTSLA";
    address constant PRICE_ORACLE = 0x845d51C05c482198A7C543D3BFaB95846E3E0a50;
    address constant POOL_STRATEGY = 0x627d18FAe968Ad8d73CE9f54680B2e6F3b15700e;

    // Deployed contract addresses (replace with actual addresses after deployment)
    address constant ASSET_POOL_FACTORY = 0x6eA99f37b4c3ad5B3353cF7CBf7db916fd78ee63;

    function setUp() public pure {
        // Validate addresses
        require(ASSET_POOL_FACTORY == 0x6eA99f37b4c3ad5B3353cF7CBf7db916fd78ee63, "AssetPoolFactory address not set");
        require(DEPOSIT_TOKEN == 0x2cDAEADd29E6Ba0C3AF2551296D9729fB3c7eD99, "Deposit token address not set");
        require(PRICE_ORACLE == 0x845d51C05c482198A7C543D3BFaB95846E3E0a50, "Oracle address not set");
        require(POOL_STRATEGY == 0x627d18FAe968Ad8d73CE9f54680B2e6F3b15700e, "Interest rate strategy address not set");
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