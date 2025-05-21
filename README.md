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

## Test Pool & Oracle Contract Addresses (Base Sepolia)

| TSLA   | Address                                      |
| ------ | -------------------------------------------- |
| Pool   | `0x688878805152CE79CD930071cD32481B11A5b95B` |
| Oracle | `0x845d51C05c482198A7C543D3BFaB95846E3E0a50` |

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
