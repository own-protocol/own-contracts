const { Defender } = require("@openzeppelin/defender-sdk");
const { ethers } = require("ethers");

// Configuration
const CONFIG = {
  SUBSCRIPTION_ID: 254,
  GAS_LIMIT: 300_000,
  DON_ID: "0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000",
  MAX_RETRIES: 3,
  RETRY_DELAY_MS: 5 * 60 * 1000, // 5 minutes
  REQUEST_COOLDOWN_SECONDS: 300, // 5 minutes between requests
};

// Asset configurations - Add new assets here
const ASSETS = [
  {
    symbol: "TSLA",
    oracleAddress: "0x845d51C05c482198A7C543D3BFaB95846E3E0a50",
    source:
      'const ethers = await import("npm:ethers@6.10.0"); const yahooFinanceUrl = `https://query1.finance.yahoo.com/v8/finance/chart/TSLA?interval=1d`; const response = await Functions.makeHttpRequest({ url: yahooFinanceUrl }); if (!response || response.status !== 200) throw new Error("Failed to fetch asset data"); const data = response.data.chart.result[0]; const timestamp = data.timestamp[0]; const indicators = data.indicators; const quote = indicators.quote[0]; const open = quote.open[0]; const high = quote.high[0]; const low = quote.low[0]; const close = quote.close[0]; const toWei = (value) => BigInt(Math.round(value * 1e18)); const encoded = ethers.AbiCoder.defaultAbiCoder().encode(["uint256", "uint256", "uint256", "uint256", "uint256"], [toWei(open), toWei(high), toWei(low), toWei(close), BigInt(timestamp)]); return ethers.getBytes(encoded);',
  },
  {
    symbol: "NVDA",
    oracleAddress: "0x8f7f124e1101c52c1c6885f4a9377da93b2ba804",
    source:
      'const ethers = await import("npm:ethers@6.10.0"); const yahooFinanceUrl = `https://query1.finance.yahoo.com/v8/finance/chart/NVDA?interval=1d`; const response = await Functions.makeHttpRequest({ url: yahooFinanceUrl }); if (!response || response.status !== 200) throw new Error("Failed to fetch asset data"); const data = response.data.chart.result[0]; const timestamp = data.timestamp[0]; const indicators = data.indicators; const quote = indicators.quote[0]; const open = quote.open[0]; const high = quote.high[0]; const low = quote.low[0]; const close = quote.close[0]; const toWei = (value) => BigInt(Math.round(value * 1e18)); const encoded = ethers.AbiCoder.defaultAbiCoder().encode(["uint256", "uint256", "uint256", "uint256", "uint256"], [toWei(open), toWei(high), toWei(low), toWei(close), BigInt(timestamp)]); return ethers.getBytes(encoded);',
  },
  {
    symbol: "AAPL",
    oracleAddress: "0x9eb68720f0ee2539a85999065672054ad3f08fe2",
    source:
      'const ethers = await import("npm:ethers@6.10.0"); const yahooFinanceUrl = `https://query1.finance.yahoo.com/v8/finance/chart/AAPL?interval=1d`; const response = await Functions.makeHttpRequest({ url: yahooFinanceUrl }); if (!response || response.status !== 200) throw new Error("Failed to fetch asset data"); const data = response.data.chart.result[0]; const timestamp = data.timestamp[0]; const indicators = data.indicators; const quote = indicators.quote[0]; const open = quote.open[0]; const high = quote.high[0]; const low = quote.low[0]; const close = quote.close[0]; const toWei = (value) => BigInt(Math.round(value * 1e18)); const encoded = ethers.AbiCoder.defaultAbiCoder().encode(["uint256", "uint256", "uint256", "uint256", "uint256"], [toWei(open), toWei(high), toWei(low), toWei(close), BigInt(timestamp)]); return ethers.getBytes(encoded);',
  },
  // Add more assets here as needed:
  // {
  //   symbol: "AAPL",
  //   oracleAddress: "0x...",
  //   source: '...' // AAPL-specific source code
  // }
];

