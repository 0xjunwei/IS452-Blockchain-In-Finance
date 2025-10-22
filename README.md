Deployment

Arbitrum Sepolia
```
USDC:        0x879ab869f254d5f64086bee62aa4f8adbe380ac0
Lending:     0x8babdda69f401795c79dcdccfa200d4c9c7d9777
Dex:         0x1fa269df4ca7b9aee8742d89dafbc977fa66622d
Perpetuals:  0x4919c7458ecac4187e57efafb407f1538b73e75f
Delta Vault: 0x6f4338a8bb8bdaddef7d5cb606fc7510a5452863
```

Test Transaction
https://sepolia.arbiscan.io/tx/0xbaeef05771d20df53c9582f67568c58f57c74b5c59759a80a6a5c14d5ad76043
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
