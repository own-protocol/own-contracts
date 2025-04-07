// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "../interfaces/IProtocolRegistry.sol";

/**
 * @title ProtocolRegistry
 * @notice Tracks verified protocol contracts (strategies, oracles, pools)
 * @dev Only the owner can add or remove components
 */
contract ProtocolRegistry is IProtocolRegistry, Ownable {
    // Mapping of strategy addresses to verification status
    mapping(address => bool) private verifiedStrategies;
    
    // Mapping of oracle addresses to verification status
    mapping(address => bool) private verifiedOracles;
    
    // Mapping of pool addresses to verification status
    mapping(address => bool) private verifiedPools;

    /**
     * @notice Constructs the ProtocolRegistry contract
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @notice Sets the verification status of a strategy
     * @param strategy Address of the strategy
     * @param isVerified New verification status
     */
    function setStrategyVerification(address strategy, bool isVerified) external onlyOwner {
        if (strategy == address(0)) revert ZeroAddress();
        
        verifiedStrategies[strategy] = isVerified;
        
        emit StrategyVerificationUpdated(strategy, isVerified);
    }

    /**
     * @notice Sets the verification status of an oracle
     * @param oracle Address of the oracle
     * @param isVerified New verification status
     */
    function setOracleVerification(address oracle, bool isVerified) external onlyOwner {
        if (oracle == address(0)) revert ZeroAddress();
        
        verifiedOracles[oracle] = isVerified;
        
        emit OracleVerificationUpdated(oracle, isVerified);
    }

    /**
     * @notice Sets the verification status of a pool
     * @param pool Address of the pool
     * @param isVerified New verification status
     */
    function setPoolVerification(address pool, bool isVerified) external onlyOwner {
        if (pool == address(0)) revert ZeroAddress();
        
        verifiedPools[pool] = isVerified;
        
        emit PoolVerificationUpdated(pool, isVerified);
    }

    /**
     * @notice Checks if a strategy is verified
     * @param strategy Address of the strategy
     * @return True if the strategy is verified
     */
    function isStrategyVerified(address strategy) external view returns (bool) {
        return verifiedStrategies[strategy];
    }

    /**
     * @notice Checks if an oracle is verified
     * @param oracle Address of the oracle
     * @return True if the oracle is verified
     */
    function isOracleVerified(address oracle) external view returns (bool) {
        return verifiedOracles[oracle];
    }

    /**
     * @notice Checks if a pool is verified
     * @param pool Address of the pool
     * @return True if the pool is verified
     */
    function isPoolVerified(address pool) external view returns (bool) {
        return verifiedPools[pool];
    }
}