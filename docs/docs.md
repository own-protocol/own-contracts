BASE Sepolia testnet
Functions router: 0xf9B8fc078197181C841c296C876945aaa425B278
DON ID: 0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000 / fun-base-sepolia-1
Subscription ID: 254

##Contract Addresses:
#Base Sepolia:
AssetOracle: 0x02c436fdb529AeadaC0D4a74a34f6c51BFC142F0
AssetPoolImplementation: 0x105B599CDbC0B6EFa4C04C8dbbc4313894487713
LPRegistry: 0x66B2079cfdB9f387Bc08E36ca25097ADeD661e2b
AssetPoolFactory: 0x0AE43Ac4d1B35da83D46dC5f78b22501f83E846c

AssetPool: 0xf6AF07a6d2Fd6551c2eb0f2DA7644F4d5dd0FB65
xToken: 0xF2809722104D4a0D5E300546dF2489832512fFa4
USDC: 0x036CbD53842c5426634e7929541eC2318f3dCF7e

##Commands:
Deploy Oracle:
forge script script/DeployOracle.s.sol:DeployScript --rpc-url base_sepolia --broadcast --verify

Fetch Asset Price:
forge script script/RequestAssetPrice.s.sol:RequestAssetPrice --rpc-url base_sepolia --broadcast

Deploy AssetPool Implementation:
forge script script/DeployAssetPoolImplementation.s.sol:AssetPoolImplementationDeployScript --rpc-url base_sepolia --broadcast --verify

Deploy LP Registry:
forge script script/DeployLPRegistry.s.sol:LPRegistryDeployScript --rpc-url base_sepolia --broadcast --verify

Deploy Pool Factory:
forge script script/DeployPoolFactory.s.sol:AssetPoolDeployScript --rpc-url base_sepolia --broadcast --verify

Create New Pool:
forge script script/CreateAssetPool.s.sol:CreatePoolScript --rpc-url base_sepolia --broadcast

Verify Pool:
forge verify-contract $POOL_ADDRESS AssetPool \
  --constructor-args $(cast abi-encode "constructor(address,string,string,address,address,uint256,uint256,address)" \
  $DEPOSIT_TOKEN "$ASSET_TOKEN_NAME" "$ASSET_TOKEN_SYMBOL" $ORACLE_ADDRESS $LP_REGISTRY $CYCLE_PERIOD $REBALANCE_PERIOD $OWNER) \
 --chain base-sepolia \
 --etherscan-api-key $ETHERSCAN_API_KEY

Verify xToken:
forge verify-contract $TOKEN_ADDRESS xToken \
  --constructor-args $(cast abi-encode "constructor(string,string)" "$ASSET_TOKEN_NAME" "$ASSET_TOKEN_SYMBOL") \
 --chain base-sepolia

Update Oracle SourceHash:
forge script script/UpdateOracleSourceHash.s.sol:UpdateOracleSourceHashScript --rpc-url base_sepolia --broadcast

Forge Commands:
forge clean
forge build
forge verify-check $GUID --chain-id $CHAIN_ID // to check contract verification status
