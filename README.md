Deployment

Arbitrum Sepolia
```
USDC:        0x1d566cf9c688eb6737b10a0632fdce3c18688525
Lending:     0xd12be2ce2b8e34d8461b85feebf1192852b0c41b
Dex:         0x3054ac26615964e4475de6ea42686e7141c766a7
Perpetuals:  0xcdc276f9cedfa020fefe43ab1830f5a899715d81
DeltaVault:  0x27a7caba2587ee6b8c115fb88b0f241c54095eb9
```

Test Transaction
https://sepolia.arbiscan.io/tx/0xbaeef05771d20df53c9582f67568c58f57c74b5c59759a80a6a5c14d5ad76043
```shell

# For testing approve and send 1000 usdc to delta contract
cast send 0x1d566cf9c688eb6737b10a0632fdce3c18688525 \
    "approve(address,uint256)" \
    0x27a7caba2587ee6b8c115fb88b0f241c54095eb9 \
    999999999999999999 \
    --rpc-url arbitrum_sepolia \
    --private-key $PRIVATE_KEY

cast send 0x27a7caba2587ee6b8c115fb88b0f241c54095eb9 \
    "deposit(uint256)" \
    1000000000 \
    --rpc-url arbitrum_sepolia \
    --private-key $PRIVATE_KEY

cast send 0x27a7caba2587ee6b8c115fb88b0f241c54095eb9 \
    "stake(uint256)" \
    1000000000 \
    --rpc-url arbitrum_sepolia \
    --private-key $PRIVATE_KEY

cast send 0x27a7caba2587ee6b8c115fb88b0f241c54095eb9 \
    "unstake(uint256)" \
    1000000000 \
    --rpc-url arbitrum_sepolia \
    --private-key $PRIVATE_KEY

cast send 0x27a7caba2587ee6b8c115fb88b0f241c54095eb9 \
    "claimRewards()" \
    --rpc-url arbitrum_sepolia \
    --private-key $PRIVATE_KEY
```
