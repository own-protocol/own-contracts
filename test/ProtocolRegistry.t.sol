// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/protocol/ProtocolRegistry.sol";
import "../src/interfaces/IProtocolRegistry.sol";

contract ProtocolRegistryTest is Test {
    ProtocolRegistry public registry;
    
    address public owner;
    address public nonOwner;
    address public strategy;
    address public oracle;
    address public pool;
    
    event StrategyVerificationUpdated(address indexed strategy, bool isVerified);
    event OracleVerificationUpdated(address indexed oracle, bool isVerified);
    event PoolVerificationUpdated(address indexed pool, bool isVerified);
    
    function setUp() public {
        owner = address(this);
        nonOwner = makeAddr("nonOwner");
        strategy = makeAddr("strategy");
        oracle = makeAddr("oracle");
        pool = makeAddr("pool");
        
        registry = new ProtocolRegistry();
    }
    
    // ==================== STRATEGY VERIFICATION TESTS ====================
    
    function testSetStrategyVerification() public {
        // Verify strategy
        vm.expectEmit(true, false, false, true);
        emit StrategyVerificationUpdated(strategy, true);
        registry.setStrategyVerification(strategy, true);
        
        // Check that strategy is verified
        assertTrue(registry.isStrategyVerified(strategy), "Strategy should be verified");
        
        // Unverify strategy
        vm.expectEmit(true, false, false, true);
        emit StrategyVerificationUpdated(strategy, false);
        registry.setStrategyVerification(strategy, false);
        
        // Check that strategy is no longer verified
        assertFalse(registry.isStrategyVerified(strategy), "Strategy should not be verified");
    }
    
    function testSetStrategyVerificationRevertWhenNotOwner() public {
        // Try to verify strategy as non-owner
        vm.prank(nonOwner);
        vm.expectRevert();
        registry.setStrategyVerification(strategy, true);
    }
    
    function testSetStrategyVerificationRevertWithZeroAddress() public {
        // Try to verify zero address
        vm.expectRevert(IProtocolRegistry.ZeroAddress.selector);
        registry.setStrategyVerification(address(0), true);
    }
    
    // ==================== ORACLE VERIFICATION TESTS ====================
    
    function testSetOracleVerification() public {
        // Verify oracle
        vm.expectEmit(true, false, false, true);
        emit OracleVerificationUpdated(oracle, true);
        registry.setOracleVerification(oracle, true);
        
        // Check that oracle is verified
        assertTrue(registry.isOracleVerified(oracle), "Oracle should be verified");
        
        // Unverify oracle
        vm.expectEmit(true, false, false, true);
        emit OracleVerificationUpdated(oracle, false);
        registry.setOracleVerification(oracle, false);
        
        // Check that oracle is no longer verified
        assertFalse(registry.isOracleVerified(oracle), "Oracle should not be verified");
    }
    
    function testSetOracleVerificationRevertWhenNotOwner() public {
        // Try to verify oracle as non-owner
        vm.prank(nonOwner);
        vm.expectRevert();
        registry.setOracleVerification(oracle, true);
    }
    
    function testSetOracleVerificationRevertWithZeroAddress() public {
        // Try to verify zero address
        vm.expectRevert(IProtocolRegistry.ZeroAddress.selector);
        registry.setOracleVerification(address(0), true);
    }
    
    // ==================== POOL VERIFICATION TESTS ====================
    
    function testSetPoolVerification() public {
        // Verify pool
        vm.expectEmit(true, false, false, true);
        emit PoolVerificationUpdated(pool, true);
        registry.setPoolVerification(pool, true);
        
        // Check that pool is verified
        assertTrue(registry.isPoolVerified(pool), "Pool should be verified");
        
        // Unverify pool
        vm.expectEmit(true, false, false, true);
        emit PoolVerificationUpdated(pool, false);
        registry.setPoolVerification(pool, false);
        
        // Check that pool is no longer verified
        assertFalse(registry.isPoolVerified(pool), "Pool should not be verified");
    }
    
    function testSetPoolVerificationRevertWhenNotOwner() public {
        // Try to verify pool as non-owner
        vm.prank(nonOwner);
        vm.expectRevert();
        registry.setPoolVerification(pool, true);
    }
    
    function testSetPoolVerificationRevertWithZeroAddress() public {
        // Try to verify zero address
        vm.expectRevert(IProtocolRegistry.ZeroAddress.selector);
        registry.setPoolVerification(address(0), true);
    }
    
    // ==================== MULTI-COMPONENT VERIFICATION TESTS ====================
    
    function testVerifyMultipleComponents() public {
        // Verify all components
        registry.setStrategyVerification(strategy, true);
        registry.setOracleVerification(oracle, true);
        registry.setPoolVerification(pool, true);
        
        // Check all components are verified
        assertTrue(registry.isStrategyVerified(strategy), "Strategy should be verified");
        assertTrue(registry.isOracleVerified(oracle), "Oracle should be verified");
        assertTrue(registry.isPoolVerified(pool), "Pool should be verified");
        
        // Unverify all components
        registry.setStrategyVerification(strategy, false);
        registry.setOracleVerification(oracle, false);
        registry.setPoolVerification(pool, false);
        
        // Check all components are unverified
        assertFalse(registry.isStrategyVerified(strategy), "Strategy should not be verified");
        assertFalse(registry.isOracleVerified(oracle), "Oracle should not be verified");
        assertFalse(registry.isPoolVerified(pool), "Pool should not be verified");
    }
    
    function testDefaultVerificationState() public {
        // Create new addresses
        address newStrategy = makeAddr("newStrategy");
        address newOracle = makeAddr("newOracle");
        address newPool = makeAddr("newPool");
        
        // Check that new components are not verified by default
        assertFalse(registry.isStrategyVerified(newStrategy), "New strategy should not be verified by default");
        assertFalse(registry.isOracleVerified(newOracle), "New oracle should not be verified by default");
        assertFalse(registry.isPoolVerified(newPool), "New pool should not be verified by default");
    }
}