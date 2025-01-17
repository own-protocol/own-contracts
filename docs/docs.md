BASE Sepolia testnet
Functions router: 0xf9B8fc078197181C841c296C876945aaa425B278
DON ID: 0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000 / fun-base-sepolia-1
Subscription ID: 254

##Contract Addresses:
#Base Sepolia:
AssetOracle: 0x453cD289694c036980226FDEDF3A7a3eC686Ae05
LPRegistry: 0x82d533e4a2973D5c1E29eB207af0B6f387E395C9
AssetPoolFactory: 0xda62cb7c018505042eF56B02A8207A9a704e734c

AssetPool: 0x5C387fA6c1304f82AB6c1d01A6325DfF2aB1B5b6
xToken: 0xe54c25e05f8B4Fd8CbebF7127876b4c4Af2cc968

##Commands:
Deploy Oracle:
forge script script/DeployOracle.s.sol:DeployScript --rpc-url base_sepolia --broadcast --verify

Fetch Asset Price:
forge script script/RequestAssetPrice.s.sol:RequestAssetPrice --rpc-url base_sepolia --broadcast

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
forge verify-check $GUID --chain-id $CHAIN_ID // to check verification status
