// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import {ILPRegistry} from './ILPRegistry.sol';

interface IPoolFactory {
    event PoolCreated(
        address indexed pool,
        string assetSymbol,
        address depositToken,
        address oracle,
        uint256 cycleLength,
        uint256 rebalancingPeriod
    );

    error InvalidParams();
    error ZeroAddress();

    function lpRegistry() external view returns (ILPRegistry);
    
    function createPool(
        string memory assetSymbol,
        string memory assetTokenName,
        string memory assetTokenSymbol,
        address depositToken,
        address oracle,
        uint256 cycleLength,
        uint256 rebalancingPeriod
    ) external returns (address);
}