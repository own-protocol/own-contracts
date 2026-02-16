// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {MarketParams} from "@morpho-blue/interfaces/IMorpho.sol";

interface IMorphoCreateMarket {
    function createMarket(MarketParams memory marketParams) external;
}

contract CreateMorphoMarket is Script {
    // Base mainnet addresses
    address constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address constant ADAPTIVE_CURVE_IRM = 0x46415998764C29aB2a25CbeA6254146D50D22687;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant AI7_TOKEN = 0x2567563f230A3A30A5ba9de84157E0449c00EB36;

    // Replace with deployed MorphoOracleAdapter address
    address constant ORACLE_ADAPTER = 0x7BB7af53eE355b2DB45fdbe54D84d2d69Ae20105; // set adapter

    // Morpho has default LLTV's that are governance approved.
    uint256 constant LLTV = 860000000000000000; // 86%

    function run() external {
        require(ORACLE_ADAPTER != address(0), "Set ORACLE_ADAPTER address");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MarketParams memory params = MarketParams({
            loanToken: USDC,
            collateralToken: AI7_TOKEN,
            oracle: ORACLE_ADAPTER,
            irm: ADAPTIVE_CURVE_IRM,
            lltv: LLTV
        });

        IMorphoCreateMarket(MORPHO).createMarket(params);
        console.log("Morpho AI7/USDC market created successfully");

        vm.stopBroadcast();
    }
}
