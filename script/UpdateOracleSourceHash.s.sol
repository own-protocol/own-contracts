// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/AssetOracle.sol";

contract UpdateOracleSourceHashScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address oracleAddress = 0x02c436fdb529AeadaC0D4a74a34f6c51BFC142F0;
        
        // The new source code for which we want to update the hash
        string memory newSource = "const yahooFinanceUrl = `https://query1.finance.yahoo.com/v8/finance/chart/TSLA?interval=1h`; const response = await Functions.makeHttpRequest({ url: yahooFinanceUrl }); if (!response || response.status !== 200) throw new Error(\"Failed to fetch asset data\"); const data = response.data.chart.result[0]; const currentPrice = data.meta.regularMarketPrice; return Functions.encodeUint256(Math.round(currentPrice * 1e18));";
        
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