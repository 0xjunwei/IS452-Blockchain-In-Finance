// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {USDC} from "../src/USDC.sol";

contract USDCScript is Script {
    USDC public counter;
    address public addy = 0x000000000000000000000000000000000000dEaD;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        counter = new USDC(addy);

        vm.stopBroadcast();
    }
}