// AssetOracle ABI (minimal required functions)
const ASSET_ORACLE_ABI = [
  {
    inputs: [
      { internalType: "string", name: "source", type: "string" },
      { internalType: "uint64", name: "subscriptionId", type: "uint64" },
      { internalType: "uint32", name: "gasLimit", type: "uint32" },
      { internalType: "bytes32", name: "donID", type: "bytes32" },
    ],
    name: "requestAssetPrice",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "lastUpdated",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "assetSymbol",
    outputs: [{ internalType: "string", name: "", type: "string" }],
    stateMutability: "view",
    type: "function",
  },
];

class OracleUpdateManager {
  constructor(client, provider, signer) {
    this.client = client;
    this.provider = provider;
    this.signer = signer;
    this.updateAttempts = new Map(); // Track retry attempts per asset
  }

  async updateAllOracles() {
    console.log(`Starting oracle updates for ${ASSETS.length} assets...`);

    const results = {
      successful: [],
      failed: [],
      skipped: [],
    };

    for (const asset of ASSETS) {
      try {
        const result = await this.updateAssetOracle(asset);
        if (result.success) {
          results.successful.push({
            symbol: asset.symbol,
            txHash: result.txHash,
          });
        } else if (result.skipped) {
          results.skipped.push({ symbol: asset.symbol, reason: result.reason });
        } else {
          results.failed.push({ symbol: asset.symbol, error: result.error });
        }
      } catch (error) {
        console.error(`Unexpected error updating ${asset.symbol}:`, error);
        results.failed.push({ symbol: asset.symbol, error: error.message });
      }
    }

    this.logResults(results);
    return results;
  }

  async updateAssetOracle(asset) {
    const oracle = new ethers.Contract(
      asset.oracleAddress,
      ASSET_ORACLE_ABI,
      this.signer
    );

    try {
      // Check if update is needed
      const shouldUpdate = await this.shouldUpdateOracle(oracle, asset.symbol);
      if (!shouldUpdate.update) {
        return {
          success: false,
          skipped: true,
          reason: shouldUpdate.reason,
        };
      }

      // Attempt update with retry logic
      const result = await this.attemptUpdateWithRetry(oracle, asset);

      if (result.success) {
        // Reset retry counter on success
        this.updateAttempts.delete(asset.symbol);
      }

      return result;
    } catch (error) {
      console.error(`Error updating oracle for ${asset.symbol}:`, error);
      return {
        success: false,
        skipped: false,
        error: error.message,
      };
    }
  }

  async shouldUpdateOracle(oracle, symbol) {
    try {
      const lastUpdated = await oracle.lastUpdated();
      const currentTime = Math.floor(Date.now() / 1000);
      const timeSinceUpdate = currentTime - Number(lastUpdated);

      // Skip if updated recently (within cooldown period)
      if (timeSinceUpdate < CONFIG.REQUEST_COOLDOWN_SECONDS) {
        return {
          update: false,
          reason: `Recently updated ${timeSinceUpdate}s ago (cooldown: ${CONFIG.REQUEST_COOLDOWN_SECONDS}s)`,
        };
      }

      return { update: true };
    } catch (error) {
      console.error(`Error checking update status for ${symbol}:`, error);
      return { update: true }; // Attempt update if we can't check status
    }
  }

