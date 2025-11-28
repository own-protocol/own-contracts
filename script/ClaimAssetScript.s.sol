// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

interface IPoolCycleManager {
    function cycleIndex() external view returns (uint256);
}

interface IAssetPool {
    enum RequestType { NONE, DEPOSIT, REDEEM, LIQUIDATE }
    
    function userRequests(address user) external view returns (
        RequestType requestType,
        uint256 amount,
        uint256 collateralAmount,
        uint256 requestCycle
    );
    
    function poolCycleManager() external view returns (address);
    
    function claimAsset(address user) external;
}

contract ClaimAssetScript is Script {
    // ============ CONFIGURATION ============
    address constant POOL = 0xCa5b851B28d756EB21DEDceA9BAcea6e18DD5ECF; // TODO: Set pool address
    
    address[] users; // Populate in setUp

    function setUp() public {
        // TODO: Add user addresses
        users = [0xA2A6460f20E43dcC5F8f55714A969500c342d7CE];
    }

    function run() public {

        uint256 managerPrivateKey = vm.envUint("PRIVATE_KEY_MANAGER");
        vm.startBroadcast(managerPrivateKey);

        require(POOL != address(0), "Pool address not set");
        
        IAssetPool pool = IAssetPool(POOL);
        IPoolCycleManager cycleManager = IPoolCycleManager(pool.poolCycleManager());
        uint256 currentCycle = cycleManager.cycleIndex();
        
        console.log("Current cycle:", currentCycle);
        console.log("---");
        
        uint256 claimableCount;
        
        // First pass: identify claimable users
        for (uint256 i = 0; i < users.length; i++) {
            (
                IAssetPool.RequestType requestType,
                uint256 amount,
                ,
                uint256 requestCycle
            ) = pool.userRequests(users[i]);
            
            if (requestType == IAssetPool.RequestType.DEPOSIT && requestCycle < currentCycle) {
                claimableCount++;
                console.log("Claimable - User:", users[i]);
                console.log("  Amount:", amount);
                console.log("  Request cycle:", requestCycle);
            }
        }
        
        console.log("---");
        console.log("Total claimable users:", claimableCount);
        
        if (claimableCount == 0) {
            console.log("No users to claim for. Exiting.");
            return;
        }
        
        // Second pass: claim assets
        for (uint256 i = 0; i < users.length; i++) {
            (
                IAssetPool.RequestType requestType,
                ,
                ,
                uint256 requestCycle
            ) = pool.userRequests(users[i]);
            
            if (requestType == IAssetPool.RequestType.DEPOSIT && requestCycle < currentCycle) {
                try pool.claimAsset(users[i]) {
                    console.log("Claimed for:", users[i]);
                } catch Error(string memory reason) {
                    console.log("Failed for user:", users[i]);
                    console.log("  Reason:", reason);
                } catch {
                    console.log("Failed for user:", users[i]);
                    console.log("  Reason: unknown");
                }
            }
        }
        
        vm.stopBroadcast();
    }
}
