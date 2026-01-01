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

## Asset Pool Factory (Base)

| Contract         | Address                                      |
| ---------------- | -------------------------------------------- |
| AssetPoolFactory | `0xC8e4cc79da89FCFaF4436f5e9F9fFCE0D2850378` |

## Implementation Contract Addresses (Base)

| Contract             | Address                                      |
| -------------------- | -------------------------------------------- |
| AssetPool            | `0x1d227F102B56d91f201EC7715aB96088a34e76a6` |
| PoolCylceManager     | `0x6068042feb82Ee17Cf1A7de908E44CBB9d506cBe` |
| PoolLiquidityManager | `0x16AF157937E70Eb432d6a403ADAEb3b5b1FE9C2C` |
| ProtocolRegistry     | `0xBB9f34413f48aE7520acdedC4f07b110860c1534` |

## Strategy Contract Addresses (Base)

| Contract   | Address                                      |
| ---------- | -------------------------------------------- |
| Strategy A | `0x82eECDd667D68961045B18B38501ef391ff71b25` |

Strategy A - To be used for low volatility assets. It has lower lp collateral requirements.

## Main Pool Contract Addresses (Base)

| AI7          | Address                                      |
| ------------ | -------------------------------------------- |
| Pool         | `0xCa5b851B28d756EB21DEDceA9BAcea6e18DD5ECF` |
| CycleManager | `0x0e3eE1270aC831c32875426365505A3f91E40742` |
| LiqManager   | `0x6C0297c6007dB1E1eC88df92D2302374BcB72ec0` |
| Oracle       | `0x52BdAa287CF02cf9b4c700439e11146D7c23D311` |
| Asset        | `0x2567563f230A3A30A5ba9de84157E0449c00EB36` |
| Reserve      | `0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB` |

## Deploy & Create Commands

### Create New Oracle

```bash
forge script script/CreateAssetOracle.s.sol:CreateAssetOracleScript \
    --rpc-url base --broadcast --verify
```

### Create New Pool

```bash
forge script script/CreateAssetPool.s.sol:CreatePoolScript \
    --rpc-url base --broadcast
```

**Checkout [docs](https://own-protocol.gitbook.io/docs) for more details**
