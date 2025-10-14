# 💱 Dex.sol

A minimal on-chain DEX that enables **ETH ↔ USDC ↔ WETH** swaps using **Chainlink price feeds** for real-time conversion rates.  
Used by vaults like **DeltaVault** for accurate, slippage-free token conversions.

---

## ⚙️ Core Functionalities

### 🧮 Price Feed
- **`getLatestPrice()`**  
  Fetches the latest **ETH/USD** price from Chainlink’s AggregatorV3 feed.  
  - Ensures valid (>0) price data.  
  - Used for all swap conversions.

---

### 💱 Swap
- **`swap(address tokenIn, address tokenOut, uint256 amountIn)`**  
  Converts tokens between **ETH**, **WETH**, and **USDC** using live Chainlink prices.  
  Supports:
  - **ETH → USDC** (native ETH sent with `msg.value`)  
  - **WETH → USDC**  
  - **USDC → ETH**  
  - **USDC → WETH**  

  Automatically handles decimal adjustments:  
  - ETH/WETH: 18 decimals  
  - USDC: 6 decimals  
  - Feed: typically 8 decimals  

  Emits `Swap(user, tokenIn, tokenOut, amountIn, amountOut)` event.

---

### 💰 Liquidity Management
- **`depositToken(address token, uint256 amount)`** — Add WETH/USDC liquidity.  
- **`depositEth()`** — Add native ETH liquidity.  
- **`withdraw(address token, uint256 amount)`** — Withdraw ETH or ERC20 tokens from the DEX.

---

### 🔐 Security
- Validates supported token pairs only (ETH/WETH/USDC).  
- Reverts on same-token swaps or invalid inputs.  
- Uses **Chainlink’s decentralized oracle** for accurate pricing.

---

## 🧾 Summary

| Function | Purpose |
|-----------|----------|
| `getLatestPrice()` | Get live ETH/USD price. |
| `swap()` | Convert between ETH, WETH, and USDC. |
| `depositToken()` / `depositEth()` | Provide liquidity. |
| `withdraw()` | Remove liquidity. |

---

**License:** MIT  
**SPDX-License-Identifier:** MIT
