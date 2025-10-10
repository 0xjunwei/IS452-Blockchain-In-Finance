// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

// All my interfaces between the different smart contracts
interface ILending {
    function deposit() external payable;
    function withdraw(uint256 _amount) external;
    function getAccruedBalance(address _user) external view returns (uint256);
    function deposits(address) external view returns (uint256 amount, uint256 lastUpdate);
}

interface IPerpetuals {
    function short(uint256 _amount) external;
    function reduceShort(uint256 _reduceAmount) external;
    function getLatestPrice() external view returns (uint256);
    function positions(address user) external view returns (uint256 size, uint256 entryPrice, bool isOpen);
}

interface IDex {
    function swap(address tokenIn, address tokenOut, uint256 amountIn) external payable;
    function getLatestPrice() external view returns (uint256);
    function usdc() external view returns (address);
}

// Main to parse ERC20, ownable and re-entrancy guard
contract DeltaVault is ERC20, ERC20Permit, Ownable, Pausable, ReentrancyGuard {
    // Core integrations
    IERC20 public immutable usdc; // 6 decimals
    ILending public immutable lending;
    IPerpetuals public immutable perps;
    IDex public immutable dex;

    // Staking of vault shares to earn a portion of harvested USDC fees
    uint256 public totalStakedShares;
    mapping(address => uint256) public stakedShares;
    uint256 public accRewardsPerStakedShare; // scaled by 1e18
    mapping(address => uint256) public rewardDebt; // staker's accRewardsPerStakedShare snapshot

    // Configuration
    uint256 public feeToStakersBps; // portion of harvested USDC sent to stakers (in bps)
    // Max bps is 10000, 10000 = 100.00% look at the number of 0 ~ will be equal to the MAX_BPS
    uint256 public constant MAX_BPS = 10000;

    // Events
    event Deposit(address indexed user, uint256 usdcIn, uint256 sharesMinted);
    event Withdraw(address indexed user, uint256 sharesBurned, uint256 usdcOut);
    event HarvestLending(uint256 ethHarvested, uint256 usdcHarvested, uint256 toStakers, uint256 toVault);
    event HarvestFunding(uint256 reduceAmountUSDC, uint256 usdcRealized, uint256 toStakers, uint256 toVault);
    event Stake(address indexed user, uint256 shares);
    event Unstake(address indexed user, uint256 shares);
    event ClaimRewards(address indexed user, uint256 usdcAmount);

    constructor(
        address _usdc,
        address _lending,
        address _perps,
        address _dex,
        uint256 _feeToStakersBps,
        address _owner
    ) ERC20("Delta Neutral Vault", "DELTA") ERC20Permit("Delta Neutral Vault") Ownable(_owner) {
        require(_usdc != address(0) && _lending != address(0) && _perps != address(0) && _dex != address(0), "bad addr");
        require(_feeToStakersBps <= MAX_BPS, "fee too high");
        usdc = IERC20(_usdc);
        lending = ILending(_lending);
        perps = IPerpetuals(_perps);
        dex = IDex(_dex);
        feeToStakersBps = _feeToStakersBps;
    }
    
    function decimals() public pure override returns (uint8) { return 6; }

    // Admin functions
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
    function setFeeToStakersBps(uint256 bps) external onlyOwner { require(bps <= MAX_BPS, "fee too high"); feeToStakersBps = bps; }
    // Main one to call for demo, deposit the usdc the smart contract should route
    // Main concern is gas, the amount of calls might be high in gas
    function deposit(uint256 usdcAmount) external nonReentrant whenNotPaused {
        require(usdcAmount > 0, "amount=0");

        // Pull USDC from user
        require(usdc.transferFrom(msg.sender, address(this), usdcAmount), "transferFrom failed");

        // Strategy: 50% buy ETH and lend, 50% open short
        uint256 toEth = usdcAmount / 2;
        uint256 toShort = usdcAmount - toEth;

        // Approve and swap USDC->ETH on Dex; measure received ETH by balance delta
        // Lend the eth
        if (toEth > 0) {
            _approveIfNeeded(usdc, address(dex), toEth);
            uint256 ethBefore = address(this).balance;
            dex.swap(address(usdc), address(0), toEth);
            uint256 ethReceived = address(this).balance - ethBefore;
            if (ethReceived > 0) {
                // Deposit ETH into Lending
                lending.deposit{value: ethReceived}();
            }
        }
        // Short the same amount of ETH in USDC on perps
        if (toShort > 0) {
            _approveIfNeeded(usdc, address(perps), toShort);
            perps.short(toShort);
        }
        _mint(msg.sender, usdcAmount);
        emit Deposit(msg.sender, usdcAmount, usdcAmount);
    }

    function withdraw(uint256 shares) external nonReentrant whenNotPaused {
        require(shares > 0, "amount=0");
        require(balanceOf(msg.sender) >= shares, "insufficient shares");

        _burn(msg.sender, shares);

        uint256 half = shares / 2;
        uint256 otherHalf = shares - half;

        (uint256 size,, bool isOpen) = perps.positions(address(this));
        if (isOpen && size > 0) {
            uint256 reduceAmt = half > size ? size : half;
            if (reduceAmt > 0) {
                perps.reduceShort(reduceAmt);
            }
        }

        uint256 price = dex.getLatestPrice();
        uint8 feedDecimals = 8;
        uint256 ethNeeded = (otherHalf * 1e12) * (10 ** feedDecimals) / price;
        uint256 ethAccrued = lending.getAccruedBalance(address(this));
        if (ethNeeded > ethAccrued) ethNeeded = ethAccrued;
        if (ethNeeded > 0) {
            lending.withdraw(ethNeeded);
            dex.swap(address(0), address(usdc), ethNeeded);
        }

        require(usdc.balanceOf(address(this)) >= shares, "insufficient USDC");
        require(usdc.transfer(msg.sender, shares), "USDC xfer failed");
        emit Withdraw(msg.sender, shares, shares);
    }

    // ------------ Harvesting ------------

    function harvestLending() external nonReentrant whenNotPaused {
        // Withdraw only interest from lending, keep principal
        (uint256 principal,) = lending.deposits(address(this));
        uint256 accrued = lending.getAccruedBalance(address(this));
        if (accrued <= principal) return; // no interest
        uint256 interestEth = accrued - principal;

        lending.withdraw(interestEth);

        // Swap harvested ETH interest to USDC
        uint256 usdcBefore = usdc.balanceOf(address(this));
        dex.swap(address(0), address(usdc), interestEth);
        uint256 harvestedUSDC = usdc.balanceOf(address(this)) - usdcBefore;
        if (harvestedUSDC == 0) return;

        // Split to stakers and vault
        uint256 toStakers = (harvestedUSDC * feeToStakersBps) / MAX_BPS;
        uint256 toVault = harvestedUSDC - toStakers;
        if (toStakers > 0) {
            _distributeToStakers(toStakers);
        }
        // toVault stays as USDC in the contract, increasing NAV
        emit HarvestLending(interestEth, harvestedUSDC, toStakers, toVault);
    }

    // Realize perps funding/PnL by reducing then reopening the short with same notional
    function harvestFunding(uint256 reduceAmountUSDC) external nonReentrant whenNotPaused {
        (uint256 size,, bool isOpen) = perps.positions(address(this));
        require(isOpen && size > 0, "no short");
        if (reduceAmountUSDC > size) reduceAmountUSDC = size;

        uint256 usdcBefore = usdc.balanceOf(address(this));
        perps.reduceShort(reduceAmountUSDC);
        uint256 realized = usdc.balanceOf(address(this)) - usdcBefore;

        if (reduceAmountUSDC > 0) {
            _approveIfNeeded(usdc, address(perps), reduceAmountUSDC);
            perps.short(reduceAmountUSDC);
        }

        if (realized > 0) {
            uint256 toStakers = (realized * feeToStakersBps) / MAX_BPS;
            uint256 toVault = realized - toStakers;
            if (toStakers > 0) {
                _distributeToStakers(toStakers);
            }
            // toVault remains as USDC to boost NAV
            emit HarvestFunding(reduceAmountUSDC, realized, toStakers, toVault);
        }
    }

    // Staking Functions

    function stake(uint256 shares) external nonReentrant whenNotPaused {
        require(shares > 0, "shares must be more than0");
        _updateUserRewards(msg.sender);
        totalStakedShares += shares;
        stakedShares[msg.sender] += shares;
        // Calculate a debt to prevent double-counting, if another user staked for a year, and i just added in, i should not able to claim their portion
        // Using masterchef staking contract style, this would set accRewardsPerStaked but would incur debt for new entrants
        // Thus all is fair
        // User A stake 100 usdc for a year at 100% APR
        // User B enters at 100 USDC at T0 + 365 days, he needs to incur 100 usdc debt from staking to prevent disproportionate claim rights
        rewardDebt[msg.sender] = (stakedShares[msg.sender] * accRewardsPerStakedShare) / 1e18;
        _transfer(msg.sender, address(this), shares);
        emit Stake(msg.sender, shares);
    }

    function unstake(uint256 shares) external nonReentrant whenNotPaused {
        require(shares > 0 && stakedShares[msg.sender] >= shares, "bad shares");
        // Handles pending claims before unstaking, to readjust all numbers
        _updateUserRewards(msg.sender);
        totalStakedShares -= shares;
        stakedShares[msg.sender] -= shares;
        rewardDebt[msg.sender] = (stakedShares[msg.sender] * accRewardsPerStakedShare) / 1e18;
        _transfer(address(this), msg.sender, shares);
        emit Unstake(msg.sender, shares);
    }

    function claimRewards() external nonReentrant whenNotPaused {
        uint256 pending = pendingRewards(msg.sender);
        if (pending > 0) {
            rewardDebt[msg.sender] = (stakedShares[msg.sender] * accRewardsPerStakedShare) / 1e18;
            require(usdc.transfer(msg.sender, pending), "reward xfer failed");
            emit ClaimRewards(msg.sender, pending);
        }
    }

    function pendingRewards(address user) public view returns (uint256) {
        uint256 accumulated = (stakedShares[user] * accRewardsPerStakedShare) / 1e18;
        uint256 debt = rewardDebt[user];
        return accumulated > debt ? accumulated - debt : 0;
    }

    // ------------ Views ------------

    function totalAssetsUSDC() public view returns (uint256) {
        uint256 total;

        // On-hand USDC
        total += usdc.balanceOf(address(this));

        // ETH held in contract (unlikely) and ETH in Lending -> convert to USDC
        uint256 ethHeld = address(this).balance;
        uint256 ethLending = lending.getAccruedBalance(address(this));
        uint256 ethTotal = ethHeld + ethLending;
        if (ethTotal > 0) {
            uint256 price = dex.getLatestPrice(); // 1eFeed
            // ETH(1e18) * price(1eFeed) / 10^feed -> 1e18; then /1e12 to 1e6 USDC
            uint8 feedDecimals = 8; // Dex normalizes via Chainlink, but expose decimals? assume 8 common
            uint256 usdcFromEth = (ethTotal * price) / (10 ** feedDecimals);
            usdcFromEth = usdcFromEth / 1e12;
            total += usdcFromEth;
        }

        // Perps position valued at close-out value (size +/- pnl)
        (uint256 size, uint256 entryPrice, bool isOpen) = perps.positions(address(this));
        if (isOpen && size > 0) {
            uint256 current = perps.getLatestPrice();
            // emulate reduceShort math to compute pnl6
            uint256 entry18 = entryPrice * 1e10;
            uint256 current18 = current * 1e10;
            uint256 size18 = size * 1e12; // size is 6 decimals
            int256 pnl18 = int256(size18) * (int256(entry18) - int256(current18)) / int256(entry18);
            int256 pnl6 = pnl18 / 1e12;
            if (pnl6 >= 0) {
                total += size + uint256(pnl6);
            } else {
                uint256 loss = uint256(-pnl6);
                total += size > loss ? size - loss : 0;
            }
        }

        return total;
    }

    function _previewSharesMint(uint256 totalBefore, uint256 totalAfter, uint256 depositAmountUSDC) internal view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0 || totalBefore == 0) {
            return depositAmountUSDC;
        }
        uint256 gain = totalAfter - totalBefore; // includes deposit impact; safe in 0.8 if totalAfter>=totalBefore
        // Use depositAmount as contribution to NAV for share calc
        uint256 contribution = depositAmountUSDC + (gain > depositAmountUSDC ? 0 : 0); // keep simple
        return (contribution * supply) / totalBefore;
    }

    // ------------ Internal helpers ------------

    function _approveIfNeeded(IERC20 token, address spender, uint256 amount) internal {
        if (token.allowance(address(this), spender) < amount) {
            token.approve(spender, type(uint256).max);
        }
    }

    function _distributeToStakers(uint256 usdcAmount) internal {
        if (totalStakedShares == 0 || usdcAmount == 0) return;
        accRewardsPerStakedShare += (usdcAmount * 1e18) / totalStakedShares;
    }

    function _updateUserRewards(address user) internal {
        uint256 pending = pendingRewards(user);
        if (pending > 0) {
            // Update debt before paying to prevent double-counting
            rewardDebt[user] = (stakedShares[user] * accRewardsPerStakedShare) / 1e18;
            // pay from vault USDC balance
            require(usdc.transfer(user, pending), "reward xfer failed");
            emit ClaimRewards(user, pending);
        }
    }

    receive() external payable {}
}
