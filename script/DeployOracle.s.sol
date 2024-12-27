// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/AssetOracle.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy your contract
        AssetOracle assetOracle = new AssetOracle(0xf9B8fc078197181C841c296C876945aaa425B278,"TSLA");

        console.log("Deployed Oracle contract at:", address(assetOracle));

        vm.stopBroadcast();
    }
}
