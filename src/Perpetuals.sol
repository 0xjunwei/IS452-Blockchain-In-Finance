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
}


contract Perpetuals {

    // Current Funding rate
    uint256 public fundingRate;
    // Open Interest
    uint256 public openInterest;
    // Total short position
    uint256 public totalShortPosition;
    // map users address to position opened
    struct Position {
        uint256 size;       // in USDC (6 decimals)
        uint256 entryPrice; // price * 1e8 (from Chainlink)
        bool isOpen;
    }
    mapping(address => Position) public positions;

    // Mock USDC contract address
    address public usdcToken;
    address public owner;
    // Data feed, arb sepolia address
    AggregatorV3Interface public priceFeed;

    constructor(address _usdc, address _priceFeed) {
        usdcToken = _usdc;
        priceFeed = AggregatorV3Interface(_priceFeed);
        owner = msg.sender;
    }
    // Chainlink price feed pricing
    function getLatestPrice() public view returns (uint256) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        return uint256(price); 
    }

    function short(uint256 _amount) external {
        // up OI, totalShortPos and map the position
        // Pull USDC from contract's / user's wallet first
        // Require allowance else will fail by revert

        // price feeds return 8 decimals while usdc is 6, we should factor that into calculation
        require(_amount > 0, "Amount must be more than 0");
        require(!positions[msg.sender].isOpen, "Position already open");

        // Pull USDC from user
        IERC20(usdcToken).transferFrom(msg.sender, address(this), _amount);

        uint256 price = getLatestPrice();

        positions[msg.sender] = Position({
            size: _amount,
            entryPrice: price,
            isOpen: true
        });

        openInterest += _amount;
        totalShortPosition += _amount;

    }

    // Close short
    function closeShort() external {
        // close the position
        // Calculate the interest first before sending capital + interest, since mock perpetuals contract
       Position storage pos = positions[msg.sender];
        require(pos.isOpen, "No open position");

        uint256 currentPrice = getLatestPrice();
        uint256 entry = pos.entryPrice;
        uint256 size = pos.size;

        // Normalize decimals to 18 for calculation:
        uint256 size18 = size * 1e12;
        uint256 entry18 = entry * 1e10;
        uint256 current18 = currentPrice * 1e10;

        // PnL = size * (entry - current) / entry
        // Point to note OI must not be above int256 or position size else overflow
        int256 pnl18 = int256(size18) * (int256(entry18) - int256(current18)) / int256(entry18);

        // Convert back to 6 decimals (USDC)
        int256 pnl6 = pnl18 / 1e12;
        
        uint256 payout;
        if (pnl6 > 0) {
            payout = size + uint256(pnl6);
        } else {
            uint256 loss = uint256(-pnl6);
            payout = size > loss ? size - loss : 0;
        }

        // Reset position
        pos.isOpen = false;
        pos.size = 0;
        pos.entryPrice = 0;

        openInterest -= size;
        totalShortPosition -= size;

        IERC20(usdcToken).transfer(msg.sender, payout);
    }

     function ownerWithdraw(uint256 _amount) external {
        require(msg.sender == owner, "Not owner");
        IERC20(usdcToken).transfer(owner, _amount);
    }
    // Future ref handle longs for funding rate flip
    // Liquidate position function? not needed in this context

    
}
