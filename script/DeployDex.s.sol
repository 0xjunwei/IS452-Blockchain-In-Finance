// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Dex} from "../src/Dex.sol";

// Mock price feed for local testing
interface AggregatorV3Interface {
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
    function decimals() external view returns (uint8);
}

contract MockV3Aggregator is AggregatorV3Interface {
    uint8 private _decimals;
    int256 private _answer;

    constructor(uint8 decimals_, int256 initialAnswer_) {
        _decimals = decimals_;
        _answer = initialAnswer_;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
        return (1, _answer, block.timestamp, block.timestamp, 1);
    }

    function updateAnswer(int256 newAnswer) external {
        _answer = newAnswer;
    }
}

// Mock WETH for testing
contract MockWETH {
    string public name = "Wrapped ETH";
    string public symbol = "WETH";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    receive() external payable {
        balanceOf[msg.sender] += msg.value;
    }
}

contract DeployDex is Script {
    function run() external returns (Dex) {
        // Read from environment or use defaults
        address priceFeed = vm.envOr("PRICE_FEED", address(0));
        address weth = vm.envOr("WETH", address(0));
        address usdc = vm.envOr("USDC", address(0));

        vm.startBroadcast();

        // Deploy mock price feed if not provided
        if (priceFeed == address(0)) {
            MockV3Aggregator mock = new MockV3Aggregator(8, 3000e8); // ETH = $3000
            priceFeed = address(mock);
            console2.log("Deployed mock price feed at:", priceFeed);
        }

        // Deploy mock WETH if not provided
        if (weth == address(0)) {
            MockWETH mockWeth = new MockWETH();
            weth = address(mockWeth);
            console2.log("Deployed mock WETH at:", weth);
        }

        require(usdc != address(0), "USDC address required");

        // Deploy Dex
        Dex dex = new Dex(priceFeed, weth, usdc);
        console2.log("Dex deployed at:", address(dex));
        console2.log("Using PriceFeed:", priceFeed);
        console2.log("Using WETH:", weth);
        console2.log("Using USDC:", usdc);

        vm.stopBroadcast();
        return dex;
    }
}

