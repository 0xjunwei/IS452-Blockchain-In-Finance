// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

// Interfaces
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
    function positions(address user) external view returns (uint256 size, uint256 entryPrice, bool isOpen, int256 fundingIndex);
    function claimFunding() external returns (int256);
    function getPendingFunding(address user) external view returns (int256);
}

interface IDex {
    function swap(address tokenIn, address tokenOut, uint256 amountIn) external payable;
    function getLatestPrice() external view returns (uint256);
    function usdc() external view returns (address);
}

contract DeltaVault is ERC20, ERC20Permit, Ownable, Pausable, ReentrancyGuard {
    // Core integrations
    IERC20 public immutable usdc; // 6 decimals
    ILending public immutable lending;
    IPerpetuals public immutable perps;
    IDex public immutable dex;

    // Staking
    uint256 public totalStakedShares;
    mapping(address => uint256) public stakedShares;
    uint256 public accRewardsPerStakedShare; // scaled by 1e18
    mapping(address => uint256) public rewardDebt; 

    // Configuration
    uint256 public feeToStakersBps;
    uint256 public constant MAX_BPS = 10000;
    
    // Protocol fees (owner's 20% share)
    uint256 public accumulatedProtocolFees;

    // Events
    event Deposit(address indexed user, uint256 usdcIn, uint256 sharesMinted);
    event Withdraw(address indexed user, uint256 sharesBurned, uint256 usdcOut);
    event HarvestLending(uint256 ethHarvested, uint256 usdcHarvested, uint256 toStakers, uint256 toVault);
    event HarvestFunding(uint256 fundingClaimed, uint256 toStakers, uint256 toVault);
    event Stake(address indexed user, uint256 shares);
    event Unstake(address indexed user, uint256 shares);
    event ClaimRewards(address indexed user, uint256 usdcAmount);
    event OwnerWithdraw(address indexed owner, uint256 amount);

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
    
    function ownerWithdraw(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "amount=0");
        require(amount <= accumulatedProtocolFees, "exceeds protocol fees");
        require(usdc.balanceOf(address(this)) >= amount, "insufficient balance");
        
        accumulatedProtocolFees -= amount;
        require(usdc.transfer(msg.sender, amount), "transfer failed");
        emit OwnerWithdraw(msg.sender, amount);
    }
    
    function getAvailableProtocolFees() external view returns (uint256) {
        return accumulatedProtocolFees;
    }
    
    function getTotalUSDCBalance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }
    
    function deposit(uint256 usdcAmount) external nonReentrant whenNotPaused {
        require(usdcAmount > 0, "amount=0");

        require(usdc.transferFrom(msg.sender, address(this), usdcAmount), "transferFrom failed");

        uint256 toEth = usdcAmount / 2;
        uint256 toShort = usdcAmount - toEth;

        if (toEth > 0) {
            _approveIfNeeded(usdc, address(dex), toEth);
            uint256 ethBefore = address(this).balance;
            dex.swap(address(usdc), address(0), toEth);
            uint256 ethReceived = address(this).balance - ethBefore;
            if (ethReceived > 0) {
                lending.deposit{value: ethReceived}();
            }
        }
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

        // Calculate user's proportional share of vault value BEFORE burning
        uint256 totalShares = totalSupply();
        uint256 totalValue = totalAssetsUSDC();
        uint256 userValue = (totalValue * shares) / totalShares;
        
        // Calculate how much to withdraw from each position proportionally
        uint256 shareFraction = (shares * 1e18) / totalShares; // User's fraction scaled by 1e18

        _burn(msg.sender, shares);

        // Unwind short position proportionally
        (uint256 size,, bool isOpen,) = perps.positions(address(this));
        if (isOpen && size > 0) {
            uint256 reduceAmt = (size * shareFraction) / 1e18;
            if (reduceAmt > 0) {
                perps.reduceShort(reduceAmt);
            }
        }

        // Withdraw ETH proportionally and convert to USDC
        uint256 ethAccrued = lending.getAccruedBalance(address(this));
        if (ethAccrued > 0) {
            uint256 ethToWithdraw = (ethAccrued * shareFraction) / 1e18;
            if (ethToWithdraw > 0) {
                lending.withdraw(ethToWithdraw);
                dex.swap{value: ethToWithdraw}(address(0), address(usdc), ethToWithdraw);
            }
        }

        // Transfer USDC to user
        // Use minimum of userValue or actual balance to prevent reverts
        uint256 usdcBalance = usdc.balanceOf(address(this));
        uint256 usdcToUser = userValue > usdcBalance ? usdcBalance : userValue;
        
        require(usdc.transfer(msg.sender, usdcToUser), "USDC xfer failed");
        emit Withdraw(msg.sender, shares, usdcToUser);
    }

    function harvestLending() external nonReentrant whenNotPaused {
        (uint256 principal,) = lending.deposits(address(this));
        uint256 accrued = lending.getAccruedBalance(address(this));
        if (accrued <= principal) return;
        uint256 interestEth = accrued - principal;

        lending.withdraw(interestEth);

        uint256 usdcBefore = usdc.balanceOf(address(this));
        dex.swap{value: interestEth}(address(0), address(usdc), interestEth);
        uint256 harvestedUSDC = usdc.balanceOf(address(this)) - usdcBefore;
        if (harvestedUSDC == 0) return;

        uint256 toStakers = (harvestedUSDC * feeToStakersBps) / MAX_BPS;
        uint256 toVault = harvestedUSDC - toStakers;
        if (toStakers > 0) {
            _distributeToStakers(toStakers);
        }
        // Accumulate protocol fees for owner
        accumulatedProtocolFees += toVault;
        emit HarvestLending(interestEth, harvestedUSDC, toStakers, toVault);
    }

    function harvestFunding() external nonReentrant whenNotPaused {
        (uint256 size,,bool isOpen,) = perps.positions(address(this));
        require(isOpen && size > 0, "no short");
        
        // Check if there's pending funding to claim
        int256 pendingFunding = perps.getPendingFunding(address(this));
        require(pendingFunding > 0, "no funding to claim");
        
        // Claim funding from perpetuals contract
        uint256 usdcBefore = usdc.balanceOf(address(this));
        perps.claimFunding();
        uint256 fundingReceived = usdc.balanceOf(address(this)) - usdcBefore;
        
        // Distribute funding to stakers and vault
        if (fundingReceived > 0) {
            uint256 toStakers = (fundingReceived * feeToStakersBps) / MAX_BPS;
            uint256 toVault = fundingReceived - toStakers;
            if (toStakers > 0) {
                _distributeToStakers(toStakers);
            }
            // Accumulate protocol fees for owner
            accumulatedProtocolFees += toVault;
            emit HarvestFunding(fundingReceived, toStakers, toVault);
        }
    }

    function stake(uint256 shares) external nonReentrant whenNotPaused {
        require(shares > 0, "shares must be more than 0");
        _updateUserRewards(msg.sender);
        totalStakedShares += shares;
        stakedShares[msg.sender] += shares;
        rewardDebt[msg.sender] = (stakedShares[msg.sender] * accRewardsPerStakedShare) / 1e18;
        _transfer(msg.sender, address(this), shares);
        emit Stake(msg.sender, shares);
    }

    function unstake(uint256 shares) external nonReentrant whenNotPaused {
        require(shares > 0 && stakedShares[msg.sender] >= shares, "bad shares");
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

    function totalAssetsUSDC() public view returns (uint256) {
        uint256 total = usdc.balanceOf(address(this));

        // Add ETH value (from lending + held)
        uint256 ethTotal = address(this).balance + lending.getAccruedBalance(address(this));
        if (ethTotal > 0) {
            total += (ethTotal * dex.getLatestPrice()) / 1e8 / 1e12; // price is 8 decimals, convert to 6
        }

        // Add short position value (size + PnL + funding)
        (uint256 size, uint256 entryPrice, bool isOpen,) = perps.positions(address(this));
        if (isOpen && size > 0) {
            int256 pnl = int256(size * 1e12) * (int256(entryPrice * 1e10) - int256(perps.getLatestPrice() * 1e10)) / int256(entryPrice * 1e10) / 1e12;
            int256 positionValue = int256(size) + pnl + perps.getPendingFunding(address(this));
            
            if (positionValue >= 0) {
                total += uint256(positionValue);
            } else if (total > uint256(-positionValue)) {
                total -= uint256(-positionValue);
            } else {
                total = 0;
            }
        }
        return total;
    }

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
            rewardDebt[user] = (stakedShares[user] * accRewardsPerStakedShare) / 1e18;
            require(usdc.transfer(user, pending), "reward xfer failed");
            emit ClaimRewards(user, pending);
        }
    }

    receive() external payable {}
}
