BASE Sepolia testnet
Functions router: 0xf9B8fc078197181C841c296C876945aaa425B278
DON ID: 0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000 / fun-base-sepolia-1
Subscription ID: 254

AssetOracle Base Sepolia Contract Address: 0x453cD289694c036980226FDEDF3A7a3eC686Ae05

Deploy:
forge script script/DeployOracle.s.sol:DeployScript --rpc-url base_sepolia --broadcast --verify

Fetch Asset Price:
forge script script/RequestAssetPrice.s.sol:RequestAssetPrice --rpc-url base_sepolia --broadcast
