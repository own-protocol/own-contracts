
// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import 'openzeppelin-contracts/contracts/access/Ownable.sol';
import {ILPRegistry} from '../interfaces/ILPRegistry.sol';
import {IPoolFactory} from '../interfaces/IAssetPoolFactory.sol';
import {AssetPool} from './AssetPool.sol';

contract PoolFactory is IPoolFactory, Ownable {
    ILPRegistry public immutable lpRegistry;
    
    constructor(address _lpRegistry) Ownable(msg.sender) {
        if (_lpRegistry == address(0)) revert ZeroAddress();
        lpRegistry = ILPRegistry(_lpRegistry);
    }

    function createPool(
        string memory assetSymbol,
        string memory assetTokenName,
        string memory assetTokenSymbol,
        address depositToken,
        address oracle,
        uint256 cyclePeriod,
        uint256 rebalancingPeriod
    ) external onlyOwner returns (address) {
        if (
            depositToken == address(0) ||
            oracle == address(0) ||
            cyclePeriod == 0 ||
            rebalancingPeriod >= cyclePeriod
        ) revert InvalidParams();

        AssetPool pool = new AssetPool(
            depositToken,
            assetTokenName,
            assetTokenSymbol,
            oracle,
            address(lpRegistry),
            cyclePeriod,
            rebalancingPeriod,
            msg.sender
        );

        lpRegistry.addPool(address(pool));

        emit PoolCreated(
            address(pool),
            assetSymbol,
            depositToken,
            oracle,
            cyclePeriod,
            rebalancingPeriod
        );

        return address(pool);
    }
}
