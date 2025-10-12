//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/src/interfaces/feeds/AggregatorV3Interface.sol";

contract Dex {
    // Price feed addy
    // 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165
    AggregatorV3Interface internal priceFeed;
    address public weth;   // Wrapped ETH address
    address public usdc;
    uint8 internal feedDecimals; // Chainlink feed decimals (usually 8)

	function getLatestPrice() public view returns (uint256) {
		(, int256 price, , , ) = priceFeed.latestRoundData();
		require(price > 0, "Invalid price");
		return uint256(price);
	}
    event Swap(address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    constructor(address _priceFeedAddress, address _weth, address _usdc) {
        priceFeed = AggregatorV3Interface(_priceFeedAddress);
        weth = _weth;
        usdc = _usdc;
        feedDecimals = priceFeed.decimals();
    }


    function swap(address tokenIn, address tokenOut, uint256 amountIn) external payable {
        require(tokenIn == weth || tokenIn == address(0) || tokenIn == usdc, "Unsupported tokenIn");
        require(tokenOut == weth || tokenOut == address(0) || tokenOut == usdc, "Unsupported tokenOut");
        require(tokenIn != tokenOut, "Cannot swap same token");

        uint256 ethUsdPrice = getLatestPrice(); // e.g. 3000 * 10^feedDecimals

        uint256 amountOut;

        // Native ETH -> USDC
        if (tokenIn == address(0) && tokenOut == usdc) {
            require(msg.value == amountIn, "ETH amount mismatch");

            // Convert 18-dec ETH to 6-dec USDC using feed decimals
            amountOut = (amountIn * ethUsdPrice) / (10 ** feedDecimals); // now 18 + feedDecimals - feedDecimals = 18
            amountOut = amountOut / (10 ** 12); // reduce to 6 decimals

            // Transfer USDC from contract to user
            require(IERC20(usdc).balanceOf(address(this)) >= amountOut, "Insufficient USDC liquidity");
            IERC20(usdc).transfer(msg.sender, amountOut);
        }

        // WETH -> USDC
        else if (tokenIn == weth && tokenOut == usdc) {
            IERC20(weth).transferFrom(msg.sender, address(this), amountIn);

            // Same conversion as native ETH -> USDC
            amountOut = (amountIn * ethUsdPrice) / (10 ** feedDecimals);
            amountOut = amountOut / (10 ** 12);

            require(IERC20(usdc).balanceOf(address(this)) >= amountOut, "Insufficient USDC liquidity");
            IERC20(usdc).transfer(msg.sender, amountOut);
        }

        
        // USDC -> Native ETH or WETH
        else if (tokenIn == usdc && (tokenOut == address(0) || tokenOut == weth)) {
            IERC20(usdc).transferFrom(msg.sender, address(this), amountIn);

            // Convert 6-dec USDC to 18-dec ETH using feed decimals
            uint256 ethOut = (amountIn * (10 ** 12)) * (10 ** feedDecimals) / ethUsdPrice;
            amountOut = ethOut;

            if (tokenOut == address(0)) {
                require(address(this).balance >= amountOut, "Insufficient ETH liquidity");
                payable(msg.sender).transfer(amountOut);
            } else {
                require(IERC20(weth).balanceOf(address(this)) >= amountOut, "Insufficient WETH liquidity");
                IERC20(weth).transfer(msg.sender, amountOut);
            }
        }

        else {
            revert("Unsupported pair");
        }

        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    
    function depositToken(address token, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    function depositEth() external payable {}

    function withdraw(address token, uint256 amount) external {
        if (token == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(token).transfer(msg.sender, amount);
        }
    }

    receive() external payable {}
}