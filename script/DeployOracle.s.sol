// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/AssetOracle.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        string memory source = "const yahooFinanceUrl = `https://query1.finance.yahoo.com/v8/finance/chart/TSLA?interval=1h`; const response = await Functions.makeHttpRequest({ url: yahooFinanceUrl }); if (!response || response.status !== 200) throw new Error(\"Failed to fetch asset data\"); const data = response.data.chart.result[0]; const currentPrice = data.meta.regularMarketPrice; return Functions.encodeUint256(Math.round(currentPrice * 1e18));";

        // Calculate the source hash
        bytes32 sourceHash = keccak256(abi.encodePacked(source));

        // Deploy your contract
        AssetOracle assetOracle = new AssetOracle(0xf9B8fc078197181C841c296C876945aaa425B278,"TSLA", sourceHash);

        console.log("Deployed Oracle contract at:", address(assetOracle));

        vm.stopBroadcast();
    }
}
