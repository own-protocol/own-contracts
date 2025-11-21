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
