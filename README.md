Deployment

Arbitrum Sepolia
FAKE USDC: 0xb77ff7864657a548e24242f198394fa7c5214ad9
Simulated Perps: 0xecbdc282820f1fc720adb21ae648e61593412f68
Simulated Lending: 0x47439425B447f27F2D1d4d855266B9A4a2aD0fc2

```shell
forge script script/DeployUSDC.s.sol --rpc-url wss://arbitrum-sepolia-rpc.publicnode.com --broadcast --account defaultKey --sender 0x272B97E93b3AccA272fB9ac7B9043d1Ba6472FC4 --etherscan-api-key $ETHERSCAN_KEY --verify
forge script script/DeployPerps.s.sol --tc DeployPerpetuals --rpc-url wss://arbitrum-sepolia-rpc.publicnode.com --broadcast --account defaultKey --sender 0x272B97E93b3AccA272fB9ac7B9043d1Ba6472FC4 --etherscan-api-key $ETHERSCAN_KEY --verify
forge script script/DeployLending.s.sol --rpc-url wss://arbitrum-sepolia-rpc.publicnode.com --broadcast --account defaultKey --sender 0x272B97E93b3AccA272fB9
ac7B9043d1Ba6472FC4 --etherscan-api-key $ETHERSCAN_KEY --verify
```
