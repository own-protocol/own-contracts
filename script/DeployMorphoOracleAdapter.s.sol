// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/lending/MorphoOracleAdapter.sol";

contract DeployMorphoOracleAdapter is Script {
    address constant AI7_ORACLE = 0x52BdAa287CF02cf9b4c700439e11146D7c23D311;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MorphoOracleAdapter oracleAdapter = new MorphoOracleAdapter(AI7_ORACLE);

        console.log("MorphoOracleAdapter deployed at:", address(oracleAdapter));
        console.log("Oracle price (scaled to 1e24):", oracleAdapter.price());

        vm.stopBroadcast();
    }
}
