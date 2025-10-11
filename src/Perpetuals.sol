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

    uint256 public fundingRate;
    uint256 public openInterest;
    uint256 public totalShortPosition;

    struct Position {
        uint256 size;       // in USDC (6 decimals)
        uint256 entryPrice; // price * 1e8 (from Chainlink)
        bool isOpen;
    }
    mapping(address => Position) public positions;

    address public usdcToken;
    address public owner;
    AggregatorV3Interface public priceFeed;

    constructor(address _usdc, address _priceFeed) {
        usdcToken = _usdc;
        priceFeed = AggregatorV3Interface(_priceFeed);
        owner = msg.sender;
    }
    
    function getLatestPrice() public view returns (uint256) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        return uint256(price); 
    }

    function short(uint256 _amount) external {
        require(_amount > 0, "Amount > 0");
        IERC20(usdcToken).transferFrom(msg.sender, address(this), _amount);

        uint256 currentPrice = getLatestPrice();
        Position storage pos = positions[msg.sender];

        if (!pos.isOpen) {
            pos.size = _amount;
            pos.entryPrice = currentPrice;
            pos.isOpen = true;
        } else {
            uint256 oldSize = pos.size;
            uint256 newSize = oldSize + _amount;
            uint256 weightedEntry = (pos.entryPrice * oldSize + currentPrice * _amount) / newSize;
            pos.size = newSize;
            pos.entryPrice = weightedEntry;
        }
        
        openInterest += _amount;
        totalShortPosition += _amount;
    }
    
    function reduceShort(uint256 _reduceAmount) external {
        Position storage pos = positions[msg.sender];
        // --- FIX: Made error message consistent ---
        require(pos.isOpen, "No open position");
        require(_reduceAmount > 0 && _reduceAmount <= pos.size, "Invalid reduce amount");

        uint256 currentPrice = getLatestPrice();

        uint256 entry18 = pos.entryPrice * 1e10;
        uint256 current18 = currentPrice * 1e10;
        uint256 reduce18 = _reduceAmount * 1e12;

        int256 pnl18 = int256(reduce18) * (int256(entry18) - int256(current18)) / int256(entry18);
        int256 pnl6 = pnl18 / 1e12;

        uint256 payout;
        if (pnl6 > 0) {
            payout = _reduceAmount + uint256(pnl6);
        } else {
            uint256 loss = uint256(-pnl6);
            payout = _reduceAmount > loss ? _reduceAmount - loss : 0;
        }

        pos.size -= _reduceAmount;

        if (pos.size == 0) {
            pos.isOpen = false;
            pos.entryPrice = 0;
        }

        openInterest -= _reduceAmount;
        totalShortPosition -= _reduceAmount;

        IERC20(usdcToken).transfer(msg.sender, payout);
    }

    function closeShort() external {
        Position storage pos = positions[msg.sender];
        require(pos.isOpen, "No open position");

        uint256 sizeToClose = pos.size; // Store before it's modified
        
        uint256 currentPrice = getLatestPrice();
        uint256 entry18 = pos.entryPrice * 1e10;
        uint256 current18 = currentPrice * 1e10;
        uint256 size18 = sizeToClose * 1e12;

        int256 pnl18 = int256(size18) * (int256(entry18) - int256(current18)) / int256(entry18);
        int256 pnl6 = pnl18 / 1e12;

        uint256 payout;
        if (pnl6 > 0) {
            payout = sizeToClose + uint256(pnl6);
        } else {
            uint256 loss = uint256(-pnl6);
            payout = sizeToClose > loss ? sizeToClose - loss : 0;
        }

        pos.isOpen = false;
        pos.size = 0;
        pos.entryPrice = 0;

        openInterest -= sizeToClose;
        totalShortPosition -= sizeToClose;

        IERC20(usdcToken).transfer(msg.sender, payout);
    }

    function ownerWithdraw(uint256 _amount) external {
        require(msg.sender == owner, "Not owner");
        IERC20(usdcToken).transfer(owner, _amount);
    }
}

