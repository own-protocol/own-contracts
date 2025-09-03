// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/invariant/StdInvariant.sol";
import "../../src/protocol/AssetPool.sol";
import "../../src/protocol/PoolLiquidityManager.sol";
import "../../src/protocol/PoolCycleManager.sol";
import "../../src/protocol/xToken.sol";
import "../../src/interfaces/IPoolStrategy.sol";
import "./handlers/InvariantHandler.sol";


/**
 * @title BaseInvariants
 * @notice Base contract with core invariants that all protocol tests should inherit
 * @dev Contains the most critical system properties
 */
abstract contract BaseInvariants is Test, StdInvariant {
    // Protocol contracts
    AssetPool public assetPool;
    PoolLiquidityManager public liquidityManager;
    PoolCycleManager public cycleManager;
    xToken public assetToken;
    MockERC20 public reserveToken;
    MockAssetOracle public assetOracle;
    IPoolStrategy public poolStrategy;
    
    // Handler for guided fuzzing
    InvariantHandler public handler;
    
    /**
     * @notice Setup handler and target contracts for invariant testing
     */
    function _setupInvariantTesting() internal {
        handler = new InvariantHandler(
            assetPool,
            liquidityManager,
            cycleManager,
            assetToken,
            reserveToken,
            assetOracle,
            poolStrategy
        );
        
        // Fund handler
        reserveToken.mint(address(handler), 10_000_000e6);
        
        // Set as target
        targetContract(address(handler));
        
        // Target specific functions
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = handler.deposit.selector;
        selectors[1] = handler.redeem.selector;
        selectors[2] = handler.addLiquidity.selector;
        selectors[3] = handler.reduceLiquidity.selector;
        selectors[4] = handler.completeCycle.selector;
        selectors[5] = handler.claimAssets.selector;
        selectors[6] = handler.claimReserves.selector;
        selectors[7] = handler.liquidateUser.selector;
        
        targetSelector(FuzzSelector({
            addr: address(handler),
            selectors: selectors
        }));
    }

    // ==================== CORE INVARIANTS ====================

    /**
     * @notice The most critical invariant - total reserve conservation
     * @dev Total reserves in system must equal sum of all accounted reserves
     */
    function invariant_totalReserveConservation() external {
        uint256 systemReserves = reserveToken.balanceOf(address(assetPool)) + 
                                reserveToken.balanceOf(address(liquidityManager));
        
        uint256 accountedReserves = assetPool.aggregatePoolReserves() + 
                                   liquidityManager.aggregatePoolReserves();
        
        assertEq(systemReserves, accountedReserves, "Reserve conservation violated");
    }

    /**
     * @notice Asset token supply must match user positions
     * @dev Total asset token supply should equal sum of all user asset amounts
     */
    function invariant_assetTokenSupplyConsistency() external {
        uint256 totalSupply = assetToken.totalSupply();
        uint256 sumUserAssets = handler.getTotalUserAssets();
        
        assertEq(totalSupply, sumUserAssets, "Asset token supply inconsistent with user positions");
    }

    /**
     * @notice Protocol solvency - assets can always be redeemed
     * @dev Total reserves must be sufficient to back all outstanding obligations
     */
    function invariant_protocolSolvency() external {
        uint256 totalReserves = assetPool.aggregatePoolReserves() + 
                               liquidityManager.aggregatePoolReserves();
        
        uint256 totalObligations = handler.getTotalUserDeposits() + 
                                  handler.getTotalUserCollateral() +
                                  liquidityManager.totalLPCollateral();
        
        assertGe(totalReserves, totalObligations, "Protocol insolvency detected");
    }

    /**
     * @notice User collateral conservation
     * @dev User collateral in assetPool should match sum of individual user collateral
     */
    function invariant_userCollateralConservation() external {
        uint256 totalUserCollateral = assetPool.totalUserCollateral();
        uint256 sumUserCollateral = handler.getTotalUserCollateral();
        
        assertEq(totalUserCollateral, sumUserCollateral, "User collateral conservation violated");
    }

    /**
     * @notice LP collateral must match tracked amounts
     * @dev Total LP collateral in liquidityManager should match sum of individual positions
     */
    function invariant_lpCollateralConsistency() external {
        uint256 totalLPCollateral = liquidityManager.totalLPCollateral();
        uint256 sumLPCollateral = handler.getTotalLPCollateral();
        
        assertEq(totalLPCollateral, sumLPCollateral, "LP collateral tracking inconsistent");
    }
}