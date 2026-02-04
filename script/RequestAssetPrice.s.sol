// SPDX-License-Identifier: GPL-3.0-or-later
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/AssetOracle.sol"; 

contract RequestAssetPrice is Script {
    // Contract configuration - replace with your deployed contract address
    address constant ORACLE_CONTRACT_ADDRESS = 0x52BdAa287CF02cf9b4c700439e11146D7c23D311;
    
    // Chainlink Functions configuration - depends on your subscription and network
    address constant ROUTER_ADDRESS = 0xf9B8fc078197181C841c296C876945aaa425B278;
    uint64 constant SUBSCRIPTION_ID = 66; 
    uint32 constant GAS_LIMIT = 300_000;
    bytes32 constant DON_ID = 0x66756e2d626173652d6d61696e6e65742d310000000000000000000000000000; 
    
    string constant SOURCE = "const ethers = await import(\"npm:ethers@6.10.0\"); const [priceRes, marketRes] = await Promise.all([Functions.makeHttpRequest({ url: \"https://query1.finance.yahoo.com/v8/finance/chart/MAGS?interval=1d\", headers: { \"User-Agent\": \"Mozilla/5.0\" } }), Functions.makeHttpRequest({ url: \"https://api.ownfinance.org/api/isMarketOpen\" })]); if (!priceRes || priceRes.status !== 200) throw new Error(\"Failed to fetch price data\"); if (!marketRes || marketRes.status !== 200) throw new Error(\"Failed to fetch market status\"); const quote = priceRes.data.chart.result[0].indicators.quote[0]; const timestamp = marketRes.data.timestamp; const toWei = (v) => BigInt(Math.round(v * 1e18)); const encoded = ethers.AbiCoder.defaultAbiCoder().encode([\"uint256\", \"uint256\", \"uint256\", \"uint256\", \"uint256\"], [toWei(quote.open[0]), toWei(quote.high[0]), toWei(quote.low[0]), toWei(quote.close[0]), BigInt(timestamp)]); return ethers.getBytes(encoded);";
    
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