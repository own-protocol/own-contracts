// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../docs/testnet/SimpleTokenV2.sol";

contract DeploySimpleToken is Script {
    function run() external {
        // Get private key from environment variable for deployment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Define token parameters
        string memory name = "USDT";
        string memory symbol = "USDT";
        uint8 decimals = 18;
        uint256 nonOwnerMintLimit = 50000; // 50000 tokens (will be scaled by decimals in the contract)
        uint256 maxMintPerTransaction = 10000; // 10000 tokens per transaction
        uint256 maxMintTimes = 5; // Maximum 5 minting transactions per non-owner

        // Start broadcast for deployment
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the token
        SimpleToken token = new SimpleToken(name, symbol, decimals, nonOwnerMintLimit, maxMintPerTransaction, maxMintTimes);
        
        // End broadcast
        vm.stopBroadcast();
        
        // Log deployment information
        console.log("SimpleToken deployed at:", address(token));
        console.log("Token Name:", name);
        console.log("Token Symbol:", symbol);
        console.log("Token Decimals:", decimals);
        console.log("Non-owner Mint Limit:", nonOwnerMintLimit, "tokens");
    }
}