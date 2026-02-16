// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/AssetPoolFactory.sol";

contract CreateAssetOracleScript is Script {

    // Deployed contract addresses (replace with actual addresses after deployment)
    address constant ASSET_POOL_FACTORY = 0x59409659e34158244AF69c3E3aE15Ded8bA941A4;

    // Chainlink Functions Router address - depends on the network
    address constant FUNCTIONS_ROUTER = 0xf9B8fc078197181C841c296C876945aaa425B278; // Modify for the correct network

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Define the source code for fetching price data - using ABI encoding approach with updated ethers import
        string memory source = "const ethers = await import(\"npm:ethers@6.10.0\"); const [priceRes, marketRes] = await Promise.all([Functions.makeHttpRequest({ url: \"https://query1.finance.yahoo.com/v8/finance/chart/MAGS?interval=1d\", headers: { \"User-Agent\": \"Mozilla/5.0\" } }), Functions.makeHttpRequest({ url: \"https://api.ownfinance.org/api/isMarketOpen\" })]); if (!priceRes || priceRes.status !== 200) throw new Error(\"Failed to fetch price data\"); if (!marketRes || marketRes.status !== 200) throw new Error(\"Failed to fetch market status\"); const quote = priceRes.data.chart.result[0].indicators.quote[0]; const timestamp = marketRes.data.timestamp; const toWei = (v) => BigInt(Math.round(v * 1e18)); const encoded = ethers.AbiCoder.defaultAbiCoder().encode([\"uint256\", \"uint256\", \"uint256\", \"uint256\", \"uint256\"], [toWei(quote.open[0]), toWei(quote.high[0]), toWei(quote.low[0]), toWei(quote.close[0]), BigInt(timestamp)]); return ethers.getBytes(encoded);";
    
        // Calculate the source hash
        bytes32 sourceHash = keccak256(abi.encodePacked(source));

        // Get contract instances
        AssetPoolFactory factory = AssetPoolFactory(ASSET_POOL_FACTORY);

        // Deploy the AssetOracle contract
        address assetOracle = factory.createOracle(
            "AAPL",
            sourceHash,
            FUNCTIONS_ROUTER
        );

        console.log("Deployed AssetOracle contract at:", assetOracle);
        console.log("Source hash:", vm.toString(sourceHash));

        vm.stopBroadcast();
    }
}