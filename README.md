Deployment

Arbitrum Sepolia
```
USDC:        0x1d566cf9c688eb6737b10a0632fdce3c18688525
Lending:     0xd12be2ce2b8e34d8461b85feebf1192852b0c41b
Dex:         0x3054ac26615964e4475de6ea42686e7141c766a7
Perpetuals:  0xcdc276f9cedfa020fefe43ab1830f5a899715d81
DeltaVault:  0x27a7caba2587ee6b8c115fb88b0f241c54095eb9
```
```shell
forge script script/DeployUSDC.s.sol --rpc-url wss://arbitrum-sepolia-rpc.publicnode.com --broadcast --account defaultKey --sender 0x272B97E93b3AccA272fB9ac7B9043d1Ba6472FC4 --etherscan-api-key $ETHERSCAN_KEY --verify
forge script script/DeployPerps.s.sol --tc DeployPerpetuals --rpc-url wss://arbitrum-sepolia-rpc.publicnode.com --broadcast --account defaultKey --sender 0x272B97E93b3AccA272fB9ac7B9043d1Ba6472FC4 --etherscan-api-key $ETHERSCAN_KEY --verify
forge script script/DeployLending.s.sol --rpc-url wss://arbitrum-sepolia-rpc.publicnode.com --broadcast --account defaultKey --sender 0x272B97E93b3AccA272fB9
ac7B9043d1Ba6472FC4 --etherscan-api-key $ETHERSCAN_KEY --verify
```
