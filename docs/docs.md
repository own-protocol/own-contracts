BASE Sepolia testnet
Functions router: 0xf9B8fc078197181C841c296C876945aaa425B278
DON ID: 0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000 / fun-base-sepolia-1
Subscription ID: 254

AssetOracle Base Sepolia Contract Address: 0xF3b76d16a999478c05eA6367245f9BDd90d816D4

Deploy:
forge script script/DeployOracle.s.sol:DeployScript --rpc-url https://sepolia.base.org --broadcast --verify

Fetch Asset Price:
forge script script/RequestAssetPrice.s.sol:RequestAssetPrice --rpc-url https://sepolia.base.org --broadcast
