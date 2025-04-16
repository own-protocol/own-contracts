# Own Protocol

Own is a permissionless protocol for fully collateralized asset swaps, enabling synthetic exposure to any real-world asset onchain.

The protocol creates a market where users can gain exposure to asset performance by paying a floating interest rate, while liquidity providers earn this interest in exchange for offering asset exposure. As the default market makers in the protocol, LPs can also earn from market making.

## How It Works

- **Users** deposit reserve tokens (like USDC) to gain synthetic exposure to real-world assets (stocks, index etc) by paying a floating interest rate
- **Liquidity Providers (LPs)** supply liquidity to earn interest payments and from market making
- **xTokens** represent synthetic exposure to the underlying real-world assets
- The protocol manages collateral requirements, rebalancing, and interest rate adjustments through automated cycles

## Contract Architecture

### Core Components

- **AssetPool**: Manages user positions, deposits, redemptions, and user collateral requirements
- **xToken**: ERC20-compliant token representing synthetic exposure to the underlying asset
- **PoolCycleManager**: Handles the lifecycle of operational cycles, including rebalancing periods
- **PoolLiquidityManager**: Manages LP liquidity & collateral requirements and ensures system solvency
- **PoolStrategy**: Defines economic parameters including interest rates, collateral ratios, and fees

### Oracle & Price Feed

- **AssetOracle**: Provides price data for the underlying assets using Chainlink Functions
- Handles price deviation detection for corporate actions like stock splits

### Factory & Registry

- **AssetPoolFactory**: Creates new asset pools for different real-world assets
- **ProtocolRegistry**: Tracks verified protocol contracts for security and discoverability

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

## Security Model

- Multi-layered collateralization requirements for both users and LPs
- Cycle-based rebalancing to prevent market manipulation from being overly reliant on oracle prices
- Automated interest rate adjustments based on pool utilization
- Permissionless design allows for community-driven governance and upgrades
- Comprehensive testing of all contracts
- Clear separation between offchain and onchain rebalancing phases
- Oracle price validation and anomaly detection

**Checkout docs for more details**
