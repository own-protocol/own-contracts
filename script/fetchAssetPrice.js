// Asset price function to be used in the AssetOracle contract to fetch data from Yahoo Finance using Chainlink Functions.

const assetSymbol = args[0];
const yahooFinanceUrl = `https://query1.finance.yahoo.com/v8/finance/chart/${assetSymbol}?interval=1d`;

const response = await Functions.makeHttpRequest({ url: yahooFinanceUrl });
if (!response || response.status !== 200)
  throw new Error("Failed to fetch asset data");

const data = response.data.chart.result[0];
const currentPrice = data.meta.regularMarketPrice;

return Functions.encodeUint256(Math.round(currentPrice * 100));
