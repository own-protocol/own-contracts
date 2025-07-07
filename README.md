# Own Protocol

Own is a permissionless protocol for fully collateralized Total Return Swaps (Equity Swap), enabling synthetic exposure to stocks onchain. Think of Maker DAO or Uniswap but for creating synthetic stocks permissionlessly & traded as native ERC20 tokens.

The protocol creates a market where users gain exposure to stock performance by paying a floating interest rate, while liquidity providers earn this interest in exchange for offering that exposure. As default market makers, LPs can also earn from trading activity. Since the protocol is fully collateralized, LPs take no directional risk, enabling delta-neutral strategies.

## Contract Architecture

### Core Components

- **AssetPool**: Manages user positions, deposits, redemptions, and user collateral requirements
- **PoolCycleManager**: Handles pool rebalancing and interest rate calculations.
- **PoolLiquidityManager**: Manages LP positions, LP collateral & liquidations and ensures system solvency
- **xToken**: ERC20-compliant token representing synthetic exposure to the underlying asset
- **PoolStrategy**: Defines economic parameters including interest rates, collateral ratios, and fees

### Oracle & Price Feed

- **AssetOracle**: Provides price data for the underlying assets using Chainlink Functions

### Factory & Registry

- **AssetPoolFactory**: Creates new asset pools for different real-world assets
- **ProtocolRegistry**: Tracks verified protocol contracts for security and discoverability

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

## Deploy & Create Commands

### Create New Oracle

```bash
forge script script/CreateAssetOracle.s.sol:CreateAssetOracleScript \
    --rpc-url base_sepolia --broadcast --verify
```

### Create New Pool

```bash
forge script script/CreateAssetPool.s.sol:CreatePoolScript \
    --rpc-url base_sepolia --broadcast
```

**Checkout [docs](https://own-protocol.gitbook.io/docs) for more details**
