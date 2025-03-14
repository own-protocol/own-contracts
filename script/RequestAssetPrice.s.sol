// SPDX-License-Identifier: GPL-3.0-or-later
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/AssetOracle.sol"; 

contract RequestAssetPrice is Script {

    address constant ORACLE_CONTRACT_ADDRESS = 0x02c436fdb529AeadaC0D4a74a34f6c51BFC142F0; // Deployed AssetOracle contract address
    address constant ROUTER_ADDRESS = 0xf9B8fc078197181C841c296C876945aaa425B278; // Chainlink Functions router address
    uint64 constant SUBSCRIPTION_ID = 254; // Your Chainlink subscription ID
    uint32 constant GAS_LIMIT = 300_000;
    bytes32 constant DON_ID = 0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000; // DON ID for Chainlink Functions
    string constant SOURCE = "const yahooFinanceUrl = `https://query1.finance.yahoo.com/v8/finance/chart/TSLA?interval=1h`; const response = await Functions.makeHttpRequest({ url: yahooFinanceUrl }); if (!response || response.status !== 200) throw new Error(\"Failed to fetch asset data\"); const data = response.data.chart.result[0]; const currentPrice = data.meta.regularMarketPrice; return Functions.encodeUint256(Math.round(currentPrice * 1e18));";

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Initialize the deployed contract
        AssetOracle oracle = AssetOracle(ORACLE_CONTRACT_ADDRESS);

        // Call the requestAssetPrice function
        oracle.requestAssetPrice(SOURCE, SUBSCRIPTION_ID, GAS_LIMIT, DON_ID);

        vm.stopBroadcast(); // Stop broadcasting the transaction
    }
}
