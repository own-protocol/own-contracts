// SPDX-License-Identifier: GPL-3.0-or-later
// author: bhargavaparoksham

pragma solidity ^0.8.20;

/**
 * @title IProtocolRegistry
 * @notice Interface for the ProtocolRegistry contract that tracks verified protocol contracts
 */
interface IProtocolRegistry {
    /**
     * @notice Emitted when a strategy is added to or removed from the registry
     * @param strategy Address of the strategy
     * @param isVerified New verification status
     */
    event StrategyVerificationUpdated(address indexed strategy, bool isVerified);

    /**
     * @notice Emitted when an oracle is added to or removed from the registry
     * @param oracle Address of the oracle
     * @param isVerified New verification status
     */
    event OracleVerificationUpdated(address indexed oracle, bool isVerified);

    /**
     * @notice Emitted when a pool is added to or removed from the registry
     * @param pool Address of the pool
     * @param isVerified New verification status
     */
    event PoolVerificationUpdated(address indexed pool, bool isVerified);

    /**
     * @notice Sets the verification status of a strategy
     * @param strategy Address of the strategy
     * @param isVerified New verification status
     */
    function setStrategyVerification(address strategy, bool isVerified) external;

    /**
     * @notice Sets the verification status of an oracle
     * @param oracle Address of the oracle
     * @param isVerified New verification status
     */
    function setOracleVerification(address oracle, bool isVerified) external;

    /**
     * @notice Sets the verification status of a pool
     * @param pool Address of the pool
     * @param isVerified New verification status
     */
    function setPoolVerification(address pool, bool isVerified) external;

    /**
     * @notice Checks if a strategy is verified
     * @param strategy Address of the strategy
     * @return True if the strategy is verified
     */
    function isStrategyVerified(address strategy) external view returns (bool);

    /**
     * @notice Checks if an oracle is verified
     * @param oracle Address of the oracle
     * @return True if the oracle is verified
     */
    function isOracleVerified(address oracle) external view returns (bool);

    /**
     * @notice Checks if a pool is verified
     * @param pool Address of the pool
     * @return True if the pool is verified
     */
    function isPoolVerified(address pool) external view returns (bool);
}