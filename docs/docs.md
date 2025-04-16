# Own Protocol Documentation

## Asset Pool Factory (Base Sepolia)

| Contract         | Address                                      |
| ---------------- | -------------------------------------------- |
| AssetPoolFactory | `0xF225f028F7cd2CbEF1C882224e4ae97AbBd352Dc` |

## Implementation Contract Addresses (Base Sepolia)

| Contract             | Address                                      |
| -------------------- | -------------------------------------------- |
| AssetPool            | `0x3A91E1E6Fd53Bf1efF573dBd551DA930f4937ea3` |
| PoolCylceManager     | `0xda22816E7FeAD4a4639cC892d7Dfa0d1eCDB362C` |
| PoolLiquidityManager | `0x3C6F5423287FCf768E2393735778a65f94d521e7` |
| ProtocolRegistry     | `0xCEaBF7ed92bCA91920316f015C92F61a4F8bE761` |

## Strategy Contract Addresses (Base Sepolia)

| Contract   | Address                                      |
| ---------- | -------------------------------------------- |
| Strategy A | `0xE94a39c718fF6Ffa91E91eFc486B6a031338a31F` |
| Strategy B | `0x17976DC403bd39DeF23485D86604d1fFf3A9D0F3` |

Strategy A - To be used for low volatility assets. It has lower lp collateral requirements.  
Strategy B - To be used for high volatility assets. It has higher lp collateral requirements.

## Test Pool & Oracl Contract Addresses (Base Sepolia)

| AAPL   | Address                                      |
| ------ | -------------------------------------------- |
| Pool   | `0xf2266E76547460be653a58F8929932921AE877b9` |
| Oracle | `0x634344E170C47B71c2254be91094A01Ee8B98667` |

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
