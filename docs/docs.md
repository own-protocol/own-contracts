BASE Sepolia testnet
Functions router: 0xf9B8fc078197181C841c296C876945aaa425B278
DON ID: 0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000 / fun-base-sepolia-1
Subscription ID: 254

##Contract Addresses:
#Base Sepolia:
AssetOracle: 0x453cD289694c036980226FDEDF3A7a3eC686Ae05
AssetPoolImplementation: 0x6D2a971099314b2dB9a78138ac1b3Bd52AfB597e
LPRegistry: 0xfA6bD97e1662Df409d15EEaa5654BDA6b319D721
AssetPoolFactory: 0xC75324D1949E004963Bb158c1Bc9A702b591a21A

AssetPool: 0xcA18c8a2f554c57950C8944228F4db262Ea24D5a
xToken: 0x463011e877e7C2cd95E2a61b444752f62981E071
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
