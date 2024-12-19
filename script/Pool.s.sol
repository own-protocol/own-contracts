// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Pool} from "../src/Pool.sol";

contract PoolScript is Script {
    Pool public pool;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        pool = new Pool();

        vm.stopBroadcast();
    }
}
