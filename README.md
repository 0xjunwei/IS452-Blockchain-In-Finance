Deployment

Arbitrum Sepolia
```
USDC:        0x7A8507e60eAc46C592cb505A35DEA374dC06BFA8
Lending:     0xC62F73A09047FEd6F2fCADCDE0FA89c1F6b53AF7
Dex:         0x706882dE9AdF2ae2F03001690675BAb1a04e2035
Perpetuals:  0x51f4f05329e629132e03b81F532690c8f0859eFF
Delta Vault: 0xFD8601FAaA0edc762F012a86e80A7901a9Aa66b2
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
