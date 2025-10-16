# Own Protocol Documentation

## Asset Pool Factory (Base Sepolia)

| Contract         | Address                                      |
| ---------------- | -------------------------------------------- |
| AssetPoolFactory | `0x59409659e34158244AF69c3E3aE15Ded8bA941A4` |

## Implementation Contract Addresses (Base Sepolia)

| Contract             | Address                                      |
| -------------------- | -------------------------------------------- |
| AssetPool            | `0x63a0Bc7cf9603f5D3bcAE4C35500526a72A790AE` |
| PoolCylceManager     | `0x3B10A2343fFC0C452AeE1580fBcFB27cA05572f1` |
| PoolLiquidityManager | `0xACdf42f5A525EF0a0E3D749d6000471cf1100a81` |
| ProtocolRegistry     | `0x811Ad5f758DB53d8dD3B18890a0cfe5a389e3C72` |

## Strategy Contract Addresses (Base Sepolia)

| Contract   | Address                                      |
| ---------- | -------------------------------------------- |
| Strategy A | `0x1D89e11a80d08323B86377f56Ff2de9B07cf6045` |
| Strategy B | `0xD0aD5937B8365C90404145FFEc361b2C817B0c52` |

Strategy A - To be used for low volatility assets. It has lower lp collateral requirements.  
Strategy B - To be used for high volatility assets. It has higher lp collateral requirements.

## Test Pool & Oracle Contract Addresses (Base Sepolia)

| TSLA   | Address                                      |
| ------ | -------------------------------------------- |
| Pool   | `0x9c66076401E5008E4BE2FAB3d013e5A257AAc102` |
| Oracle | `0xF2fF3c044fEEDA0FE91A65ba3f056d7D81E6c6dc` |

## Test Reserve Token Contract Addresses (Base Sepolia)

| Token | Address                                      |
| ----- | -------------------------------------------- |
| USDC  | `0x7bD1331A7c4E32F3aD9Ca14Ad0E7FAb0d4F380Ec` |
| USDT  | `0x82eECDd667D68961045B18B38501ef391ff71b25` |

### Chainlink Oracle Details (Base Sepolia)

- **Functions Router:** `0xf9B8fc078197181C841c296C876945aaa425B278`
- **DON ID:** `0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000`
  - Human-readable: `fun-base-sepolia-1`
- **Subscription ID:** `254`

### Chainlink Oracle Details (Sepolia)

- **Functions Router:** `0xb83E47C2bC239B3bf370bc41e1459A34b41238D0`
- **DON ID:** `0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000`
  - Human-readable: `fun-ethereum-sepolia-1`
- **Subscription ID:** `4808`

## Deployment Commands

### Deploy Implementations

```bash
forge script script/DeployPoolImplementations.s.sol:DeployPoolImplementations \
    --rpc-url base_sepolia --etherscan-api-key base_sepolia --broadcast --verify
```

### Deploy Protocol Registry

```bash
forge script script/DeployProtocolRegistry.s.sol:DeployProtocolRegistryScript \
    --rpc-url base_sepolia --etherscan-api-key base_sepolia --broadcast --verify
```

### Deploy Pool Strategy

```bash
forge script script/DeployPoolStrategy.s.sol:DeployPoolStrategyScript \
    --rpc-url base_sepolia --etherscan-api-key base_sepolia --broadcast --verify
```

### Deploy Pool Factory

```bash
forge script script/DeployPoolFactory.s.sol:AssetPoolFactoryDeployScript \
    --rpc-url base_sepolia --etherscan-api-key base_sepolia --broadcast --verify
```

### Create Oracle

```bash
forge script script/CreateAssetOracle.s.sol:CreateAssetOracleScript \
    --rpc-url base_sepolia --broadcast
```

### Verify Contracts on Registry

```bash
forge script script/VerifyContractsOnRegistry.s.sol:VerifyContractsOnStrategyScript \
    --rpc-url base_sepolia --broadcast
```

### Fetch Asset Price

```bash
forge script script/RequestAssetPrice.s.sol:RequestAssetPrice \
    --rpc-url base_sepolia --broadcast
```

### Create New Pool

```bash
forge script script/CreateAssetPool.s.sol:CreatePoolScript \
    --rpc-url base_sepolia --broadcast
```

### Verify Pool

```bash
forge verify-contract $POOL_ADDRESS AssetPool \
    --constructor-args $(cast abi-encode "constructor(address,string,string,address,address,uint256,uint256,address)" \
    $DEPOSIT_TOKEN "$ASSET_TOKEN_NAME" "$ASSET_TOKEN_SYMBOL" $ORACLE_ADDRESS $LP_REGISTRY $CYCLE_PERIOD $REBALANCE_PERIOD $OWNER) \
    --chain base-sepolia \
    --etherscan-api-key $ETHERSCAN_API_KEY
```

### Verify xToken

```bash
forge verify-contract $TOKEN_ADDRESS xToken \
    --constructor-args $(cast abi-encode "constructor(string,string)" "$ASSET_TOKEN_NAME" "$ASSET_TOKEN_SYMBOL") \
    --chain base-sepolia
```

### Update Oracle SourceHash

```bash
forge script script/UpdateOracleSourceHash.s.sol:UpdateOracleSourceHashScript \
    --rpc-url base_sepolia --broadcast
```

## Utility Commands

### Forge Commands

```bash
# Clean build artifacts
forge clean

# Build contracts
forge build

# Build with sizes
forge build --sizes

# Run a specific test file
forge test --match-path test/MyContract.t.sol

# Run a specific test in a test file
forge test --match-path test/MyContract.t.sol --match-test testMyFunction

# Run all tests with gas report
forge test --gas-report

# Check contract verification status
forge verify-check $GUID --chain-id $CHAIN_ID

# Run specific test
forge test --match-contract ContractName --match-test testName
```
