const { Defender } = require("@openzeppelin/defender-sdk");
const { ethers } = require("ethers");

// Constants
const ORACLE_CONTRACT_ADDRESS = "0x02c436fdb529AeadaC0D4a74a34f6c51BFC142F0";
const SUBSCRIPTION_ID = 254;
const GAS_LIMIT = 300_000;
const DON_ID =
  "0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000";
const SOURCE =
  'const yahooFinanceUrl = `https://query1.finance.yahoo.com/v8/finance/chart/TSLA?interval=1h`; const response = await Functions.makeHttpRequest({ url: yahooFinanceUrl }); if (!response || response.status !== 200) throw new Error("Failed to fetch asset data"); const data = response.data.chart.result[0]; const currentPrice = data.meta.regularMarketPrice; return Functions.encodeUint256(Math.round(currentPrice * 1e18));';

// ABI of the AssetOracle contract
const ASSET_ORACLE_ABI = [
  {
    inputs: [
      { internalType: "address", name: "router", type: "address" },
      { internalType: "string", name: "_assetSymbol", type: "string" },
      { internalType: "bytes32", name: "_sourceHash", type: "bytes32" },
    ],
    stateMutability: "nonpayable",
    type: "constructor",
  },
  { inputs: [], name: "EmptySource", type: "error" },
  { inputs: [], name: "InvalidSource", type: "error" },
  { inputs: [], name: "NoInlineSecrets", type: "error" },
  { inputs: [], name: "OnlyRouterCanFulfill", type: "error" },
  {
    inputs: [{ internalType: "bytes32", name: "requestId", type: "bytes32" }],
    name: "UnexpectedRequestID",
    type: "error",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: false,
        internalType: "uint256",
        name: "price",
        type: "uint256",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "timestamp",
        type: "uint256",
      },
    ],
    name: "AssetPriceUpdated",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: false,
        internalType: "string",
        name: "newAssetSymbol",
        type: "string",
      },
    ],
    name: "AssetSymbolUpdated",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, internalType: "address", name: "from", type: "address" },
      { indexed: true, internalType: "address", name: "to", type: "address" },
    ],
    name: "OwnershipTransferRequested",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, internalType: "address", name: "from", type: "address" },
      { indexed: true, internalType: "address", name: "to", type: "address" },
    ],
    name: "OwnershipTransferred",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, internalType: "bytes32", name: "id", type: "bytes32" },
    ],
    name: "RequestFulfilled",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, internalType: "bytes32", name: "id", type: "bytes32" },
    ],
    name: "RequestSent",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: false,
        internalType: "bytes32",
        name: "newSourceHash",
        type: "bytes32",
      },
    ],
    name: "SourceHashUpdated",
    type: "event",
  },
  {
    inputs: [],
    name: "acceptOwnership",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "assetPrice",
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
  {
    inputs: [
      { internalType: "bytes32", name: "requestId", type: "bytes32" },
      { internalType: "bytes", name: "response", type: "bytes" },
      { internalType: "bytes", name: "err", type: "bytes" },
    ],
    name: "handleOracleFulfillment",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "lastError",
    outputs: [{ internalType: "bytes", name: "", type: "bytes" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "lastResponse",
    outputs: [{ internalType: "bytes", name: "", type: "bytes" }],
    stateMutability: "view",
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
    name: "owner",
    outputs: [{ internalType: "address", name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
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
    name: "s_lastRequestId",
    outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "sourceHash",
    outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ internalType: "address", name: "to", type: "address" }],
    name: "transferOwnership",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { internalType: "string", name: "newAssetSymbol", type: "string" },
    ],
    name: "updateAssetSymbol",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { internalType: "bytes32", name: "newSourceHash", type: "bytes32" },
    ],
    name: "updateSourceHash",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
];

exports.handler = async function (event) {
  const credentials = {
    relayerApiKey: event.secrets.RELAYER_API_KEY,
    relayerApiSecret: event.secrets.RELAYER_API_SECRET,
  };

  const client = new Defender(credentials);
  const provider = client.relaySigner.getProvider();
  const signer = await client.relaySigner.getSigner(provider);

  // Connect to the deployed AssetOracle contract
  const oracle = new ethers.Contract(
    ORACLE_CONTRACT_ADDRESS,
    ASSET_ORACLE_ABI,
    signer
  );

  try {
    console.log("Sending transaction to request asset price...");
    const tx = await oracle.requestAssetPrice(
      SOURCE,
      SUBSCRIPTION_ID,
      GAS_LIMIT,
      DON_ID
    );
    console.log("Transaction sent:", tx.hash);

    // Wait for confirmation
    const receipt = await tx.wait();
    console.log("Transaction confirmed:", receipt.transactionHash);
  } catch (error) {
    console.error("Error:", error);
    throw error;
  }
};
