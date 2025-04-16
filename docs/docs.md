# Own Protocol Documentation

## Asset Pool Factory (Base Sepolia)

| Contract         | Address                                      |
| ---------------- | -------------------------------------------- |
| AssetPoolFactory | `0x0AE43Ac4d1B35da83D46dC5f78b22501f83E846c` |

## Implementation Contract Addresses (Base Sepolia)

| Contract             | Address                                      |
| -------------------- | -------------------------------------------- |
| AssetPool            | ``                                           |
| PoolCylceManager     | `0x0f1A428320e1cd5E2ED40f1d1ACf91E337E96015` |
| PoolLiquidityManager | `0xF73dB7066C192A84e55ea92D7fC161757f36345f` |
| ProtocolRegistry     | ``                                           |

## Strategy Contract Addresses (Base Sepolia)

| Contract   | Address                                      |
| ---------- | -------------------------------------------- |
| Strategy A | `0x105B599CDbC0B6EFa4C04C8dbbc4313894487713` |

### Chainlink Oracle Details

- **Functions Router:** `0xf9B8fc078197181C841c296C876945aaa425B278`
- **DON ID:** `0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000`
  - Human-readable: `fun-base-sepolia-1`
- **Subscription ID:** `254`

## Deployment Commands

### Deploy AssetPool Implementation

```bash
forge script script/DeployPoolImplementations.s.sol:DeployPoolImplementations \
    --rpc-url base_sepolia --broadcast --verify
```

### Deploy Protocol Registry

```bash
forge script script/DeployProtocolRegistry.s.sol:DeployProtocolRegistryScript \
    --rpc-url base_sepolia --broadcast --verify
```

### Deploy Pool Strategy

```bash
forge script script/DeployPoolStrategy.s.sol:DeployPoolStrategyScript \
    --rpc-url base_sepolia --broadcast --verify
```

### Deploy Pool Factory

```bash
forge script script/DeployPoolFactory.s.sol:AssetPoolDeployScript \
    --rpc-url base_sepolia --broadcast --verify
```

### Create Oracle

```bash
forge script script/CreateAssetOracle.s.sol:CreateAssetOracleScript \
    --rpc-url base_sepolia --broadcast --verify
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
```
