# 🏦 Lending.sol

A lightweight **ETH lending contract** that allows users to deposit ETH and earn a fixed **2% APR** yield over time.  
Interest is calculated linearly based on how long funds remain deposited.

---

## ⚙️ Core Functionalities

### 💰 deposit()
Users deposit ETH to start earning yield.  
- Accrues pending interest before adding new funds.  
- Updates user balance and timestamp.  
- Increases total deposits.

### 💸 withdraw(uint256 amount)
Withdraw ETH plus accrued interest.  
- Calculates and adds pending yield before withdrawal.  
- Ensures requested amount ≤ current balance.  
- Sends ETH to the user.

### 📊 getAccruedBalance(address user)
View function returning total ETH balance including earned interest.  
Uses simple interest formula:
