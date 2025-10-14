// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;


// Import Chainlink price feed interface
interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function decimals() external view returns (uint8);
}

interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}


contract Perpetuals {

    uint256 public fundingRate; // Annual funding rate in basis points (e.g., 2000 = 20%)
    uint256 public openInterest;
    uint256 public totalShortPosition;
    uint256 public lastFundingTime;
    int256 public cumulativeFundingRate; // Cumulative funding rate scaled by 1e18

    struct Position {
        uint256 size;       // in USDC (6 decimals)
        uint256 entryPrice; // price * 1e8 (from Chainlink)
        bool isOpen;
        int256 fundingIndex; // Funding index when position was opened/last claimed (scaled by 1e18)
    }
    mapping(address => Position) public positions;

    address public usdcToken;
    address public owner;
    AggregatorV3Interface public priceFeed;
    
    event FundingClaimed(address indexed user, int256 amount);
    event FundingRateUpdated(int256 newRate, uint256 timestamp);

    constructor(address _usdc, address _priceFeed) {
        usdcToken = _usdc;
        priceFeed = AggregatorV3Interface(_priceFeed);
        owner = msg.sender;
        lastFundingTime = block.timestamp;
        fundingRate = 2000; // 20% annual funding rate (in basis points)
    }
    
    function getLatestPrice() public view returns (uint256) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        return uint256(price); 
    }
    
    function updateFunding() internal {
        if (block.timestamp <= lastFundingTime) return;
        
        uint256 timeDelta = block.timestamp - lastFundingTime;
        
        // Calculate funding rate for the time period
        // Positive funding rate means shorts earn (longs pay shorts)
        // fundingRate is annual in basis points, we calculate per second
        // Funding accrual = (fundingRate / 10000) * (timeDelta / 365 days) * 1e18
        int256 fundingAccrual = int256((fundingRate * timeDelta * 1e18) / (10000 * 365 days));
        
        cumulativeFundingRate += fundingAccrual;
        lastFundingTime = block.timestamp;
        
        emit FundingRateUpdated(fundingAccrual, block.timestamp);
    }
    
    function getPendingFunding(address user) public view returns (int256) {
        Position memory pos = positions[user];
        if (!pos.isOpen || pos.size == 0) return 0;
        
        // Calculate time-based funding accrual
        uint256 timeDelta = block.timestamp - lastFundingTime;
        int256 fundingAccrual = int256((fundingRate * timeDelta * 1e18) / (10000 * 365 days));
        int256 currentCumulativeRate = cumulativeFundingRate + fundingAccrual;
        
        // Calculate funding payment
        // Positive = user receives funding, Negative = user pays funding
        int256 fundingDelta = currentCumulativeRate - pos.fundingIndex;
        int256 fundingPayment = (int256(pos.size) * fundingDelta) / 1e18;
        
        return fundingPayment;
    }
    
    function claimFunding() external returns (int256) {
        updateFunding();
        
        Position storage pos = positions[msg.sender];
        require(pos.isOpen, "No open position");
        
        int256 fundingPayment = getPendingFunding(msg.sender);
        
        // Update position's funding index
        pos.fundingIndex = cumulativeFundingRate;
        
        if (fundingPayment > 0) {
            // User receives funding
            IERC20(usdcToken).transfer(msg.sender, uint256(fundingPayment));
        } else if (fundingPayment < 0) {
            // User pays funding (reduce position size or take from balance)
            uint256 paymentAmount = uint256(-fundingPayment);
            if (paymentAmount < pos.size) {
                // Reduce position size by funding payment
                pos.size -= paymentAmount;
                openInterest -= paymentAmount;
                totalShortPosition -= paymentAmount;
            } else {
                // Funding payment exceeds position size - liquidate
                uint256 remainingPayment = paymentAmount - pos.size;
                openInterest -= pos.size;
                totalShortPosition -= pos.size;
                pos.size = 0;
                pos.isOpen = false;
                pos.entryPrice = 0;
                
                // Try to collect remaining from user
                IERC20(usdcToken).transferFrom(msg.sender, address(this), remainingPayment);
            }
        }
        
        emit FundingClaimed(msg.sender, fundingPayment);
        return fundingPayment;
    }

    function short(uint256 _amount) external {
        require(_amount > 0, "Amount > 0");
        IERC20(usdcToken).transferFrom(msg.sender, address(this), _amount);

        updateFunding();
        
        uint256 currentPrice = getLatestPrice();
        Position storage pos = positions[msg.sender];

        if (!pos.isOpen) {
            pos.size = _amount;
            pos.entryPrice = currentPrice;
            pos.isOpen = true;
            pos.fundingIndex = cumulativeFundingRate;
        } else {
            // Claim any pending funding before increasing position
            int256 pendingFunding = getPendingFunding(msg.sender);
            if (pendingFunding > 0) {
                IERC20(usdcToken).transfer(msg.sender, uint256(pendingFunding));
                emit FundingClaimed(msg.sender, pendingFunding);
            } else if (pendingFunding < 0) {
                // Deduct from position size
                uint256 paymentAmount = uint256(-pendingFunding);
                if (paymentAmount < pos.size) {
                    pos.size -= paymentAmount;
                }
            }
            
            uint256 oldSize = pos.size;
            uint256 newSize = oldSize + _amount;
            uint256 weightedEntry = (pos.entryPrice * oldSize + currentPrice * _amount) / newSize;
            pos.size = newSize;
            pos.entryPrice = weightedEntry;
            pos.fundingIndex = cumulativeFundingRate;
        }
        
        openInterest += _amount;
        totalShortPosition += _amount;
    }
    
    function reduceShort(uint256 _reduceAmount) external {
        updateFunding();
        
        Position storage pos = positions[msg.sender];
        require(pos.isOpen, "No open position");
        require(_reduceAmount > 0 && _reduceAmount <= pos.size, "Invalid reduce amount");

        // Calculate and add pending funding to payout
        int256 pendingFunding = getPendingFunding(msg.sender);
        pos.fundingIndex = cumulativeFundingRate;

        uint256 currentPrice = getLatestPrice();

        uint256 entry18 = pos.entryPrice * 1e10;
        uint256 current18 = currentPrice * 1e10;
        uint256 reduce18 = _reduceAmount * 1e12;

        int256 pnl18 = int256(reduce18) * (int256(entry18) - int256(current18)) / int256(entry18);
        int256 pnl6 = pnl18 / 1e12;

        // Calculate total payout including funding
        int256 totalPayout = int256(_reduceAmount) + pnl6 + pendingFunding;
        
        uint256 payout;
        if (totalPayout > 0) {
            payout = uint256(totalPayout);
        } else {
            payout = 0;
        }

        pos.size -= _reduceAmount;

        if (pos.size == 0) {
            pos.isOpen = false;
            pos.entryPrice = 0;
            pos.fundingIndex = 0;
        }

        openInterest -= _reduceAmount;
        totalShortPosition -= _reduceAmount;

        if (payout > 0) {
            IERC20(usdcToken).transfer(msg.sender, payout);
        }
        
        if (pendingFunding != 0) {
            emit FundingClaimed(msg.sender, pendingFunding);
        }
    }

    function closeShort() external {
        updateFunding();
        
        Position storage pos = positions[msg.sender];
        require(pos.isOpen, "No open position");

        uint256 sizeToClose = pos.size; // Store before it's modified
        
        // Calculate and add pending funding to payout
        int256 pendingFunding = getPendingFunding(msg.sender);
        
        uint256 currentPrice = getLatestPrice();
        uint256 entry18 = pos.entryPrice * 1e10;
        uint256 current18 = currentPrice * 1e10;
        uint256 size18 = sizeToClose * 1e12;

        int256 pnl18 = int256(size18) * (int256(entry18) - int256(current18)) / int256(entry18);
        int256 pnl6 = pnl18 / 1e12;

        // Calculate total payout including funding
        int256 totalPayout = int256(sizeToClose) + pnl6 + pendingFunding;
        
        uint256 payout;
        if (totalPayout > 0) {
            payout = uint256(totalPayout);
        } else {
            payout = 0;
        }

        pos.isOpen = false;
        pos.size = 0;
        pos.entryPrice = 0;
        pos.fundingIndex = 0;

        openInterest -= sizeToClose;
        totalShortPosition -= sizeToClose;

        if (payout > 0) {
            IERC20(usdcToken).transfer(msg.sender, payout);
        }
        
        if (pendingFunding != 0) {
            emit FundingClaimed(msg.sender, pendingFunding);
        }
    }

    function ownerWithdraw(uint256 _amount) external {
        require(msg.sender == owner, "Not owner");
        IERC20(usdcToken).transfer(owner, _amount);
    }
    
    function setFundingRate(uint256 _newRate) external {
        require(msg.sender == owner, "Not owner");
        require(_newRate <= 10000, "Rate too high"); // Max 100% annual
        updateFunding();
        fundingRate = _newRate;
    }
}

