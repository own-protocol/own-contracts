// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/protocol/AssetPool.sol";
import "../src/protocol/PoolCycleManager.sol";
import "../src/protocol/PoolLiquidityManager.sol";

/**
 * @title DeployPoolImplementations
 * @notice Deploy script for AssetPool, PoolCycleManager, and PoolLiquidityManager implementation contracts
 * @dev These implementation contracts will be used as the base for proxy clones
 */
contract DeployPoolImplementations is Script {
    function setUp() public {}

    function run() public {
        // Retrieve private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation contracts
        AssetPool assetPoolImpl = new AssetPool();
        PoolCycleManager cycleManagerImpl = new PoolCycleManager();
        PoolLiquidityManager liquidityManagerImpl = new PoolLiquidityManager();
        
        // Log deployment addresses
        console.log("Implementations deployed:");
        console.log("AssetPool:", address(assetPoolImpl));
        console.log("PoolCycleManager:", address(cycleManagerImpl));
        console.log("PoolLiquidityManager:", address(liquidityManagerImpl));

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}