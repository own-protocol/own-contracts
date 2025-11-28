# Own Protocol Documentation

## Asset Pool Factory (Base Sepolia)

| Contract         | Address                                      |
| ---------------- | -------------------------------------------- |
| AssetPoolFactory | `0xC0166Fd0F9269B7031477C8098E27E8dDb761D54` |

## Implementation Contract Addresses (Base Sepolia)

| Contract             | Address                                      |
| -------------------- | -------------------------------------------- |
| AssetPool            | `0x65939A7A7E78AbAb3A78fbE37728dD66849caB0c` |
| PoolCylceManager     | `0x6594E0B1Bc8E0aE386aCf63d00a0928e64DCa8AB` |
| PoolLiquidityManager | `0xcF65F5889C5F2727d0Efa08EE8A1B816a781E940` |
| ProtocolRegistry     | `0xdE65370F905999eaEC9a3612874752C301324cF7` |

## Strategy Contract Addresses (Base Sepolia)

| Contract   | Address                                      |
| ---------- | -------------------------------------------- |
| Strategy A | `0xF5F2bf441B0EE021FA5fd5803ba143Fdd32f88Cc` |
| Strategy B | `0xba0efA3aDA11aF3B1837A0A6f086Cc9cAaADa5E2` |

Strategy A - To be used for high volatility assets. It has higher lp collateral requirements.  
Strategy B - To be used for low volatility assets. It has lower lp collateral requirements.

## Test Pool & Oracle Contract Addresses (Base Sepolia)

| TSLA   | Address                                      |
| ------ | -------------------------------------------- |
| Pool   | `0xE1661B11F3D46bdD3661DB16e592454aE31dafEa` |
| Oracle | `0x9A5D90Ed944d9413E7BcBF813a59821df68b0a4e` |

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

### Add Collateral

```bash
forge script script/AddCollateralScript.s.sol:AddCollateralScript \
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
