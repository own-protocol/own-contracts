# Own Protocol

## Overview

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

### Key Features

- Fully collateralized system with no liquidation risk for users or LPs (when properly collateralized)
- Floating interest rate model based on pool utilization
- Cyclical rebalancing to ensure proper asset exposure
- Support for corporate actions like stock splits

## Security Model

- Multi-layered collateralization requirements for both users and LPs
- Cycle-based rebalancing to prevent market manipulation from being overly reliant on oracle prices
- Automated interest rate adjustments based on pool utilization
- Permissionless design allows for community-driven governance and upgrades
- Comprehensive testing of all contracts
- Clear separation between offchain and onchain rebalancing phases
- Oracle price validation and anomaly detection

### Check docs for deployment instructions and contract addresses
