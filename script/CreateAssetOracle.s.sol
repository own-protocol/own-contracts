// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/AssetPoolFactory.sol";

contract CreateAssetOracleScript is Script {

    // Deployed contract addresses (replace with actual addresses after deployment)
    address constant ASSET_POOL_FACTORY = 0x0AE43Ac4d1B35da83D46dC5f78b22501f83E846c;

    // Chainlink Functions Router address - depends on the network
    address constant FUNCTIONS_ROUTER = 0xf9B8fc078197181C841c296C876945aaa425B278; // Modify for the correct network

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Define the source code for fetching price data - using ABI encoding approach with updated ethers import
        string memory source = "const ethers = await import(\"npm:ethers@6.10.0\"); const yahooFinanceUrl = `https://query1.finance.yahoo.com/v8/finance/chart/TSLA?interval=1d`; const response = await Functions.makeHttpRequest({ url: yahooFinanceUrl }); if (!response || response.status !== 200) throw new Error(\"Failed to fetch asset data\"); const data = response.data.chart.result[0]; const timestamp = data.timestamp[0]; const indicators = data.indicators; const quote = indicators.quote[0]; const open = quote.open[0]; const high = quote.high[0]; const low = quote.low[0]; const close = quote.close[0]; const toWei = (value) => BigInt(Math.round(value * 1e18)); const encoded = ethers.AbiCoder.defaultAbiCoder().encode([\"uint256\", \"uint256\", \"uint256\", \"uint256\", \"uint256\"], [toWei(open), toWei(high), toWei(low), toWei(close), BigInt(timestamp)]); return ethers.getBytes(encoded);";

        // Calculate the source hash
        bytes32 sourceHash = keccak256(abi.encodePacked(source));

        // Get contract instances
        AssetPoolFactory factory = AssetPoolFactory(ASSET_POOL_FACTORY);

        // Deploy the AssetOracle contract
        address assetOracle = factory.createOracle(
            "TSLA",
            sourceHash,
            FUNCTIONS_ROUTER
        );

        console.log("Deployed AssetOracle contract at:", assetOracle);
        console.log("Source hash:", vm.toString(sourceHash));

        vm.stopBroadcast();
    }
}