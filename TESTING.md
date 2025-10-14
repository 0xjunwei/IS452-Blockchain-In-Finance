# Testing and Deployment Guide

## Overview
This project contains comprehensive deployment scripts and test suites for all blockchain contracts:
- USDC (Mock stablecoin)
- Lending (ETH lending with 2% APR)
- Perpetuals (ETH shorts with PnL tracking)
- Dex (DEX with Chainlink price feeds)
- Delta (Delta-neutral vault with staking)

## Prerequisites
- Foundry installed (`forge`, `cast`, `anvil`)
- Environment variables configured (optional, scripts use sensible defaults)

## Running Tests

### Run All Tests
```bash
forge test
```

### Run Specific Test File
```bash
# USDC tests
forge test --match-path test/USDC.t.sol -vvv

# Lending tests
forge test --match-path test/Lending.t.sol -vvv

# Dex tests
forge test --match-path test/Dex.t.sol -vvv

# Perpetuals tests
forge test --match-path test/Perpetuals.t.sol -vvv

# Delta Vault tests
forge test --match-path test/Delta.t.sol -vvv
```

### Run Specific Test Function
```bash
forge test --match-test test_Deposit -vvv
```

### Run Tests with Gas Report
```bash
forge test --gas-report
```

### Run Tests with Coverage
```bash
forge coverage
```

## Deployment Scripts

### Deploy USDC
```bash
# Local deployment
forge script script/DeployUSDC.s.sol:DeployUSDC --rpc-url http://localhost:8545 --broadcast

# Testnet deployment (e.g., Arbitrum Sepolia)
forge script script/DeployUSDC.s.sol:DeployUSDC --rpc-url $ARB_SEPOLIA_RPC --broadcast --verify
```

### Deploy Lending
```bash
forge script script/DeployLending.s.sol:DeployLending --rpc-url http://localhost:8545 --broadcast
```

### Deploy Perpetuals
```bash
# Set environment variables first
export USDC=0x... # USDC contract address
export PRICE_FEED=0x... # Optional, will deploy mock if not set

forge script script/DeployPerps.s.sol:DeployPerpetuals --rpc-url http://localhost:8545 --broadcast
```

### Deploy Dex
```bash
# Set environment variables
export USDC=0x... # Required
export WETH=0x... # Optional, will deploy mock
export PRICE_FEED=0x... # Optional, will deploy mock

forge script script/DeployDex.s.sol:DeployDex --rpc-url http://localhost:8545 --broadcast
```

### Deploy Delta Vault (Complete System)
```bash
# Deploy entire system (will deploy all dependencies if not provided)
export FEE_TO_STAKERS_BPS=2000 # 20% of harvested fees to stakers
export OWNER=0x... # Vault owner address

forge script script/DeployDelta.s.sol:DeployDelta --rpc-url http://localhost:8545 --broadcast

# Or deploy with existing contracts
export USDC=0x...
export LENDING=0x...
export PERPETUALS=0x...
export DEX=0x...
export PRICE_FEED=0x...
export WETH=0x...

forge script script/DeployDelta.s.sol:DeployDelta --rpc-url $ARB_SEPOLIA_RPC --broadcast --verify
```

## Test Coverage Summary

### USDC Tests (`test/USDC.t.sol`)
- ✅ Initial supply and minting
- ✅ Decimals (6)
- ✅ Transfer and transferFrom
- ✅ ERC20Permit functionality
- ✅ Failure cases (insufficient balance, allowance)

### Lending Tests (`test/Lending.t.sol`)
- ✅ ETH deposits and withdrawals
- ✅ Interest accrual (2% APR)
- ✅ Multiple deposits
- ✅ Partial withdrawals
- ✅ Compounding interest
- ✅ Owner withdrawal
- ✅ Failure cases (overdraw, zero deposits)

### Dex Tests (`test/Dex.t.sol`)
- ✅ Chainlink price feed integration
- ✅ ETH → USDC swaps
- ✅ USDC → ETH swaps
- ✅ WETH → USDC swaps
- ✅ USDC → WETH swaps
- ✅ Price updates
- ✅ Liquidity deposits
- ✅ Failure cases (same token swap, insufficient liquidity)

### Perpetuals Tests (`test/Perpetuals.t.sol`)
- ✅ Opening short positions
- ✅ Increasing position size (weighted average entry)
- ✅ Closing shorts with profit
- ✅ Closing shorts with loss
- ✅ Partial position reduction
- ✅ Multiple users
- ✅ Large position PnL
- ✅ Failure cases (zero amount, no position, overdraw)

### Delta Vault Tests (`test/Delta.t.sol`)
- ✅ Deposit (50/50 ETH lending + USDC short)
- ✅ Withdraw (maintains 50/50 split)
- ✅ Harvest lending interest
- ✅ Harvest perps funding/PnL
- ✅ Stake vault shares
- ✅ Unstake and claim rewards
- ✅ Reward distribution (proportional)
- ✅ Pause/unpause
- ✅ Fee configuration
- ✅ NAV calculation (totalAssetsUSDC)
- ✅ Failure cases (zero amounts, overdraw, unauthorized)

## Environment Variables

### Optional Configuration
```bash
# Contract addresses
export USDC=0x...
export LENDING=0x...
export PERPETUALS=0x...
export DEX=0x...
export WETH=0x...
export PRICE_FEED=0x...

# Delta Vault configuration
export FEE_TO_STAKERS_BPS=2000  # 20% default
export OWNER=0x...

# RPC endpoints
export ARB_SEPOLIA_RPC=https://sepolia-rollup.arbitrum.io/rpc
```

## Local Development

### Start Local Anvil Chain
```bash
anvil
```

### Deploy Entire System Locally
```bash
# Terminal 1: Start Anvil
anvil

# Terminal 2: Deploy
forge script script/DeployDelta.s.sol:DeployDelta --rpc-url http://localhost:8545 --broadcast
```

### Interactive Testing
```bash
# Start Anvil with fixed accounts
anvil --accounts 10 --balance 1000

# Use cast to interact
cast send $USDC "transfer(address,uint256)" $USER1 1000000000 --rpc-url http://localhost:8545 --private-key $PRIVATE_KEY
```

## Gas Optimization Tips
All contracts use:
- Solidity 0.8.30 (safe math built-in)
- ReentrancyGuard on critical functions
- View/pure where possible
- Efficient storage patterns

## Security Features
- ✅ Checks-effects-interactions pattern
- ✅ ReentrancyGuard on all state-changing functions
- ✅ Pausable vault operations
- ✅ Ownable admin functions
- ✅ Safe math (Solidity 0.8+)
- ✅ ERC20Permit for gasless approvals

## Notes
- All test contracts deploy mock price feeds with ETH = $3000
- USDC has 6 decimals (standard)
- Chainlink feeds return 8 decimals
- Delta vault shares are 1:1 with USDC (6 decimals)
- Lending APR is fixed at 2% (200 bps)
- Default staker fee is 80% (8000 bps) of harvested yield

