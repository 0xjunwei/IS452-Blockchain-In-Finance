Deployment

Arbitrum Sepolia
```
USDC:        0x61d2e62b99905738f301b37b37e5f2bd54779c72
Lending:     0x083634a3548436c128853d875e276c9648f5b7b1
Dex:         0x7989e0614175b7f3ae304cd6450afd8e484eabf0
Perpetuals:  0xfb70296f034ce4bb44abd4d20e78dbf85cdebf5d
Delta Vault: 0xb67aacd7ff69916123254e4aa1cca0cf167c8ea7
```

Adjust / or \ according to windows or macos


Deploy code:
```
forge script .\script\DeployAll.s.sol:DeployAll --rpc-url $RPC_URL --verify --broadcast -vvvv

If verification fail
forge flatten .\src\USDC.sol > USDC_flattened.sol
forge flatten .\src\Lending.sol > Lending_flattened.sol
forge flatten .\src\Dex.sol > Dex_flattened.sol
forge flatten .\src\Perpetuals.sol > Perpetuals_flattened.sol
forge flatten .\src\Delta.sol > DeltaVault_flattened.sol
```
[Test Transaction](https://sepolia.arbiscan.io/tx/0x8a3844d565416fd730a1c837b430639593bcf4f2d93b5f847141e3c62ba41b05)
```shell

# For testing approve and send 1000 usdc to delta contract
# 1. Approve USDC
cast send $USDC "approve(address,uint256)" $DELTA_VAULT $AMOUNT --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# 2. Deposit
cast send $DELTA_VAULT "deposit(uint256)" $AMOUNT --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# 3. Stake
cast send $DELTA_VAULT "stake(uint256)" $AMOUNT --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# 4. Harvest Lending
cast send $DELTA_VAULT "harvestLending()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# 5. Harvest Funding
cast send $DELTA_VAULT "harvestFunding()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# 6. Check Rewards
cast call $DELTA_VAULT "pendingRewards(address)(uint256)" $YOUR_ADDRESS --rpc-url $RPC_URL

cast send $DELTA_VAULT "claimRewards()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# 7. Unstake
cast send $DELTA_VAULT "unstake(uint256)" $AMOUNT --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# 8. Withdraw
cast send $DELTA_VAULT "withdraw(uint256)" $AMOUNT --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```
