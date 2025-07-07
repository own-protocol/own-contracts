// SPDX-License-Identifier: GPL-3.0-or-later
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/AssetOracle.sol"; 

contract RequestAssetPrice is Script {
    // Contract configuration - replace with your deployed contract address
    address constant ORACLE_CONTRACT_ADDRESS = 0xF2fF3c044fEEDA0FE91A65ba3f056d7D81E6c6dc;
    
    // Chainlink Functions configuration - depends on your subscription and network
    address constant ROUTER_ADDRESS = 0xf9B8fc078197181C841c296C876945aaa425B278; 
    uint64 constant SUBSCRIPTION_ID = 254; 
    uint32 constant GAS_LIMIT = 300_000;
    bytes32 constant DON_ID = 0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000; 
    
   string constant SOURCE = "const ethers = await import(\"npm:ethers@6.10.0\"); const yahooFinanceUrl = `https://query1.finance.yahoo.com/v8/finance/chart/TSLA?interval=1d`; const response = await Functions.makeHttpRequest({ url: yahooFinanceUrl }); if (!response || response.status !== 200) throw new Error(\"Failed to fetch asset data\"); const data = response.data.chart.result[0]; const timestamp = data.timestamp[0]; const indicators = data.indicators; const quote = indicators.quote[0]; const open = quote.open[0]; const high = quote.high[0]; const low = quote.low[0]; const close = quote.close[0]; const toWei = (value) => BigInt(Math.round(value * 1e18)); const encoded = ethers.AbiCoder.defaultAbiCoder().encode([\"uint256\", \"uint256\", \"uint256\", \"uint256\", \"uint256\"], [toWei(open), toWei(high), toWei(low), toWei(close), BigInt(timestamp)]); return ethers.getBytes(encoded);";

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Initialize the deployed contract
        AssetOracle oracle = AssetOracle(ORACLE_CONTRACT_ADDRESS);

        // Call the requestAssetPrice function
        oracle.requestAssetPrice(SOURCE, SUBSCRIPTION_ID, GAS_LIMIT, DON_ID);
        console.log("Asset price update requested successfully");

        vm.stopBroadcast();
    }
}