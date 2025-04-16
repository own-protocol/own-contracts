// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/protocol/xToken.sol";
import "../src/interfaces/IXToken.sol";

contract MockPool {
    xToken public token;
    address public manager;
    
    constructor(string memory name, string memory symbol, address _manager) {
        manager = _manager;
        token = new xToken(name, symbol, manager);
    }
    
    function mint(address account, uint256 amount) external {
        token.mint(account, amount);
    }
    
    function burn(address account, uint256 amount) external {
        token.burn(account, amount);
    }
}

contract MockManager {
    function applySplit(
        IXToken token,
        uint256 splitRatio, 
        uint256 splitDenominator
    ) external {
        token.applySplit(splitRatio, splitDenominator);
    }
}

contract xTokenTest is Test {
    xToken public xtoken;
    MockPool public pool;
    MockManager public manager;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    
    uint256 constant PRECISION = 1e18;
    
    event Mint(address indexed account, uint256 amount);
    event Burn(address indexed account, uint256 amount);
    event StockSplitApplied(uint256 splitRatio, uint256 splitDenominator, uint256 newSplitMultiplier);
    
    function setUp() public {
        manager = new MockManager();
        pool = new MockPool("Test xToken", "xTST", address(manager));
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
        assertEq(xtoken.manager(), address(manager));
        assertEq(xtoken.XTOKEN_VERSION(), 0x1);
        assertEq(xtoken.totalSupply(), 0);
        assertEq(xtoken.splitMultiplier(), PRECISION); // Default split multiplier should be 1.0 (PRECISION)
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
    
    function test_BurnRevert_InsufficientBalance() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18);
        
        // Try to burn more than balance
        vm.prank(address(pool));
        vm.expectRevert(IXToken.InsufficientBalance.selector);
        xtoken.burn(alice, 1500 * 1e18);
    }
    
    // ============ Transfer Tests ============
    
    function test_Transfer() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18);
        
        // Transfer from alice to bob
        vm.prank(alice);
        xtoken.transfer(bob, 400 * 1e18);
        
        assertEq(xtoken.balanceOf(alice), 600 * 1e18);
        assertEq(xtoken.balanceOf(bob), 400 * 1e18);
    }
    
    function test_TransferFrom() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18);
        
        // Approve bob to spend alice's tokens
        vm.prank(alice);
        xtoken.approve(bob, 500 * 1e18);
        
        // Bob transfers from alice to charlie
        vm.prank(bob);
        xtoken.transferFrom(alice, charlie, 300 * 1e18);
        
        assertEq(xtoken.balanceOf(alice), 700 * 1e18);
        assertEq(xtoken.balanceOf(charlie), 300 * 1e18);
        assertEq(xtoken.allowance(alice, bob), 200 * 1e18);
    }
    
    // ============ Stock Split Tests ============
    
    function test_ForwardStockSplit() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18);
        vm.prank(address(pool));
        xtoken.mint(bob, 2000 * 1e18);
        
        // Apply a 2:1 stock split (double tokens)
        vm.expectEmit(false, false, false, true);
        emit StockSplitApplied(2, 1, 2 * PRECISION);
        
        vm.prank(address(manager));
        manager.applySplit(xtoken, 2, 1);
        
        // Check that balances are doubled
        assertEq(xtoken.balanceOf(alice), 2000 * 1e18);
        assertEq(xtoken.balanceOf(bob), 4000 * 1e18);
        assertEq(xtoken.totalSupply(), 6000 * 1e18);
        assertEq(xtoken.splitMultiplier(), 2 * PRECISION);
        
        // Check post-split transfers work correctly
        vm.prank(alice);
        xtoken.transfer(charlie, 500 * 1e18);
        
        assertEq(xtoken.balanceOf(alice), 1500 * 1e18);
        assertEq(xtoken.balanceOf(charlie), 500 * 1e18);
        
        // Check post-split minting and burning
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18);
        
        assertEq(xtoken.balanceOf(alice), 2500 * 1e18);
        
        vm.prank(address(pool));
        xtoken.burn(alice, 500 * 1e18);
        
        assertEq(xtoken.balanceOf(alice), 2000 * 1e18);
    }
    
    function test_ReverseStockSplit() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18);
        vm.prank(address(pool));
        xtoken.mint(bob, 2000 * 1e18);
        
        // Apply a 1:2 reverse stock split (halve tokens)
        vm.expectEmit(false, false, false, true);
        emit StockSplitApplied(1, 2, PRECISION / 2);
        
        vm.prank(address(manager));
        manager.applySplit(xtoken, 1, 2);
        
        // Check that balances are halved
        assertEq(xtoken.balanceOf(alice), 500 * 1e18);
        assertEq(xtoken.balanceOf(bob), 1000 * 1e18);
        assertEq(xtoken.totalSupply(), 1500 * 1e18);
        assertEq(xtoken.splitMultiplier(), PRECISION / 2);
        
        // Check post-split transfers work correctly
        vm.prank(alice);
        xtoken.transfer(charlie, 300 * 1e18);
        
        assertEq(xtoken.balanceOf(alice), 200 * 1e18);
        assertEq(xtoken.balanceOf(charlie), 300 * 1e18);
    }
    
    function test_MultipleStockSplits() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18);
        
        // Apply a 2:1 stock split (double tokens)
        vm.prank(address(manager));
        manager.applySplit(xtoken, 2, 1);
        
        assertEq(xtoken.balanceOf(alice), 2000 * 1e18);
        assertEq(xtoken.splitMultiplier(), 2 * PRECISION);
        
        // Apply another 2:1 stock split
        vm.prank(address(manager));
        manager.applySplit(xtoken, 2, 1);
        
        // Balance should now be 4x the original
        assertEq(xtoken.balanceOf(alice), 4000 * 1e18);
        assertEq(xtoken.splitMultiplier(), 4 * PRECISION);
        
        // Apply a 1:2 reverse split
        vm.prank(address(manager));
        manager.applySplit(xtoken, 1, 2);
        
        // Balance should now be 2x the original
        assertEq(xtoken.balanceOf(alice), 2000 * 1e18);
        assertEq(xtoken.splitMultiplier(), 2 * PRECISION);
    }
    
    function test_StockSplit_Allowances() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18);
        
        // Alice approves bob to spend half her tokens
        vm.prank(alice);
        xtoken.approve(bob, 500 * 1e18);
        
        // Apply a 2:1 stock split
        vm.prank(address(manager));
        manager.applySplit(xtoken, 2, 1);
        
        // Allowance should be doubled
        assertEq(xtoken.allowance(alice, bob), 1000 * 1e18);
        
        // Bob uses the allowance
        vm.prank(bob);
        xtoken.transferFrom(alice, charlie, 800 * 1e18);
        
        assertEq(xtoken.balanceOf(alice), 1200 * 1e18);
        assertEq(xtoken.balanceOf(charlie), 800 * 1e18);
        assertEq(xtoken.allowance(alice, bob), 200 * 1e18);
    }
    
    function test_RevertWhen_InvalidSplitRatio() public {
        vm.prank(address(manager));
        vm.expectRevert(IXToken.InvalidSplitRatio.selector);
        manager.applySplit(xtoken, 0, 1);
        
        vm.prank(address(manager));
        vm.expectRevert(IXToken.InvalidSplitRatio.selector);
        manager.applySplit(xtoken, 1, 0);
    }
    
    function test_RevertWhen_StockSplitNotManager() public {
        vm.prank(alice);
        vm.expectRevert(IXToken.NotManager.selector);
        xtoken.applySplit(2, 1);
    }
}