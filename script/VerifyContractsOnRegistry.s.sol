// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/ProtocolRegistry.sol";

contract VerifyContractsOnStrategyScript is Script {

    // Deployed contract addresses (replace with actual addresses after deployment)
    address constant PROTOCOL_REGISTRY = 0x8BE9b8cC39e3974690E5BbABe16b4a52D1BF3897;


    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get contract instances
        ProtocolRegistry registry = ProtocolRegistry(PROTOCOL_REGISTRY);

        // Deploy the AssetOracle contract
        registry.setStrategyVerification(0x5076A1Ef38A27fa2d9fF44428415Da3CD67f780A, true);
        registry.setOracleVerification(0xBcd5B1a4B0e593EC0a501330A52B86948B79aCA6, true);
        registry.setPoolVerification(0x64ae3c4AD4315b16D9282c84a5D6b47671707F44, true);


        vm.stopBroadcast();
    }
}