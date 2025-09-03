// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./AdvancedInvariants.sol";
import "../utils/ProtocolTestUtils.sol";

/**
 * @title ProtocolInvariantTest
 * @notice Main invariant test contract that combines all invariant categories
 * @dev Inherits from AdvancedInvariants which includes BaseInvariants
 */
contract ProtocolInvariantTest is ProtocolTestUtils, AdvancedInvariants {
    // Protocol constants
    uint256 public constant INITIAL_PRICE = 100 * 1e18;
    uint256 public constant USER_BALANCE = 1_000_000;
    uint256 public constant LP_BALANCE = 10_000_000;
    uint256 public constant LP_LIQUIDITY = 5_000_000;
    
    function setUp() public {
        // Deploy protocol with USDC-like 6 decimal token
        bool success = setupProtocol(
            "xTSLA",
            6,
            INITIAL_PRICE,
            USER_BALANCE,
            LP_BALANCE,
            LP_LIQUIDITY
        );
        require(success, "Protocol setup failed");
        
        // Setup invariant testing infrastructure
        _setupInvariantTesting();
    }
}