// SPDX-License-Identifier: GPL-3.0-or-later
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/AssetOracle.sol"; 

contract RequestAssetPrice is Script {
    // Contract configuration - replace with your deployed contract address
    address constant ORACLE_CONTRACT_ADDRESS = 0x02c436fdb529AeadaC0D4a74a34f6c51BFC142F0; 
    
    // Chainlink Functions configuration - depends on your subscription and network
    address constant ROUTER_ADDRESS = 0xf9B8fc078197181C841c296C876945aaa425B278; 
    uint64 constant SUBSCRIPTION_ID = 254; 
    uint32 constant GAS_LIMIT = 300_000;
    bytes32 constant DON_ID = 0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000; 
    
    // The source code with OHLC and trading period information extraction using updated ethers import
    string constant SOURCE = "const ethers = await import(\"npm:ethers@6.10.0\"); const yahooFinanceUrl = `https://query1.finance.yahoo.com/v8/finance/chart/TSLA?interval=1d`; const response = await Functions.makeHttpRequest({ url: yahooFinanceUrl }); if (!response || response.status !== 200) throw new Error(\"Failed to fetch asset data\"); const data = response.data.chart.result[0]; const meta = data.meta; const regularMarketPrice = meta.regularMarketPrice; const timestamp = data.timestamp[0]; const indicators = data.indicators; const quote = indicators.quote[0]; const open = quote.open[0]; const high = quote.high[0]; const low = quote.low[0]; const close = quote.close[0]; const volume = Math.round(quote.volume[0]); const regularMarketPeriod = meta.currentTradingPeriod.regular; const regularMarketStart = regularMarketPeriod.start; const regularMarketEnd = regularMarketPeriod.end; const gmtOffset = regularMarketPeriod.gmtoffset; const toWei = (value) => BigInt(Math.round(value * 1e18)); console.log(`TSLA Data Retrieved:`); console.log(`Current Price: $${regularMarketPrice}`); console.log(`OHLC: Open=$${open}, High=$${high}, Low=$${low}, Close=$${close}`); console.log(`Volume: ${volume}`); console.log(`Timestamp: ${new Date(timestamp * 1000).toISOString()}`); console.log(`Market Hours: ${new Date(regularMarketStart * 1000).toISOString()} - ${new Date(regularMarketEnd * 1000).toISOString()}`); const encoded = ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256'], [toWei(regularMarketPrice), toWei(open), toWei(high), toWei(low), toWei(close), BigInt(volume), BigInt(timestamp), BigInt(regularMarketStart), BigInt(regularMarketEnd), BigInt(gmtOffset)]); return ethers.getBytes(encoded);";

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Initialize the deployed contract
        AssetOracle oracle = AssetOracle(ORACLE_CONTRACT_ADDRESS);

        // Get the source hash to verify it matches
        bytes32 currentSourceHash = oracle.sourceHash();
        bytes32 newSourceHash = keccak256(abi.encodePacked(SOURCE));
        
        console.log("Current source hash:", vm.toString(currentSourceHash));
        console.log("New source hash:", vm.toString(newSourceHash));

        // Update source hash if it has changed
        if (currentSourceHash != newSourceHash) {
            console.log("Updating source hash...");
            oracle.updateSourceHash(newSourceHash);
        }

        // Call the requestAssetPrice function
        oracle.requestAssetPrice(SOURCE, SUBSCRIPTION_ID, GAS_LIMIT, DON_ID);
        console.log("Asset price update requested successfully");

        vm.stopBroadcast();
    }
}