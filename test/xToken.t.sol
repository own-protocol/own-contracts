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
    
    function mint(address account, uint256 amount, uint256 reserve) external {
        token.mint(account, amount, reserve);
    }
    
    function burn(address account, uint256 amount, uint256 reserve) external {
        token.burn(account, amount, reserve);
    }
}

contract xTokenTest is Test {
    xToken public xtoken;
    MockPool public pool;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    
    event Mint(address indexed account, uint256 amount, uint256 reserve);
    event Burn(address indexed account, uint256 amount, uint256 reserve);
    
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
        assertEq(xtoken.totalReserveSupply(), 0);
    }
    
    // ============ Mint Tests ============
    
    function test_Mint() public {
        uint256 mintAmount = 1000 * 1e18;
        uint256 reserveAmount = 500 * 1e18;
        
        vm.expectEmit(true, false, false, true);
        emit Mint(alice, mintAmount, reserveAmount);
        
        vm.prank(address(pool));
        xtoken.mint(alice, mintAmount, reserveAmount);
        
        assertEq(xtoken.balanceOf(alice), mintAmount);
        assertEq(xtoken.reserveBalanceOf(alice), reserveAmount);
        assertEq(xtoken.totalSupply(), mintAmount);
        assertEq(xtoken.totalReserveSupply(), reserveAmount);
    }
    
    function test_Mint_Multiple() public {
        // First mint to alice
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18, 500 * 1e18);
        
        // Second mint to alice
        vm.prank(address(pool));
        xtoken.mint(alice, 500 * 1e18, 250 * 1e18);
        
        // Mint to bob
        vm.prank(address(pool));
        xtoken.mint(bob, 2000 * 1e18, 1000 * 1e18);
        
        assertEq(xtoken.balanceOf(alice), 1500 * 1e18);
        assertEq(xtoken.reserveBalanceOf(alice), 750 * 1e18);
        assertEq(xtoken.balanceOf(bob), 2000 * 1e18);
        assertEq(xtoken.reserveBalanceOf(bob), 1000 * 1e18);
        assertEq(xtoken.totalSupply(), 3500 * 1e18);
        assertEq(xtoken.totalReserveSupply(), 1750 * 1e18);
    }
    
    function test_RevertWhen_MintNotPool() public {
        vm.prank(alice);
        vm.expectRevert(IXToken.NotPool.selector);
        xtoken.mint(alice, 1000 * 1e18, 500 * 1e18);
    }
    
    function test_MintRevert_NotPool() public {
        vm.prank(alice);
        vm.expectRevert(IXToken.NotPool.selector);
        xtoken.mint(alice, 1000 * 1e18, 500 * 1e18);
    }
    
    // ============ Burn Tests ============
    
    function test_Burn() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18, 500 * 1e18);
        
        // Burn half
        uint256 burnAmount = 500 * 1e18;
        uint256 burnReserve = 250 * 1e18;
        
        vm.expectEmit(true, false, false, true);
        emit Burn(alice, burnAmount, burnReserve);
        
        vm.prank(address(pool));
        xtoken.burn(alice, burnAmount, burnReserve);
        
        assertEq(xtoken.balanceOf(alice), 500 * 1e18);
        assertEq(xtoken.reserveBalanceOf(alice), 250 * 1e18);
        assertEq(xtoken.totalSupply(), 500 * 1e18);
        assertEq(xtoken.totalReserveSupply(), 250 * 1e18);
    }
    
    function test_RevertWhen_BurnNotPool() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18, 500 * 1e18);
        
        // Try to burn as non-pool
        vm.prank(alice);
        vm.expectRevert(IXToken.NotPool.selector);
        xtoken.burn(alice, 500 * 1e18, 250 * 1e18);
    }
    
    function test_BurnRevert_NotPool() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18, 500 * 1e18);
        
        // Try to burn as non-pool
        vm.prank(alice);
        vm.expectRevert(IXToken.NotPool.selector);
        xtoken.burn(alice, 500 * 1e18, 250 * 1e18);
    }
    
    function test_BurnRevert_InsufficientBalance() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18, 500 * 1e18);
        
        // Try to burn more than balance
        vm.prank(address(pool));
        vm.expectRevert(IXToken.InsufficientBalance.selector);
        xtoken.burn(alice, 1500 * 1e18, 250 * 1e18);
        
        // Try to burn more reserve than available
        vm.prank(address(pool));
        vm.expectRevert(IXToken.InsufficientBalance.selector);
        xtoken.burn(alice, 500 * 1e18, 600 * 1e18);
    }
    
    // ============ Transfer Tests ============
    
    function test_Transfer() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18, 500 * 1e18);
        
        // Transfer to Bob
        uint256 transferAmount = 400 * 1e18;
        // Expected reserve transfer: 400/1000 * 500 = 200
        
        vm.prank(alice);
        bool success = xtoken.transfer(bob, transferAmount);
        
        assertTrue(success);
        assertEq(xtoken.balanceOf(alice), 600 * 1e18);
        assertEq(xtoken.balanceOf(bob), 400 * 1e18);
        assertEq(xtoken.reserveBalanceOf(alice), 300 * 1e18);
        assertEq(xtoken.reserveBalanceOf(bob), 200 * 1e18);
        assertEq(xtoken.totalSupply(), 1000 * 1e18);
        assertEq(xtoken.totalReserveSupply(), 500 * 1e18);
    }
    
    function test_Transfer_Partial() public {
        // Mint tokens to alice and bob
        vm.startPrank(address(pool));
        xtoken.mint(alice, 1000 * 1e18, 500 * 1e18);
        xtoken.mint(bob, 200 * 1e18, 100 * 1e18);
        vm.stopPrank();
        
        // Alice transfers to bob
        vm.prank(alice);
        xtoken.transfer(bob, 600 * 1e18);
        
        assertEq(xtoken.balanceOf(alice), 400 * 1e18);
        assertEq(xtoken.balanceOf(bob), 800 * 1e18);
        // Expected reserve: 600/1000 * 500 = 300 transferred
        assertEq(xtoken.reserveBalanceOf(alice), 200 * 1e18);
        assertEq(xtoken.reserveBalanceOf(bob), 400 * 1e18);
    }
    
    function test_TransferRevert_ZeroAddress() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18, 500 * 1e18);
        
        // Try to transfer to zero address
        vm.prank(alice);
        vm.expectRevert(IXToken.ZeroAddress.selector);
        xtoken.transfer(address(0), 500 * 1e18);
    }
    
    function test_TransferRevert_InsufficientBalance() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18, 500 * 1e18);
        
        // Try to transfer more than balance
        vm.prank(alice);
        vm.expectRevert(IXToken.InsufficientBalance.selector);
        xtoken.transfer(bob, 1500 * 1e18);
    }
    
    // ============ TransferFrom Tests ============
    
    function test_TransferFrom() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18, 500 * 1e18);
        
        // Approve Bob to spend Alice's tokens
        vm.prank(alice);
        xtoken.approve(bob, 600 * 1e18);
        
        // Bob transfers Alice's tokens to Charlie
        vm.prank(bob);
        bool success = xtoken.transferFrom(alice, charlie, 400 * 1e18);
        
        assertTrue(success);
        assertEq(xtoken.allowance(alice, bob), 200 * 1e18);
        assertEq(xtoken.balanceOf(alice), 600 * 1e18);
        assertEq(xtoken.balanceOf(charlie), 400 * 1e18);
        // Expected reserve: 400/1000 * 500 = 200 transferred
        assertEq(xtoken.reserveBalanceOf(alice), 300 * 1e18);
        assertEq(xtoken.reserveBalanceOf(charlie), 200 * 1e18);
    }
    
    function test_TransferFromRevert_InsufficientAllowance() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18, 500 * 1e18);
        
        // Approve Bob to spend Alice's tokens, but not enough
        vm.prank(alice);
        xtoken.approve(bob, 300 * 1e18);
        
        // Bob tries to transfer more than allowance
        vm.prank(bob);
        vm.expectRevert(IXToken.InsufficientAllowance.selector);
        xtoken.transferFrom(alice, charlie, 400 * 1e18);
    }
    
    function test_TransferFromRevert_ZeroAddress() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18, 500 * 1e18);
        
        // Approve Bob
        vm.prank(alice);
        xtoken.approve(bob, 500 * 1e18);
        
        // Bob tries to transfer to zero address
        vm.prank(bob);
        vm.expectRevert(IXToken.ZeroAddress.selector);
        xtoken.transferFrom(alice, address(0), 400 * 1e18);
    }
    
    // ============ Edge Cases ============
    
    function test_TransferZeroAmount() public {
        // Mint tokens first
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18, 500 * 1e18);
        
        // Transfer zero tokens
        vm.prank(alice);
        bool success = xtoken.transfer(bob, 0);
        
        assertTrue(success);
        assertEq(xtoken.balanceOf(alice), 1000 * 1e18);
        assertEq(xtoken.balanceOf(bob), 0);
        assertEq(xtoken.reserveBalanceOf(alice), 500 * 1e18);
        assertEq(xtoken.reserveBalanceOf(bob), 0);
    }
    
    function test_MintZeroAmount() public {
        vm.prank(address(pool));
        xtoken.mint(alice, 0, 0);
        
        assertEq(xtoken.balanceOf(alice), 0);
        assertEq(xtoken.reserveBalanceOf(alice), 0);
        assertEq(xtoken.totalSupply(), 0);
        assertEq(xtoken.totalReserveSupply(), 0);
    }
    
    function test_ReserveRounding() public {
        // Create an uneven ratio between token and reserve
        vm.prank(address(pool));
        xtoken.mint(alice, 1000 * 1e18, 333 * 1e18);
        
        // Transfer an amount that would cause reserve calculation to have remainders
        vm.prank(alice);
        xtoken.transfer(bob, 100 * 1e18);
        
        // Get the actual values after transfer
        uint256 aliceReserve = xtoken.reserveBalanceOf(alice);
        uint256 bobReserve = xtoken.reserveBalanceOf(bob);
        
        // Verify balances
        assertEq(xtoken.balanceOf(alice), 900 * 1e18);
        assertEq(xtoken.balanceOf(bob), 100 * 1e18);
        
        // Instead of hardcoding expected values, verify mathematical relationship
        // 1. The total reserve should remain unchanged
        assertEq(aliceReserve + bobReserve, 333 * 1e18);
        
        // 2. Bob's reserve should be proportional to his token balance
        // Expected: 100/1000 * 333 = 33.3 (exact calculation gives us 33.3e18)
        uint256 expectedBobReserve = (100 * 333 * 1e18) / 1000;
        assertEq(bobReserve, expectedBobReserve);
        
        // 3. Alice's reserve should be the remainder
        assertEq(aliceReserve, 333 * 1e18 - expectedBobReserve);
    }
    
    function test_PermitFunctionality() public {
        uint256 privateKey = 0xA11CE;
        address owner = vm.addr(privateKey);
        
        // Mint tokens to the owner
        vm.prank(address(pool));
        xtoken.mint(owner, 1000 * 1e18, 500 * 1e18);
        
        // Prepare permit data
        uint256 value = 500 * 1e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint8 v;
        bytes32 r;
        bytes32 s;
        bytes32 permitHash = _getPermitHash(
            owner,
            bob,
            value,
            0, // nonce is 0 for first permit
            deadline
        );
        
        (v, r, s) = vm.sign(privateKey, permitHash);
        
        // Execute permit
        xtoken.permit(owner, bob, value, deadline, v, r, s);
        
        // Verify allowance was set
        assertEq(xtoken.allowance(owner, bob), value);
        
        // Bob should now be able to transfer tokens
        vm.prank(bob);
        xtoken.transferFrom(owner, charlie, 300 * 1e18);
        
        assertEq(xtoken.balanceOf(owner), 700 * 1e18);
        assertEq(xtoken.balanceOf(charlie), 300 * 1e18);
        assertEq(xtoken.allowance(owner, bob), 200 * 1e18);
    }
    
    // Helper function to compute permit digest
    function _getPermitHash(
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) private view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                xtoken.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        owner,
                        spender,
                        value,
                        nonce,
                        deadline
                    )
                )
            )
        );
    }
}