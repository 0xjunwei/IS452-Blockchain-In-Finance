# 📉 Perpetuals.sol

A minimal **on-chain perpetual short trading contract** that allows users to open, reduce, and close **short positions on ETH** using **USDC** as collateral.  
It uses **Chainlink price feeds** to calculate real-time profit and loss (PnL).

---

## ⚙️ Core Functionalities

### 💱 short(uint256 amount)
Opens or increases a short position using USDC.  
- Transfers `amount` USDC from the user.  
- Records **entry price** from Chainlink.  
- If user already has a short, updates the **weighted average entry price**.  
- Increases `openInterest` and `totalShortPosition`.

---

### 🔻 reduceShort(uint256 reduceAmount)
Reduces part of an existing short position.  
- Calculates profit or loss based on **entry price vs current price**.  
- Returns USDC payout accordingly:
  - Profit → `amount + PnL`
  - Loss → `amount - loss`
- Updates position size; closes if fully reduced.

---

### 🔒 closeShort()
Closes the user’s entire short position.  
- Calculates final PnL.  
- Transfers resulting USDC payout.  
- Resets position data and updates open interest.

---

### 💰 ownerWithdraw(uint256 amount)
Owner-only function to withdraw USDC from the contract.

---

## 📊 View Functions

### `getLatestPrice()`
- Fetches the latest **ETH/USD** price from Chainlink oracle.  
- Returns value with 8 decimals (standard Chainlink feed).

---

## 🧩 Key Variables

| Variable | Description |
|-----------|--------------|
| `positions[user]` | Tracks each user’s short position (size, entry price, isOpen). |
| `openInterest` | Total active short position size in USDC. |
| `totalShortPosition` | Cumulative amount shorted. |
| `fundingRate` | Placeholder for future funding mechanism. |
| `usdcToken` | Address of the USDC token used for margin. |
| `priceFeed` | Chainlink ETH/USD feed address. |

---

## 🔐 Security
- Uses Chainlink oracle for reliable price data.  
- Prevents invalid operations (zero amounts, no open position).  
- Only owner can withdraw protocol-held USDC.

---

## 🧾 Summary

| Function | Purpose |
|-----------|----------|
| `short(amount)` | Open or increase a short position. |
| `reduceShort(amount)` | Reduce or partially close a short position. |
| `closeShort()` | Fully close a short position. |
| `getLatestPrice()` | Get real-time ETH/USD price. |
| `ownerWithdraw(amount)` | Owner-only withdrawal of USDC. |

---

**License:** MIT  
**SPDX-License-Identifier:** MIT
