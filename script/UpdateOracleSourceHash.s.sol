// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/AssetOracle.sol";

contract UpdateOracleSourceHashScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address oracleAddress = 0x52BdAa287CF02cf9b4c700439e11146D7c23D311;
        
        // The new source code for which we want to update the hash
        string memory newSource = "const ethers = await import(\"npm:ethers@6.10.0\"); const [priceRes, marketRes] = await Promise.all([Functions.makeHttpRequest({ url: \"https://query1.finance.yahoo.com/v8/finance/chart/MAGS?interval=1d\", headers: { \"User-Agent\": \"Mozilla/5.0\" } }), Functions.makeHttpRequest({ url: \"https://api.ownfinance.org/api/isMarketOpen\" })]); if (!priceRes || priceRes.status !== 200) throw new Error(\"Failed to fetch price data\"); if (!marketRes || marketRes.status !== 200) throw new Error(\"Failed to fetch market status\"); const quote = priceRes.data.chart.result[0].indicators.quote[0]; const timestamp = marketRes.data.timestamp; const toWei = (v) => BigInt(Math.round(v * 1e18)); const encoded = ethers.AbiCoder.defaultAbiCoder().encode([\"uint256\", \"uint256\", \"uint256\", \"uint256\", \"uint256\"], [toWei(quote.open[0]), toWei(quote.high[0]), toWei(quote.low[0]), toWei(quote.close[0]), BigInt(timestamp)]); return ethers.getBytes(encoded);";

        // Calculate the new source hash
        bytes32 newSourceHash = keccak256(abi.encodePacked(newSource));
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Get the deployed contract instance
        AssetOracle oracle = AssetOracle(oracleAddress);
        
        // Update the source hash
        oracle.updateSourceHash(newSourceHash);
        
        console.log("Updated source hash to:", vm.toString(newSourceHash));
        
        vm.stopBroadcast();
    }
}

// Older source for reference:
// string memory source = "const ethers = await import(\"npm:ethers@6.10.0\"); const yahooFinanceUrl = \"https://query1.finance.yahoo.com/v8/finance/chart/MAGS?interval=1d\"; const response = await Functions.makeHttpRequest({ url: yahooFinanceUrl }); if (!response || response.status !== 200) throw new Error(\"Failed to fetch asset data\"); const data = response.data.chart.result[0]; const timestamp = data.timestamp[0]; const indicators = data.indicators; const quote = indicators.quote[0]; const open = quote.open[0]; const high = quote.high[0]; const low = quote.low[0]; const close = quote.close[0]; const toWei = (value) => BigInt(Math.round(value * 1e18)); const encoded = ethers.AbiCoder.defaultAbiCoder().encode([\"uint256\", \"uint256\", \"uint256\", \"uint256\", \"uint256\"], [toWei(open), toWei(high), toWei(low), toWei(close), BigInt(timestamp)]); return ethers.getBytes(encoded);";