  async attemptUpdateWithRetry(oracle, asset) {
    const currentAttempts = this.updateAttempts.get(asset.symbol) || 0;

    try {
      console.log(
        `Updating ${asset.symbol} oracle (attempt ${currentAttempts + 1}/${
          CONFIG.MAX_RETRIES + 1
        })...`
      );

      const tx = await oracle.requestAssetPrice(
        asset.source,
        CONFIG.SUBSCRIPTION_ID,
        CONFIG.GAS_LIMIT,
        CONFIG.DON_ID
      );

      console.log(`Transaction sent for ${asset.symbol}:`, tx.hash);

      const receipt = await tx.wait();
      console.log(
        `Transaction confirmed for ${asset.symbol}:`,
        receipt.transactionHash
      );

      return {
        success: true,
        txHash: receipt.transactionHash,
      };
    } catch (error) {
      console.error(
        `Update attempt failed for ${asset.symbol}:`,
        error.message
      );

      // Increment retry counter
      const newAttempts = currentAttempts + 1;
      this.updateAttempts.set(asset.symbol, newAttempts);

      // Check if we should retry
      if (newAttempts < CONFIG.MAX_RETRIES) {
        console.log(
          `Scheduling retry for ${asset.symbol} in ${
            CONFIG.RETRY_DELAY_MS / 1000
          } seconds...`
        );

        // Schedule retry (in a real environment, this would be handled by Defender's scheduling)
        setTimeout(async () => {
          const retryResult = await this.attemptUpdateWithRetry(oracle, asset);
          if (retryResult.success) {
            console.log(`Retry successful for ${asset.symbol}`);
          }
        }, CONFIG.RETRY_DELAY_MS);

        return {
          success: false,
          skipped: false,
          error: `Failed, retry scheduled (attempt ${newAttempts}/${CONFIG.MAX_RETRIES})`,
        };
      } else {
        // Max retries reached
        this.updateAttempts.delete(asset.symbol);
        return {
          success: false,
          skipped: false,
          error: `Max retries (${CONFIG.MAX_RETRIES}) reached: ${error.message}`,
        };
      }
    }
  }

  logResults(results) {
    console.log("\n=== Oracle Update Results ===");
    console.log(`Successful: ${results.successful.length}`);
    console.log(`Failed: ${results.failed.length}`);
    console.log(`Skipped: ${results.skipped.length}`);

    if (results.successful.length > 0) {
      console.log("\nSuccessful updates:");
      results.successful.forEach((r) =>
        console.log(`  ✅ ${r.symbol}: ${r.txHash}`)
      );
    }

    if (results.failed.length > 0) {
      console.log("\nFailed updates:");
      results.failed.forEach((r) =>
        console.log(`  ❌ ${r.symbol}: ${r.error}`)
      );
    }

    if (results.skipped.length > 0) {
      console.log("\nSkipped updates:");
      results.skipped.forEach((r) =>
        console.log(`  ⏭️ ${r.symbol}: ${r.reason}`)
      );
    }
  }
}

// Time validation helper
function isValidUpdateTime() {
  const now = new Date();
  const etTime = new Date(
    now.toLocaleString("en-US", { timeZone: "America/New_York" })
  );
  const hours = etTime.getHours();
  const minutes = etTime.getMinutes();

  // Market open: 9:35 AM ET (allow 9:30-9:40 window)
  const isMarketOpen = hours === 9 && minutes >= 30 && minutes <= 40;

  // Market close: 4:05 PM ET (allow 4:00-4:10 window)
  const isMarketClose = hours === 16 && minutes >= 0 && minutes <= 10;

  return isMarketOpen || isMarketClose;
}

// Main handler function
exports.handler = async function (event) {
  console.log("Oracle update task started...");
  console.log("Event:", JSON.stringify(event, null, 2));

  // Validate update time (optional - remove if you want manual triggers)
  // if (!isValidUpdateTime()) {
  //  console.log("Not a valid update time. Updates are scheduled for 9:35 AM and 4:05 PM ET.");
  //  return { status: "skipped", reason: "Invalid update time" };
  // }

  try {
    // Initialize Defender client
    const credentials = {
      relayerApiKey: event.secrets.RELAYER_API_KEY,
      relayerApiSecret: event.secrets.RELAYER_API_SECRET,
    };

    const client = new Defender(credentials);
    const provider = client.relaySigner.getProvider();
    const signer = await client.relaySigner.getSigner(provider);

    // Create update manager and run updates
    const updateManager = new OracleUpdateManager(client, provider, signer);
    const results = await updateManager.updateAllOracles();

    // Return results for monitoring
    return {
      status: "completed",
      timestamp: new Date().toISOString(),
      results: results,
    };
  } catch (error) {
    console.error("Critical error in oracle update handler:", error);
    throw error;
  }
};
