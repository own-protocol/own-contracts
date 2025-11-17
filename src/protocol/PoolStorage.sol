// SPDX-License-Identifier: BUSL-1.1
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {IAssetPool} from "../interfaces/IAssetPool.sol";
import {IAssetOracle} from "../interfaces/IAssetOracle.sol";
import {IXToken} from "../interfaces/IXToken.sol";
import {IPoolLiquidityManager} from "../interfaces/IPoolLiquidityManager.sol";
import {IPoolCycleManager} from "../interfaces/IPoolCycleManager.sol";
import {IPoolStrategy} from "../interfaces/IPoolStrategy.sol";

/**
 * @title PoolStorage
 * @notice Shared storage variables for protocol contracts
 * @dev This contract is meant to be inherited by AssetPool, PoolCycleManager, and PoolLiquidityManager
 */
abstract contract PoolStorage is Initializable {
    // --------------------------------------------------------------------------------
    //                            STORAGE VARIABLES
    // --------------------------------------------------------------------------------

    /**
     * @notice Reserve token used for collateral (e.g., USDC)
     */
    IERC20Metadata public reserveToken;

    /**
     * @notice Asset token representing the underlying asset
     */
    IXToken public assetToken;

    /**
     * @notice Oracle providing asset price information
     */
    IAssetOracle public assetOracle;

    /**
     * @notice Asset pool contract for user positions
     */
    IAssetPool public assetPool;

    /**
     * @notice Pool Liquidity Manager contract
     */
    IPoolLiquidityManager public poolLiquidityManager;

    /**
     * @notice Pool Cycle Manager contract
     */
    IPoolCycleManager public poolCycleManager;

    /**
     * @notice Pool Strategy contract
     */
    IPoolStrategy public poolStrategy;

    /**
     * @notice Reserve to asset decimal factor for conversion calculations
     */
    uint256 public reserveToAssetDecimalFactor;

    // --------------------------------------------------------------------------------
    //                              CONSTANTS
    // --------------------------------------------------------------------------------

    /**
     * @notice Precision factor for calculations
     * @dev Used for fixed-point math throughout the protocol
     */
    uint256 internal constant PRECISION = 1e18;

    /**
     * @notice Basis points scaling factor (100% = 10000)
     */
    uint256 internal constant BPS = 100_00;

    /**
     * @notice Seconds in a year, used for interest calculations
     */
    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    // --------------------------------------------------------------------------------
    //                          INITIALIZATION HELPER
    // --------------------------------------------------------------------------------

    /**
     * @notice Initializes the decimal conversion factor between reserve and asset tokens
     * @dev Should be called during contract initialization
     * @param _reserveToken Address of the reserve token
     * @param _assetToken Address of the asset token
     */
    function _initializeDecimalFactor(address _reserveToken, address _assetToken) internal {
        uint8 reserveDecimals = IERC20Metadata(_reserveToken).decimals();
        uint8 assetDecimals = IERC20Metadata(_assetToken).decimals();

        require(reserveDecimals <= assetDecimals, "decimals: reserve > asset");
        
        reserveToAssetDecimalFactor = 10 ** uint256(assetDecimals - reserveDecimals);
    }

    /**
     * @notice Converts asset amount to reserve amount based on the asset price (decimal adjusted)
     * @param assetAmount The amount of asset to convert
     * @param price The price of the asset in reserve terms
     */
    function _convertAssetToReserve(uint256 assetAmount, uint256 price) internal view returns (uint256) {
        return Math.mulDiv(assetAmount, price , PRECISION * reserveToAssetDecimalFactor);
    }

    /**
     * @notice Converts reserve amount to asset amount based on the asset price (decimal adjusted)
     * @param reserveAmount The amount of reserve to convert
     * @param price The price of the asset in reserve terms
     */
    function _convertReserveToAsset(uint256 reserveAmount, uint256 price) internal view returns (uint256) {
        return price > 0 ? Math.mulDiv(reserveAmount, PRECISION * reserveToAssetDecimalFactor, price) : 0;
    }
}