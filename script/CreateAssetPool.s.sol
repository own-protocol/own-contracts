// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/interfaces/IAssetPool.sol";
import "../src/protocol/AssetPoolFactory.sol";

contract CreatePoolScript is Script {
    // Pool configuration
    address constant DEPOSIT_TOKEN = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // USDC on base sepolia
    string constant ASSET_SYMBOL = "xTSLA";
    string constant ASSET_NAME = "xTesla";
    address constant PRICE_ORACLE = 0x02c436fdb529AeadaC0D4a74a34f6c51BFC142F0;
    uint256 constant CYCLE_LENGTH = 2 hours;
    uint256 constant REBALANCING_LENGTH = 30 minutes;

    // Deployed contract addresses (replace with actual addresses after deployment)
    address constant ASSET_POOL_FACTORY = 0x0AE43Ac4d1B35da83D46dC5f78b22501f83E846c; 

    function setUp() public pure {
        // Validate addresses
        require(ASSET_POOL_FACTORY == 0x0AE43Ac4d1B35da83D46dC5f78b22501f83E846c, "AssetPoolFactory address not set");
        require(DEPOSIT_TOKEN == 0x036CbD53842c5426634e7929541eC2318f3dCF7e, "Deposit token address not set");
        require(PRICE_ORACLE == 0x02c436fdb529AeadaC0D4a74a34f6c51BFC142F0, "Oracle address not set");
    }

    function run() public {
        // Retrieve private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Get contract instances
        AssetPoolFactory factory = AssetPoolFactory(ASSET_POOL_FACTORY);

        // Create the pool
        address poolAddress = factory.createPool(
            DEPOSIT_TOKEN,
            ASSET_NAME,
            ASSET_SYMBOL,
            PRICE_ORACLE,
            CYCLE_LENGTH,
            REBALANCING_LENGTH
        );


        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log deployment information
        console.log("Pool Deployment Completed!");
        console.log("----------------------------------------------------");
        console.log("New Pool Address:", poolAddress);
        console.log("Deposit Token:", DEPOSIT_TOKEN);
        console.log("Asset Token Name:", ASSET_NAME);
        console.log("Asset Token Symbol:", ASSET_SYMBOL);
        console.log("Price Oracle:", PRICE_ORACLE);
        console.log("Cycle Period:", CYCLE_LENGTH);
        console.log("Rebalancing Period:", REBALANCING_LENGTH);
        console.log("----------------------------------------------------");

        // Verify the pool was created correctly
        IAssetPool pool = IAssetPool(poolAddress);
        (
            IAssetPool.CycleState _cycleState,
            uint256 _cycleIndex,
            uint256 _assetPrice,
            uint256 _lastCycleActionDateTime,
            uint256 _reserveBalance,
            uint256 _assetBalance,
            uint256 _totalDepositRequests,
            uint256 _totalRedemptionRequests,
            int256 _netReserveDelta,
            int256 _netAssetDelta,
            int256 _rebalanceAmount
        ) = pool.getPoolInfo();

        console.log("Pool Initial State:");
        console.log("Cycle State:", uint256(_cycleState));
        console.log("Cycle Index:", _cycleIndex);
        console.log("Asset Price:", _assetPrice);
        console.log("Last Action Time:", _lastCycleActionDateTime);
        console.log("Reserve Balance:", _reserveBalance);
        console.log("Asset Balance:", _assetBalance);
        console.log("Total Deposit Requests:", _totalDepositRequests);
        console.log("Total Redemption Requests:", _totalRedemptionRequests);
        console.log("Net Reserve Delta:", _netReserveDelta < 0 ? "-" : "+", uint256(_netReserveDelta < 0 ? -_netReserveDelta : _netReserveDelta));
        console.log("Net Asset Delta:", _netAssetDelta < 0 ? "-" : "+", uint256(_netAssetDelta < 0 ? -_netAssetDelta : _netAssetDelta));
        console.log("Rebalance Amount:", _rebalanceAmount < 0 ? "-" : "+", uint256(_rebalanceAmount < 0 ? -_rebalanceAmount : _rebalanceAmount));
    }
}