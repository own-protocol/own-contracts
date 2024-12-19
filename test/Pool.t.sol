// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Pool} from "../src/Pool.sol";

contract PoolTest is Test {
    Pool public pool;

    function setUp() public {
        pool = new Pool();
        pool.setNumber(0);
    }

    function test_Increment() public {
        pool.increment();
        assertEq(pool.number(), 1);
    }

    function testFuzz_SetNumber(uint256 x) public {
        pool.setNumber(x);
        assertEq(pool.number(), x);
    }
}
