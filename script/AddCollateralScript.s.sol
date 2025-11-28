// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IAssetPool {
    enum RequestType { NONE, DEPOSIT, REDEEM, LIQUIDATE }
    
    function userRequests(address user) external view returns (
        RequestType requestType,
        uint256 amount,
        uint256 collateralAmount,
        uint256 requestCycle
    );
    
    function addCollateral(address user, uint256 amount) external;
}

contract AddCollateralScript is Script {
    // ============ CONFIGURATION ============
    address constant POOL = 0xCa5b851B28d756EB21DEDceA9BAcea6e18DD5ECF; // TODO: Set pool address
    address constant RESERVE_TOKEN = 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB; // TODO: Set reserve token address
    address constant MANAGER = 0xb914b344D8a2C88598A9C5905C9342a9678a67db; // TODO: Set manager address
    uint256 constant COLLATERAL_RATIO = 2; // 2% collateral ratio (in percentage)
    
    address[] users; // Populate in setUp or pass via environment

    function setUp() public {
        // TODO: Add user addresses
        users = [0xA2A6460f20E43dcC5F8f55714A969500c342d7CE];
    }

    function run() public {

        uint256 managerPrivateKey = vm.envUint("PRIVATE_KEY_MANAGER");
        vm.startBroadcast(managerPrivateKey);

        require(POOL != address(0), "Pool address not set");
        require(RESERVE_TOKEN != address(0), "Reserve token not set");
        
        IAssetPool pool = IAssetPool(POOL);
        IERC20 token = IERC20(RESERVE_TOKEN);
        
        uint256 totalCollateralNeeded;
        uint256 usersNeedingCollateral;
        
        // First pass: calculate total needed and log
        for (uint256 i = 0; i < users.length; i++) {
            (
                IAssetPool.RequestType requestType,
                uint256 depositAmount,
                uint256 collateralAmount,
            ) = pool.userRequests(users[i]);
            
            if (requestType == IAssetPool.RequestType.DEPOSIT && collateralAmount == 0 && depositAmount > 0) {
                uint256 needed = (depositAmount * COLLATERAL_RATIO) / 100;
                totalCollateralNeeded += needed;
                usersNeedingCollateral++;
                console.log("User:", users[i]);
                console.log("  Deposit amount:", depositAmount);
                console.log("  Collateral needed:", needed);
            }
        }
        
        console.log("---");
        console.log("Total users needing collateral:", usersNeedingCollateral);
        console.log("Total collateral needed:", totalCollateralNeeded);
        
        if (usersNeedingCollateral == 0) {
            console.log("No users need collateral. Exiting.");
            return;
        }
        
        // Check caller balance
        uint256 callerBalance = token.balanceOf(MANAGER);
        console.log("Caller balance:", callerBalance);
        require(callerBalance >= totalCollateralNeeded, "Insufficient balance");
        
        // Approve pool for total amount
        token.approve(POOL, totalCollateralNeeded);
        
        // Second pass: add collateral
        for (uint256 i = 0; i < users.length; i++) {
            (
                IAssetPool.RequestType requestType,
                uint256 depositAmount,
                uint256 collateralAmount,
            ) = pool.userRequests(users[i]);
            
            if (requestType == IAssetPool.RequestType.DEPOSIT && collateralAmount == 0 && depositAmount > 0) {
                uint256 collateralToAdd = (depositAmount * COLLATERAL_RATIO) / 100;
                
                try pool.addCollateral(users[i], collateralToAdd) {
                    console.log("Added collateral for:", users[i]);
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
