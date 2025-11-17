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
     * @notice Emitted when a protocol keeper is added or removed
     * @param keeper The address of the protocol keeper
     * @param isAdded Boolean indicating if the keeper was added (true) or removed (false)
     */
    event ProtocolKeeperUpdated(address keeper, bool isAdded);

    /**
     * @notice Emitted when the market open threshold is updated
     * @param oldThreshold The previous time threshold in seconds
     * @param newThreshold The new time threshold in seconds
     */
    event MarketOpenThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    /**
     * @notice Emitted when the default subscription ID is updated
     * @param oldSubscriptionId The previous default subscription ID
     * @param newSubscriptionId The new default subscription ID
     */
    event DefaultSubscriptionIdUpdated(uint256 oldSubscriptionId, uint256 newSubscriptionId);

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
     * @notice Emitted when a split is detected
     * @param prevPrice The price before the split
     * @param timestamp The timestamp when the split was detected
     */
    event SplitDetected(
        uint256 prevPrice,
        uint256 timestamp
    );

    /**
     * @notice Emitted when the request cooldown is updated
     * @param oldCooldown The previous cooldown duration
     * @param newCooldown The new cooldown duration
     */
    event RequestCooldownUpdated(uint256 oldCooldown, uint256 newCooldown);

    /**
     * @notice Emitted when the split detection state is reset
     * @param timestamp The timestamp when the split detection was reset
     */
    event SplitDetectionReset(uint256 timestamp);

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
     * @notice Thrown when trying to request a price update before the cooldown period has elapsed
     */
    error RequestCooldownNotElapsed();

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
     * @notice Updates the default Chainlink Functions subscription ID
     * @param newSubscriptionId The new default subscription ID
     */
    function updateDefaultSubscriptionId(uint256 newSubscriptionId) external;

    /**
     * @notice Updates the market open threshold
     * @param newThreshold The new time threshold in seconds
     */
    function updateMarketOpenThreshold(uint256 newThreshold) external;

    /**
     * @notice Updates the status of a protocol keeper
     * @param keeper The address of the protocol keeper
     * @param isActive The new status of the protocol keeper
     */
    function updateProtocolKeeper(address keeper, bool isActive) external;

    /**
     * @notice Returns the current asset price
     * @return The current price in cents
     */
    function assetPrice() external view returns (uint256);

    /**
     * @notice Checks if a split has been detected
     */
    function splitDetected() external view returns (bool);

    /**
     * @notice Returns the price before the last split
     */
    function preSplitPrice() external view returns (uint256);

    /**
     * @notice Returns the timestamp of the last price update
     * @return The timestamp of the last update
     */
    function lastUpdated() external view returns (uint256);

    /**
     * @notice Returns the timestamp of the last price request
     * @return The timestamp of the last request
     */
    function lastRequestedAt() external view returns (uint256);

    /**
    * @notice Returns the market open threshold in seconds
    */
    function MARKET_OPEN_THRESHOLD() external view returns (uint256);

    /**
     * @notice Returns the request cooldown period in seconds
     */
    function REQUEST_COOLDOWN() external view returns (uint256);

    /**
     * @notice Returns the default Chainlink Functions subscription ID
     */
    function defaultSubscriptionId() external view returns (uint256);

    /**
     * @notice Checks if an address is a protocol keeper
     * @param keeper The address to check
     * @return bool True if the address is a protocol keeper, false otherwise
     */
    function protocolKeepers(address keeper) external view returns (bool);

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
    function ohlcData() external view returns (
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

    /**
     * @notice Checks if a split has likely occurred based on price change
     * @param expectedRatio Expected split ratio
     * @param expectedDenominator Expected split denominator
     * @return true if a split matching the expected ratio appears to have occurred
     */
    function verifySplit(uint256 expectedRatio, uint256 expectedDenominator) external view returns (bool);

    /**
     * @notice Sets the split detected state. This function is used to manually set the split state
     * @dev Can only be called by the contract owner
     */
    function setSplitDetected() external;

    /**
     * @notice Resets the split detection state
     * @dev Can only be called by the contract owner
     */
    function resetSplitDetection() external;

    /**
     * @notice Updates the cooldown period for price requests
     * @param newCooldown The new cooldown period in seconds
     * @dev Can only be called by the contract owner
     */
    function updateRequestCooldown(uint256 newCooldown) external;
}