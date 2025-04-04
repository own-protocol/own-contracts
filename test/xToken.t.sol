// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/protocol/xToken.sol";
import "../src/interfaces/IXToken.sol";

contract MockPool {
    xToken public token;
    
    constructor(string memory name, string memory symbol) {
        token = new xToken(name, symbol);
    }
    
    function mint(address account, uint256 amount) external {
        token.mint(account, amount);
    }
    
    function burn(address account, uint256 amount) external {
        token.burn(account, amount);
    }
}

contract xTokenTest is Test {
    xToken public xtoken;
    MockPool public pool;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    
    event Mint(address indexed account, uint256 amount);
    event Burn(address indexed account, uint256 amount);
    
    function setUp() public {
        pool = new MockPool("Test xToken", "xTST");
        xtoken = pool.token();
        
        // Fund accounts for testing
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
    }
    
    // ============ Constructor Tests ============
    
    function test_Initialization() public view {
        assertEq(xtoken.name(), "Test xToken");
        assertEq(xtoken.symbol(), "xTST");
        assertEq(xtoken.pool(), address(pool));
        assertEq(xtoken.XTOKEN_VERSION(), 0x1);
        assertEq(xtoken.totalSupply(), 0);
    }
    
    // ============ Mint Tests ============
    
    function test_Mint() public {
        uint256 mintAmount = 1000 * 1e18;
        
        vm.expectEmit(true, false, false, true);
        emit Mint(alice, mintAmount);
        
        vm.prank(address(pool));
        xtoken.mint(alice, mintAmount);
        
        assertEq(xtoken.balanceOf(alice), mintAmount);
        assertEq(xtoken.totalSupply(), mintAmount);
    }
    
    function test_Mint_Multiple() public {
        // First mint to alice
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18);
        
        // Second mint to alice
        vm.prank(address(pool));
        xtoken.mint(alice, 500 * 1e18);
        
        // Mint to bob
        vm.prank(address(pool));
        xtoken.mint(bob, 2000 * 1e18);
        
        assertEq(xtoken.balanceOf(alice), 1500 * 1e18);
        assertEq(xtoken.balanceOf(bob), 2000 * 1e18);
        assertEq(xtoken.totalSupply(), 3500 * 1e18);
    }
    
    function test_RevertWhen_MintNotPool() public {
        vm.prank(alice);
        vm.expectRevert(IXToken.NotPool.selector);
        xtoken.mint(alice, 1000 * 1e18);
    }
    
    function test_MintRevert_NotPool() public {
        vm.prank(alice);
        vm.expectRevert(IXToken.NotPool.selector);
        xtoken.mint(alice, 1000 * 1e18);
    }
    
    // ============ Burn Tests ============
    
    function test_Burn() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18);
        
        // Burn half
        uint256 burnAmount = 500 * 1e18;
        
        vm.expectEmit(true, false, false, true);
        emit Burn(alice, burnAmount);
        
        vm.prank(address(pool));
        xtoken.burn(alice, burnAmount);
        
        assertEq(xtoken.balanceOf(alice), 500 * 1e18);
        assertEq(xtoken.totalSupply(), 500 * 1e18);
    }
    
    function test_RevertWhen_BurnNotPool() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18);
        
        // Try to burn as non-pool
        vm.prank(alice);
        vm.expectRevert(IXToken.NotPool.selector);
        xtoken.burn(alice, 500 * 1e18);
    }
    
    function test_BurnRevert_NotPool() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18);
        
        // Try to burn as non-pool
        vm.prank(alice);
        vm.expectRevert(IXToken.NotPool.selector);
        xtoken.burn(alice, 500 * 1e18);
    }
    
    function test_BurnRevert_InsufficientBalance() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18);
        
        // Try to burn more than balance
        vm.prank(address(pool));
        vm.expectRevert(IXToken.InsufficientBalance.selector);
        xtoken.burn(alice, 1500 * 1e18);
    }
    
}