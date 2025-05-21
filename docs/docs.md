# Own Protocol Documentation

## Asset Pool Factory (Base Sepolia)

| Contract         | Address                                      |
| ---------------- | -------------------------------------------- |
| AssetPoolFactory | `0x6eA99f37b4c3ad5B3353cF7CBf7db916fd78ee63` |

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
| Strategy A | `0x7dFC74B1dAfd918D66B35E5237C7A5b170710386` |
| Strategy B | `0x627d18FAe968Ad8d73CE9f54680B2e6F3b15700e` |

Strategy A - To be used for low volatility assets. It has lower lp collateral requirements.  
Strategy B - To be used for high volatility assets. It has higher lp collateral requirements.

## Asset Pool Factory (Sepolia)

| Contract         | Address                                      |
| ---------------- | -------------------------------------------- |
| AssetPoolFactory | `0xFA41F88b5e350C3E4e0f29dB5FDE02d866E8902c` |

## Implementation Contract Addresses (Sepolia)

| Contract             | Address                                      |
| -------------------- | -------------------------------------------- |
| AssetPool            | `0x02c436fdb529AeadaC0D4a74a34f6c51BFC142F0` |
| PoolCylceManager     | `0x105B599CDbC0B6EFa4C04C8dbbc4313894487713` |
| PoolLiquidityManager | `0x66B2079cfdB9f387Bc08E36ca25097ADeD661e2b` |
| ProtocolRegistry     | `0x0AE43Ac4d1B35da83D46dC5f78b22501f83E846c` |

## Strategy Contract Addresses (Sepolia)

| Contract   | Address                                      |
| ---------- | -------------------------------------------- |
| Strategy A | `0x38b04F6a1cCdd02c0105BE3Aa64f6b7Fa4A104b3` |

## Test Pool & Oracle Contract Addresses (Base Sepolia)

| AAPL   | Address                                      |
| ------ | -------------------------------------------- |
| Pool   | `0xf2266E76547460be653a58F8929932921AE877b9` |
| Oracle | `0x634344E170C47B71c2254be91094A01Ee8B98667` |

## Test Reserve Token Contract Addresses (Base Sepolia)

| Token | Address                                      |
| ----- | -------------------------------------------- |
| USDC  | `0x2cDAEADd29E6Ba0C3AF2551296D9729fB3c7eD99` |
| USDT  | `0x7763CeA1702d831c29656b0400a31471e9dDd55d` |

### Chainlink Oracle Details

- **Functions Router:** `0xf9B8fc078197181C841c296C876945aaa425B278`
- **DON ID:** `0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000`
  - Human-readable: `fun-base-sepolia-1`
- **Subscription ID:** `254`

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
