// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {IOracle} from "@morpho-blue/interfaces/IOracle.sol";
import {IAssetOracle} from "../interfaces/IAssetOracle.sol";

/// @title MorphoOracleAdapter
/// @notice Adapts Own Protocol's AssetOracle to Morpho Blue's IOracle interface
/// @dev Returns price scaled to 10^(36 + loanDecimals - collateralDecimals) = 10^24
contract MorphoOracleAdapter is IOracle {
    IAssetOracle public immutable assetOracle;

    /// @notice Scale factor: 10^24 / 10^18 = 10^6
    uint256 internal constant SCALE_FACTOR = 1e6;

    constructor(address _assetOracle) {
        assetOracle = IAssetOracle(_assetOracle);
    }

    /// @notice Returns the price of 1 AI7 token in USDC terms, scaled to 10^24
    function price() external view override returns (uint256) {
        return assetOracle.assetPrice() * SCALE_FACTOR;
    }
}