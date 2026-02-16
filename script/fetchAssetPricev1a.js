const ethers = await import("npm:ethers@6.10.0");

const [priceRes, marketRes] = await Promise.all([
  Functions.makeHttpRequest({
    url: `https://query1.finance.yahoo.com/v8/finance/chart/MAGS?interval=1d`,
    headers: {
      "User-Agent": "Mozilla/5.0",
    },
  }),
  Functions.makeHttpRequest({
    url: `https://api.ownfinance.org/api/isMarketOpen`,
  }),
]);

if (!priceRes || priceRes.status !== 200)
  throw new Error("Failed to fetch price data");
if (!marketRes || marketRes.status !== 200)
  throw new Error("Failed to fetch market status");

const quote = priceRes.data.chart.result[0].indicators.quote[0];
const timestamp = marketRes.data.timestamp;

const toWei = (v) => BigInt(Math.round(v * 1e18));
const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
  ["uint256", "uint256", "uint256", "uint256", "uint256"],
  [
    toWei(quote.open[0]),
    toWei(quote.high[0]),
    toWei(quote.low[0]),
    toWei(quote.close[0]),
    BigInt(timestamp),
  ],
);
return ethers.getBytes(encoded);
