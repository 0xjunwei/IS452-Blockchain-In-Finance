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
    function positions(address user) external view returns (uint256 size, uint256 entryPrice, bool isOpen);
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
            dex.swap{value: ethNeeded}(address(0), address(usdc), ethNeeded);
        }

        uint256 usdcToUser = usdc.balanceOf(address(this)) >= shares ? shares : usdc.balanceOf(address(this));
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
        emit HarvestLending(interestEth, harvestedUSDC, toStakers, toVault);
    }

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
            emit HarvestFunding(reduceAmountUSDC, realized, toStakers, toVault);
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
        uint256 total;
        total += usdc.balanceOf(address(this));

        uint256 ethHeld = address(this).balance;
        uint256 ethLending = lending.getAccruedBalance(address(this));
        uint256 ethTotal = ethHeld + ethLending;
        if (ethTotal > 0) {
            uint256 price = dex.getLatestPrice();
            uint8 feedDecimals = 8;
            uint256 usdcFromEth = (ethTotal * price) / (10 ** feedDecimals);
            usdcFromEth = usdcFromEth / 1e12;
            total += usdcFromEth;
        }

        (uint256 size, uint256 entryPrice, bool isOpen) = perps.positions(address(this));
        if (isOpen && size > 0) {
            uint256 current = perps.getLatestPrice();
            uint256 entry18 = entryPrice * 1e10;
            uint256 current18 = current * 1e10;
            uint256 size18 = size * 1e12;
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
