# 🧮 DeltaVault

**DeltaVault** is a delta-neutral automated DeFi vault that combines **ETH lending**, **perpetual shorting**, and **staking rewards** to generate yield while maintaining market neutrality.  

---

## 🚀 Overview

When users deposit **USDC**, the vault:
1. Converts **50%** to **ETH** → supplies it to a lending protocol (earning interest).
2. Uses the other **50%** to open a **short position** on a perpetual DEX.
3. Balances both sides so ETH price movements are hedged (delta-neutral).

Users receive **DELTA vault shares (ERC20)** representing ownership in the strategy.

---

## ⚙️ Core Functionalities

### 🏦 Deposit & Withdraw
- **`deposit(usdcAmount)`**  
  - User deposits USDC.  
  - Vault splits funds 50/50 between ETH lending and perps short.  
  - Mints DELTA shares 1:1 to user.

- **`withdraw(shares)`**  
  - Burns user’s DELTA shares.  
  - Closes equivalent short + withdraws ETH from lending.  
  - Converts everything back to USDC and transfers to user.

---

### 🌾 Yield Harvesting
- **`harvestLending()`**  
  - Claims interest earned from lending.  
  - Converts ETH yield → USDC.  
  - Distributes part to stakers, rest stays in vault.

- **`harvestFunding()`**  
  - Realizes profits from short funding.  
  - Temporarily closes & reopens short.  
  - Distributes USDC rewards to stakers and vault.

---

### 🪙 Staking & Rewards
- **`stake(shares)`** — Stake DELTA shares to earn a cut of profits.  
- **`unstake(shares)`** — Withdraw your staked shares.  
- **`claimRewards()`** — Claim accrued USDC rewards.  
- Rewards are updated proportionally via `accRewardsPerStakedShare`.

---

### 📊 Vault Accounting
- **`totalAssetsUSDC()`**  
  - Returns total vault value in USDC terms:  
    - On-chain USDC + converted ETH balance + PnL from short position.

---

### 🔐 Admin & Safety
- **`pause()` / `unpause()`** — Emergency stop for deposits/withdrawals.  
- **`setFeeToStakersBps(bps)`** — Adjust staker reward share (max 100%).  
- Built-in protections:  
  - `ReentrancyGuard`  
  - `Ownable`  
  - `Pausable`  

---

## 🧩 Key Components

| Module | Purpose |
|---------|----------|
| **ILending** | Handles ETH deposits and interest accrual. |
| **IPerpetuals** | Manages short positions for delta hedging. |
| **IDex** | Swaps between ETH and USDC. |

---

## 🧾 Summary

| Role | Interaction |
|------|--------------|
| **Depositors** | Earn yield through automated delta-neutral strategy. |
| **Stakers** | Receive a share of harvested profits in USDC. |
| **Owner** | Can pause the vault or adjust reward fee. |

---

## ⚖️ License
**MIT License**  
SPDX-License-Identifier: MIT
