// SPDX-License-Identifier: GPL-3.0-or-later
// author: bhargavaparoksham

pragma solidity ^0.8.20;

/**
 * @title IAssetOracle
 * @notice Interface for the AssetOracle contract that fetches and stores real-world asset prices
 * @notice Implements Chainlink Functions to fetch off-chain asset prices
 */
interface IAssetOracle {
    /**
     * @notice Emitted when the asset symbol is updated
     * @param newAssetSymbol The new symbol for the asset
     */
    event AssetSymbolUpdated(string newAssetSymbol);

    /**
     * @notice Emitted when a new price is received and updated
     * @param price The new price of the asset in cents
     * @param timestamp The timestamp when the price was updated
     */
    event AssetPriceUpdated(uint256 price, uint256 timestamp);

    /**
     * @notice Emitted when the source hash is updated
     * @param newSourceHash The new hash of the JavaScript source code
     */
    event SourceHashUpdated(bytes32 newSourceHash);
    
    /**
     * @notice Emitted when OHLC data is updated
     * @param open The opening price
     * @param high The highest price
     * @param low The lowest price
     * @param close The closing price
     * @param timestamp The timestamp of the OHLC data
     */
    event OHLCDataUpdated(
        uint256 open,
        uint256 high,
        uint256 low,
        uint256 close,
        uint256 timestamp
    );

    /**
     * @notice Thrown when received requestId doesn't match the expected one
     * @param requestId The unexpected requestId received
     */
    error UnexpectedRequestID(bytes32 requestId);

    /**
     * @notice Thrown when the provided source code hash doesn't match the stored hash
     */
    error InvalidSource();

    /**
     * @notice Thrown when the asset price is not valid
     */
    error InvalidPrice();

    /**
     * @notice Initiates a request to fetch the current asset price
     * @param source The JavaScript source code to execute
     * @param subscriptionId The Chainlink Functions subscription ID
     * @param gasLimit The gas limit for the request
     * @param donID The Chainlink Functions DON ID
     */
    function requestAssetPrice(
        string memory source,
        uint64 subscriptionId,
        uint32 gasLimit,
        bytes32 donID
    ) external;

    /**
     * @notice Updates the hash of the valid JavaScript source code
     * @param newSourceHash The new hash to validate source code against
     */
    function updateSourceHash(bytes32 newSourceHash) external;

    /**
     * @notice Updates the asset symbol
     * @param newAssetSymbol The new asset symbol
     */
    function updateAssetSymbol(string memory newAssetSymbol) external;

    /**
     * @notice Returns the current asset price
     * @return The current price in cents
     */
    function assetPrice() external view returns (uint256);

    /**
     * @notice Returns the timestamp of the last price update
     * @return The timestamp of the last update
     */
    function lastUpdated() external view returns (uint256);

    /**
     * @notice Returns the current asset symbol
     * @return The asset symbol (e.g., "TSLA")
     */
    function assetSymbol() external view returns (string memory);

    /**
     * @notice Returns the hash of the valid source code
     * @return The source code hash
     */
    function sourceHash() external view returns (bytes32);

    /**
     * @notice Returns the last request ID
     * @return The ID of the last Chainlink Functions request
     */
    function s_lastRequestId() external view returns (bytes32);
    
    /**
     * @notice Returns the current OHLC data for the asset
     * @return open The opening price
     * @return high The highest price
     * @return low The lowest price
     * @return close The closing price
     * @return timestamp The timestamp of the OHLC data
     */
    function getOHLCData() external view returns (
        uint256 open,
        uint256 high,
        uint256 low,
        uint256 close,
        uint256 timestamp
    );

    /**
     * @notice Checks if the market for the tracked asset is currently open
     * @dev Determines market status by comparing the data source timestamp with the oracle update time
     * @dev The market status is at the time of the last update. To get the current status, call this function after a new update
     * @return bool True if the market is open, false otherwise
     */
    function isMarketOpen() external view returns (bool);
}