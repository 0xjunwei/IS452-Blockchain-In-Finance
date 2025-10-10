// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {DeltaVault} from "../src/Delta.sol";
import {USDC} from "../src/USDC.sol";
import {Lending} from "../src/Lending.sol";
import {Perpetuals} from "../src/Perpetuals.sol";
import {Dex} from "../src/Dex.sol";

// Mock contracts for standalone deployment
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

contract MockWETH {
    string public name = "Wrapped ETH";
    string public symbol = "WETH";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount);
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount);
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    receive() external payable {
        balanceOf[msg.sender] += msg.value;
    }
}

contract DeployDelta is Script {
    function run() external returns (DeltaVault, USDC, Lending, Perpetuals, Dex) {
        // Read addresses from environment or deploy new
        address usdc = vm.envOr("USDC", address(0));
        address lending = vm.envOr("LENDING", address(0));
        address perps = vm.envOr("PERPETUALS", address(0));
        address dex = vm.envOr("DEX", address(0));
        address priceFeed = vm.envOr("PRICE_FEED", address(0));
        address weth = vm.envOr("WETH", address(0));
        uint256 feeToStakersBps = vm.envOr("FEE_TO_STAKERS_BPS", uint256(2000)); // 20% default
        address owner = vm.envOr("OWNER", msg.sender);

        vm.startBroadcast();

        // Deploy dependencies if not provided
        USDC usdcContract;
        if (usdc == address(0)) {
            usdcContract = new USDC(msg.sender);
            usdc = address(usdcContract);
            console2.log("Deployed USDC at:", usdc);
        }

        if (priceFeed == address(0)) {
            MockV3Aggregator mock = new MockV3Aggregator(8, 3000e8);
            priceFeed = address(mock);
            console2.log("Deployed mock price feed at:", priceFeed);
        }

        if (weth == address(0)) {
            MockWETH mockWeth = new MockWETH();
            weth = address(mockWeth);
            console2.log("Deployed mock WETH at:", weth);
        }

        Lending lendingContract;
        if (lending == address(0)) {
            lendingContract = new Lending();
            lending = address(lendingContract);
            console2.log("Deployed Lending at:", lending);
        }

        Perpetuals perpsContract;
        if (perps == address(0)) {
            perpsContract = new Perpetuals(usdc, priceFeed);
            perps = address(perpsContract);
            console2.log("Deployed Perpetuals at:", perps);
        }

        Dex dexContract;
        if (dex == address(0)) {
            dexContract = new Dex(priceFeed, weth, usdc);
            dex = address(dexContract);
            console2.log("Deployed Dex at:", dex);
        }

        // Deploy DeltaVault
        DeltaVault vault = new DeltaVault(usdc, lending, perps, dex, feeToStakersBps, owner);
        console2.log("DeltaVault deployed at:", address(vault));
        console2.log("Fee to stakers (bps):", feeToStakersBps);
        console2.log("Owner:", owner);

        vm.stopBroadcast();

        return (vault, usdcContract, lendingContract, perpsContract, dexContract);
    }
}

