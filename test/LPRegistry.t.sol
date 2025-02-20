// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/protocol/LPRegistry.sol";
import "../src/interfaces/ILPRegistry.sol";
import "forge-std/console.sol";

contract LPRegistryTest is Test {
    LPRegistry public lpRegistry;
    address public owner;
    address public pool1;
    address public pool2;
    address public lp1;
    address public lp2;
    address public lp3;
    uint256 public constant INITIAL_LIQUIDITY = 1000 ether;

    event PoolAdded(address indexed pool);
    event PoolRemoved(address indexed pool);
    event LPRegistered(address indexed pool, address indexed lp, uint256 amount);
    event LPRemoved(address indexed pool, address indexed lp);
    event LiquidityIncreased(address indexed pool, address indexed lp, uint256 amount);
    event LiquidityDecreased(address indexed pool, address indexed lp, uint256 amount);

    function setUp() public {
        owner = address(this);
        pool1 = address(0x1);
        pool2 = address(0x2);
        lp1 = address(0x10);
        lp2 = address(0x20);
        lp3 = address(0x30);
        
        lpRegistry = new LPRegistry();
    }

    // ========================
    // Pool Management Tests
    // ========================

    function testAddPool() public {
        vm.expectEmit(true, false, false, false);
        emit PoolAdded(pool1);
        
        lpRegistry.addPool(pool1);
        assertTrue(lpRegistry.validPools(pool1));
        assertTrue(lpRegistry.isValidPool(pool1));
    }

    function testAddPoolRevertWhenAlreadyRegistered() public {
        lpRegistry.addPool(pool1);
        
        vm.expectRevert(ILPRegistry.AlreadyRegistered.selector);
        lpRegistry.addPool(pool1);
    }

    function testAddPoolRevertWhenNotOwner() public {
        vm.prank(lp1);
        vm.expectRevert();
        lpRegistry.addPool(pool1);
    }

    function testRemovePool() public {
        lpRegistry.addPool(pool1);
        
        vm.expectEmit(true, false, false, false);
        emit PoolRemoved(pool1);
        
        lpRegistry.removePool(pool1);
        assertFalse(lpRegistry.validPools(pool1));
        assertFalse(lpRegistry.isValidPool(pool1));
    }

    function testRemovePoolRevertWhenNotFound() public {
        vm.expectRevert(ILPRegistry.PoolNotFound.selector);
        lpRegistry.removePool(pool1);
    }

    function testRemovePoolRevertWhenHasActiveLiquidity() public {
        lpRegistry.addPool(pool1);
        // Owner registers LP (fixed)
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
        
        vm.expectRevert("Pool has active liquidity");
        lpRegistry.removePool(pool1);
    }

    function testRemovePoolRevertWhenNotOwner() public {
        lpRegistry.addPool(pool1);
        
        vm.prank(lp1);
        vm.expectRevert();
        lpRegistry.removePool(pool1);
    }

    // ========================
    // LP Registration Tests
    // ========================

    function testRegisterLP() public {
        lpRegistry.addPool(pool1);
        
        vm.expectEmit(true, true, false, true);
        emit LPRegistered(pool1, lp1, INITIAL_LIQUIDITY);
        
        // Owner registers LP (test contract is owner)
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
        
        assertTrue(lpRegistry.poolLPs(pool1, lp1));
        assertTrue(lpRegistry.isLP(pool1, lp1));
        assertEq(lpRegistry.poolLPCount(pool1), 1);
        assertEq(lpRegistry.getLPCount(pool1), 1);
        assertEq(lpRegistry.lpLiquidityAmount(pool1, lp1), INITIAL_LIQUIDITY);
        assertEq(lpRegistry.getLPLiquidity(pool1, lp1), INITIAL_LIQUIDITY);
        assertEq(lpRegistry.totalLPLiquidity(pool1), INITIAL_LIQUIDITY);
        assertEq(lpRegistry.getTotalLPLiquidity(pool1), INITIAL_LIQUIDITY);
    }
    
    function testRegisterLPRevertWhenNotOwner() public {
        lpRegistry.addPool(pool1);
        
        // Try to register LP from a non-owner address
        vm.prank(lp1);
        vm.expectRevert();
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
    }

    function testRegisterLPRevertWhenPoolNotValid() public {
        // Attempting to register LP to invalid pool should revert
        vm.expectRevert(ILPRegistry.PoolNotFound.selector);
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
    }

    function testRegisterLPRevertWhenAlreadyRegistered() public {
        lpRegistry.addPool(pool1);
        // Owner registers LP
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
        
        // Owner tries to register same LP again
        vm.expectRevert(ILPRegistry.AlreadyRegistered.selector);
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
    }

    function testRegisterLPRevertWhenZeroAmount() public {
        lpRegistry.addPool(pool1);
        
        // Owner tries to register LP with zero amount
        vm.expectRevert(ILPRegistry.InvalidAmount.selector);
        lpRegistry.registerLP(pool1, lp1, 0);
    }

    function testMultipleLPRegistration() public {
        lpRegistry.addPool(pool1);
        
        // Register first LP (owner registers LPs)
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
        
        // Register second LP (owner registers LPs) 
        lpRegistry.registerLP(pool1, lp2, INITIAL_LIQUIDITY * 2);
        
        assertEq(lpRegistry.poolLPCount(pool1), 2);
        assertEq(lpRegistry.totalLPLiquidity(pool1), INITIAL_LIQUIDITY * 3);
    }

    function testRemoveLP() public {
        lpRegistry.addPool(pool1);
        // Owner registers LP
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
        
        // LP removes all liquidity first (must be done by LP)
        vm.prank(lp1);
        lpRegistry.decreaseLiquidity(pool1, INITIAL_LIQUIDITY);
        
        vm.expectEmit(true, true, false, false);
        emit LPRemoved(pool1, lp1);
        
        // Owner removes the LP
        lpRegistry.removeLP(pool1, lp1);
        
        assertFalse(lpRegistry.poolLPs(pool1, lp1));
        assertFalse(lpRegistry.isLP(pool1, lp1));
        assertEq(lpRegistry.poolLPCount(pool1), 0);
    }
    
    function testRemoveLPRevertWhenNotOwner() public {
        lpRegistry.addPool(pool1);
        // Owner registers LP
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
        
        // LP removes all liquidity first
        vm.prank(lp1);
        lpRegistry.decreaseLiquidity(pool1, INITIAL_LIQUIDITY);
        
        // Try to remove LP from a non-owner address
        vm.prank(lp1);
        vm.expectRevert();
        lpRegistry.removeLP(pool1, lp1);
    }

    function testRemoveLPRevertWhenNotRegistered() public {
        lpRegistry.addPool(pool1);
        
        vm.expectRevert(ILPRegistry.NotRegistered.selector);
        lpRegistry.removeLP(pool1, lp1);
    }

    function testRemoveLPRevertWhenHasActiveLiquidity() public {
        lpRegistry.addPool(pool1);
        // Owner registers LP
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
        
        // Owner tries to remove LP with active liquidity
        vm.expectRevert("LP has active liquidity");
        lpRegistry.removeLP(pool1, lp1);
    }

    // ========================
    // Liquidity Management Tests
    // ========================

    function testIncreaseLiquidity() public {
        lpRegistry.addPool(pool1);
        // Owner registers LP
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
        
        uint256 addedLiquidity = 500 ether;
        
        // LP increases their own liquidity (must be done by LP)
        vm.prank(lp1);
        vm.expectEmit(true, true, false, true);
        emit LiquidityIncreased(pool1, lp1, addedLiquidity);
        
        lpRegistry.increaseLiquidity(pool1, addedLiquidity);
        
        assertEq(lpRegistry.lpLiquidityAmount(pool1, lp1), INITIAL_LIQUIDITY + addedLiquidity);
        assertEq(lpRegistry.totalLPLiquidity(pool1), INITIAL_LIQUIDITY + addedLiquidity);
    }

    function testIncreaseLiquidityRevertWhenNotRegistered() public {
        lpRegistry.addPool(pool1);
        
        vm.prank(lp1);
        vm.expectRevert(ILPRegistry.NotRegistered.selector);
        lpRegistry.increaseLiquidity(pool1, 100 ether);
    }

    function testIncreaseLiquidityRevertWhenZeroAmount() public {
        lpRegistry.addPool(pool1);
        // Owner registers LP
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
        
        vm.prank(lp1);
        vm.expectRevert(ILPRegistry.InvalidAmount.selector);
        lpRegistry.increaseLiquidity(pool1, 0);
    }

    function testDecreaseLiquidity() public {
        lpRegistry.addPool(pool1);
        // Owner registers LP
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
        
        uint256 decreasedLiquidity = 300 ether;
        
        // LP decreases their own liquidity (must be done by LP)
        vm.prank(lp1);
        vm.expectEmit(true, true, false, true);
        emit LiquidityDecreased(pool1, lp1, decreasedLiquidity);
        
        lpRegistry.decreaseLiquidity(pool1, decreasedLiquidity);
        
        assertEq(lpRegistry.lpLiquidityAmount(pool1, lp1), INITIAL_LIQUIDITY - decreasedLiquidity);
        assertEq(lpRegistry.totalLPLiquidity(pool1), INITIAL_LIQUIDITY - decreasedLiquidity);
    }

    function testDecreaseLiquidityRevertWhenNotRegistered() public {
        lpRegistry.addPool(pool1);
        
        vm.prank(lp1);
        vm.expectRevert(ILPRegistry.NotRegistered.selector);
        lpRegistry.decreaseLiquidity(pool1, 100 ether);
    }

    function testDecreaseLiquidityRevertWhenZeroAmount() public {
        lpRegistry.addPool(pool1);
        // Owner registers LP
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
        
        vm.prank(lp1);
        vm.expectRevert(ILPRegistry.InvalidAmount.selector);
        lpRegistry.decreaseLiquidity(pool1, 0);
    }

    function testDecreaseLiquidityRevertWhenInsufficientLiquidity() public {
        lpRegistry.addPool(pool1);
        // Owner registers LP
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
        
        vm.prank(lp1);
        vm.expectRevert(ILPRegistry.InsufficientLiquidity.selector);
        lpRegistry.decreaseLiquidity(pool1, INITIAL_LIQUIDITY + 1);
    }

    // ========================
    // View Function Tests
    // ========================

    function testIsLP() public {
        lpRegistry.addPool(pool1);
        
        assertFalse(lpRegistry.isLP(pool1, lp1));
        
        // Owner registers LP
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
        
        assertTrue(lpRegistry.isLP(pool1, lp1));
        assertFalse(lpRegistry.isLP(pool1, lp2));
    }

    function testGetLPCount() public {
        lpRegistry.addPool(pool1);
        
        assertEq(lpRegistry.getLPCount(pool1), 0);
        
        // Owner registers first LP
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
        
        assertEq(lpRegistry.getLPCount(pool1), 1);
        
        // Owner registers second LP
        lpRegistry.registerLP(pool1, lp2, INITIAL_LIQUIDITY);
        
        assertEq(lpRegistry.getLPCount(pool1), 2);
    }

    function testGetLPLiquidity() public {
        lpRegistry.addPool(pool1);
        
        assertEq(lpRegistry.getLPLiquidity(pool1, lp1), 0);
        
        // Owner registers LP
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
        
        assertEq(lpRegistry.getLPLiquidity(pool1, lp1), INITIAL_LIQUIDITY);
        
        // LP increases their liquidity
        vm.prank(lp1);
        lpRegistry.increaseLiquidity(pool1, 500 ether);
        
        assertEq(lpRegistry.getLPLiquidity(pool1, lp1), INITIAL_LIQUIDITY + 500 ether);
    }

    function testGetTotalLPLiquidity() public {
        lpRegistry.addPool(pool1);
        lpRegistry.addPool(pool2);
        
        assertEq(lpRegistry.getTotalLPLiquidity(pool1), 0);
        
        // Owner registers LPs
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
        lpRegistry.registerLP(pool1, lp2, INITIAL_LIQUIDITY * 2);
        lpRegistry.registerLP(pool2, lp3, INITIAL_LIQUIDITY * 3);
        
        assertEq(lpRegistry.getTotalLPLiquidity(pool1), INITIAL_LIQUIDITY * 3);
        assertEq(lpRegistry.getTotalLPLiquidity(pool2), INITIAL_LIQUIDITY * 3);
    }

    // ========================
    // Fuzz Tests
    // ========================
    
    function testFuzz_RegisterAndManageLiquidity(
        address fuzzPool,
        address fuzzLP,
        uint256 initialAmount,
        uint256 increaseAmount,
        uint256 decreaseAmount
    ) public {
        // Guard against zero address and precompiles
        vm.assume(fuzzPool != address(0) && fuzzLP != address(0));
        vm.assume(uint160(fuzzPool) > 0x1000 && uint160(fuzzLP) > 0x1000);
        
        // Guard against unrealistic amounts
        initialAmount = bound(initialAmount, 1, 1e36);
        increaseAmount = bound(increaseAmount, 1, 1e36);
        decreaseAmount = bound(decreaseAmount, 1, initialAmount);
        
        // Add pool (as owner)
        lpRegistry.addPool(fuzzPool);
        
        // Register LP (as owner)
        lpRegistry.registerLP(fuzzPool, fuzzLP, initialAmount);
        
        // Increase liquidity (LP must do this themselves)
        vm.prank(fuzzLP);
        lpRegistry.increaseLiquidity(fuzzPool, increaseAmount);
        
        // Verify increased amount
        assertEq(
            lpRegistry.getLPLiquidity(fuzzPool, fuzzLP),
            initialAmount + increaseAmount
        );
        
        // Decrease liquidity (LP must do this themselves)
        vm.prank(fuzzLP);
        lpRegistry.decreaseLiquidity(fuzzPool, decreaseAmount);
        
        // Verify decreased amount
        assertEq(
            lpRegistry.getLPLiquidity(fuzzPool, fuzzLP),
            initialAmount + increaseAmount - decreaseAmount
        );
    }

    // ========================
    // Security Tests
    // ========================
    
    function testOnlyOwnerCanAddRemovePools() public {
        address nonOwner = address(0x99);
        
        // Try to add pool as non-owner
        vm.prank(nonOwner);
        vm.expectRevert();
        lpRegistry.addPool(pool1);
        
        // Add as owner
        lpRegistry.addPool(pool1);
        
        // Try to remove pool as non-owner
        vm.prank(nonOwner);
        vm.expectRevert();
        lpRegistry.removePool(pool1);
    }
    
    function testOnlyOwnerCanRegisterRemoveLP() public {
        address nonOwner = address(0x99);
        
        lpRegistry.addPool(pool1);
        
        // Try to register LP as non-owner
        vm.prank(nonOwner);
        vm.expectRevert();
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
        
        // Register as owner
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
        
        // Remove liquidity
        vm.prank(lp1);
        lpRegistry.decreaseLiquidity(pool1, INITIAL_LIQUIDITY);
        
        // Try to remove LP as non-owner
        vm.prank(nonOwner);
        vm.expectRevert();
        lpRegistry.removeLP(pool1, lp1);
    }
    
    function testLPCanOnlyManageOwnLiquidity() public {
        lpRegistry.addPool(pool1);
        
        // Register LP1 (by owner)
        lpRegistry.registerLP(pool1, lp1, INITIAL_LIQUIDITY);
        
        // LP2 tries to decrease LP1's liquidity
        vm.prank(lp2);
        vm.expectRevert(ILPRegistry.NotRegistered.selector);
        lpRegistry.decreaseLiquidity(pool1, 100 ether);
        
        // LP2 tries to increase LP1's liquidity
        vm.prank(lp2);
        vm.expectRevert(ILPRegistry.NotRegistered.selector);
        lpRegistry.increaseLiquidity(pool1, 100 ether);
    }

    // ========================
    // Edge Case Tests
    // ========================
    
    function testMaximumLiquidity() public {
        lpRegistry.addPool(pool1);
        
        // Test with maximum uint256 value
        uint256 maxLiquidity = type(uint256).max;
        // Owner registers LP with max liquidity
        lpRegistry.registerLP(pool1, lp1, maxLiquidity);
        
        assertEq(lpRegistry.getLPLiquidity(pool1, lp1), maxLiquidity);
        
        // This should revert due to overflow
        vm.prank(lp1);
        vm.expectRevert();
        lpRegistry.increaseLiquidity(pool1, 1);
    }
    
    function testPoolWithManySmallerLPs() public {
        lpRegistry.addPool(pool1);
        
        // Register 10 LPs with small amounts (owner registers all LPs)
        for (uint160 i = 1; i <= 10; i++) {
            address currentLP = address(i);
            lpRegistry.registerLP(pool1, currentLP, i * 1 ether);
        }
        
        assertEq(lpRegistry.getLPCount(pool1), 10);
        
        // Expected total: sum of 1 through 10 = 55
        assertEq(lpRegistry.getTotalLPLiquidity(pool1), 55 ether);
    }
}