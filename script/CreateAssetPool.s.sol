// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/interfaces/IAssetPool.sol";
import "../src/protocol/AssetPoolFactory.sol";
import "../src/protocol/LPRegistry.sol";

contract CreatePoolScript is Script {
    // Pool configuration'
    address constant DEPOSIT_TOKEN = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // USDC on base sepolia
    string constant ASSET_SYMBOL = "xTSLA";
    string constant ASSET_NAME = "xTesla";
    address constant PRICE_ORACLE = 0x453cD289694c036980226FDEDF3A7a3eC686Ae05; // Replace with actual oracle address
    uint256 constant CYCLE_PERIOD = 2 hours;
    uint256 constant REBALANCING_PERIOD = 30 minutes;

    // Deployed contract addresses (replace with actual addresses after deployment)
    address constant ASSET_POOL_FACTORY = 0xda62cb7c018505042eF56B02A8207A9a704e734c; // Replace with deployed PoolFactory address
    address constant LP_REGISTRY = 0x82d533e4a2973D5c1E29eB207af0B6f387E395C9;  // Replace with deployed LPRegistry address

    function setUp() public pure {
        // Validate addresses
        require(ASSET_POOL_FACTORY == 0xda62cb7c018505042eF56B02A8207A9a704e734c, "AssetPoolFactory address not set");
        require(LP_REGISTRY == 0x82d533e4a2973D5c1E29eB207af0B6f387E395C9, "LPRegistry address not set");
        require(DEPOSIT_TOKEN == 0x036CbD53842c5426634e7929541eC2318f3dCF7e, "Deposit token address not set");
        require(PRICE_ORACLE == 0x453cD289694c036980226FDEDF3A7a3eC686Ae05, "Oracle address not set");
    }

    function run() public {
        // Retrieve private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Get contract instances
        AssetPoolFactory factory = AssetPoolFactory(ASSET_POOL_FACTORY);
        LPRegistry registry = LPRegistry(LP_REGISTRY);

        // Create the pool
        address poolAddress = factory.createPool(
            DEPOSIT_TOKEN,
            ASSET_NAME,
            ASSET_SYMBOL,
            PRICE_ORACLE,
            CYCLE_PERIOD,
            REBALANCING_PERIOD
        );

        registry.addPool(poolAddress);

        // Optional: Register initial LPs
        // Uncomment and modify these lines to register initial LPs
        /*
        address LP1 = address(0x123...);
        address LP2 = address(0x456...);
        uint256 LP1_LIQUIDITY = 1000000e18;
        uint256 LP2_LIQUIDITY = 2000000e18;
        
        registry.registerLP(poolAddress, LP1, LP1_LIQUIDITY);
        registry.registerLP(poolAddress, LP2, LP2_LIQUIDITY);
        */

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
        console.log("Cycle Period:", CYCLE_PERIOD);
        console.log("Rebalancing Period:", REBALANCING_PERIOD);
        console.log("----------------------------------------------------");

        // Verify the pool was created correctly
        IAssetPool pool = IAssetPool(poolAddress);
        (uint256 supply, IAssetPool.CycleState state, uint256 cycle,,, uint256 price) = pool.getGeneralInfo();
        console.log("Pool Initial State:");
        console.log("Supply:", supply);
        console.log("State:", uint256(state));
        console.log("Cycle:", cycle);
        console.log("Current Asset Price:", price);
    }
}