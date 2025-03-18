// Asset price function to be used in the AssetOracle contract to fetch data from Yahoo Finance using Chainlink Functions.

// Import ethers from npm
const ethers = await import("npm:ethers@6.10.0");

// Fetch TSLA data from Yahoo Finance
const yahooFinanceUrl = `https://query1.finance.yahoo.com/v8/finance/chart/TSLA?interval=1d`;

// Make the HTTP request
const response = await Functions.makeHttpRequest({ url: yahooFinanceUrl });

// Verify the response
if (!response || response.status !== 200) {
  throw new Error("Failed to fetch asset data");
}

// Extract the data from the response
const data = response.data.chart.result[0];
const meta = data.meta;
const regularMarketPrice = meta.regularMarketPrice;
const timestamp = data.timestamp[0];
const indicators = data.indicators;

// Extract OHLC data
const quote = indicators.quote[0];
const open = quote.open[0];
const high = quote.high[0];
const low = quote.low[0];
const close = quote.close[0];
const volume = Math.round(quote.volume[0]);

// Extract regular market trading period data
const regularMarketPeriod = meta.currentTradingPeriod.regular;
const regularMarketStart = regularMarketPeriod.start;
const regularMarketEnd = regularMarketPeriod.end;
const gmtOffset = regularMarketPeriod.gmtoffset;

// Convert values to wei (18 decimal places)
const toWei = (value) => BigInt(Math.round(value * 1e18));

// Log the data for debugging
console.log(`TSLA Data Retrieved:`);
console.log(`Current Price: $${regularMarketPrice}`);
console.log(`OHLC: Open=$${open}, High=$${high}, Low=$${low}, Close=$${close}`);
console.log(`Volume: ${volume}`);
console.log(`Timestamp: ${new Date(timestamp * 1000).toISOString()}`);
console.log(
  `Market Hours: ${new Date(
    regularMarketStart * 1000
  ).toISOString()} - ${new Date(regularMarketEnd * 1000).toISOString()}`
);

// Use ethers to ABI encode the data in a format that can be directly decoded in Solidity
// The format matches our Solidity decoding: (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256)
const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
  [
    "uint256",
    "uint256",
    "uint256",
    "uint256",
    "uint256",
    "uint256",
    "uint256",
    "uint256",
    "uint256",
    "uint256",
  ],
  [
    toWei(regularMarketPrice), // Current price
    toWei(open), // Opening price
    toWei(high), // Highest price
    toWei(low), // Lowest price
    toWei(close), // Closing price
    BigInt(volume), // Trading volume
    BigInt(timestamp), // Data timestamp
    BigInt(regularMarketStart), // Regular market start time
    BigInt(regularMarketEnd), // Regular market end time
    BigInt(gmtOffset), // GMT offset
  ]
);

// Return the ABI encoded data as Uint8Array
return ethers.getBytes(encoded);
