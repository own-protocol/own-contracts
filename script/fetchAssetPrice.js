const assetSymbol = args[0];
const yahooFinanceUrl = `https://query1.finance.yahoo.com/v8/finance/chart/${assetSymbol}?interval=1d`;

const response = await Functions.makeHttpRequest({ url: yahooFinanceUrl });
if (!response || response.status !== 200)
  throw new Error("Failed to fetch asset data");

const data = response.data.chart.result[0];
const currentPrice = data.meta.regularMarketPrice;
const marketState = data.meta.marketState === "REGULAR";

return (
  Functions.encodeUint256(Math.round(currentPrice * 100)),
  Functions.encodeBool(marketState)
);
