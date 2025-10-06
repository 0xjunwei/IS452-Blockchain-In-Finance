// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {Perpetuals} from "../src/Perpetuals.sol";

// Optional local mock
interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80, int256, uint256, uint256, uint80
    );
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

    function latestRoundData() external view override returns (
        uint80, int256, uint256, uint256, uint80
    ) {
        return (1, _answer, block.timestamp, block.timestamp, 1);
    }

    function updateAnswer(int256 newAnswer) external {
        _answer = newAnswer;
    }
}

contract DeployPerpetuals is Script {
    function run() external {
        address usdc = vm.envAddress("USDC");
        address feed = vm.envOr("PRICE_FEED", address(0));

        vm.startBroadcast();

        // If no price feed, deploy mock
        if (feed == address(0)) {
            MockV3Aggregator mock = new MockV3Aggregator(8, 3000e8); // 3000 * 1e8
            feed = address(mock);
            console2.log("Deployed mock price feed at:", feed);
        }

        Perpetuals perps = new Perpetuals(usdc, feed);
        console2.log("Perpetuals deployed at:", address(perps));
        console2.log("Using USDC:", usdc);
        console2.log("Using PriceFeed:", feed);

        vm.stopBroadcast();
    }
}
