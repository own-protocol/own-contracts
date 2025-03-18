// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/AssetOracle.sol";

contract DeployOracleScript is Script {
    // Chainlink Functions Router address - depends on the network
    address constant FUNCTIONS_ROUTER = 0xf9B8fc078197181C841c296C876945aaa425B278; // Modify for the correct network

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Define the source code for fetching price data - using ABI encoding approach with updated ethers import
        string memory source = "const ethers = await import(\"npm:ethers@6.10.0\"); const yahooFinanceUrl = `https://query1.finance.yahoo.com/v8/finance/chart/TSLA?interval=1d`; const response = await Functions.makeHttpRequest({ url: yahooFinanceUrl }); if (!response || response.status !== 200) throw new Error(\"Failed to fetch asset data\"); const data = response.data.chart.result[0]; const meta = data.meta; const regularMarketPrice = meta.regularMarketPrice; const timestamp = data.timestamp[0]; const indicators = data.indicators; const quote = indicators.quote[0]; const open = quote.open[0]; const high = quote.high[0]; const low = quote.low[0]; const close = quote.close[0]; const volume = Math.round(quote.volume[0]); const regularMarketPeriod = meta.currentTradingPeriod.regular; const regularMarketStart = regularMarketPeriod.start; const regularMarketEnd = regularMarketPeriod.end; const gmtOffset = regularMarketPeriod.gmtoffset; const toWei = (value) => BigInt(Math.round(value * 1e18)); console.log(`TSLA Data Retrieved:`); console.log(`Current Price: $${regularMarketPrice}`); console.log(`OHLC: Open=$${open}, High=$${high}, Low=$${low}, Close=$${close}`); console.log(`Volume: ${volume}`); console.log(`Timestamp: ${new Date(timestamp * 1000).toISOString()}`); console.log(`Market Hours: ${new Date(regularMarketStart * 1000).toISOString()} - ${new Date(regularMarketEnd * 1000).toISOString()}`); const encoded = ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256'], [toWei(regularMarketPrice), toWei(open), toWei(high), toWei(low), toWei(close), BigInt(volume), BigInt(timestamp), BigInt(regularMarketStart), BigInt(regularMarketEnd), BigInt(gmtOffset)]); return ethers.getBytes(encoded);";

        // Calculate the source hash
        bytes32 sourceHash = keccak256(abi.encodePacked(source));

        // Deploy the AssetOracle contract
        AssetOracle assetOracle = new AssetOracle(
            FUNCTIONS_ROUTER,
            "TSLA",
            sourceHash
        );

        console.log("Deployed AssetOracle contract at:", address(assetOracle));
        console.log("Source hash:", vm.toString(sourceHash));

        vm.stopBroadcast();
    }
}