// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {Lending} from "../src/Lending.sol";

contract DeployLending is Script {
    function run() external {
        vm.startBroadcast();

        Lending lending = new Lending();
        console2.log("Lending contract deployed at:", address(lending));

        vm.stopBroadcast();
    }
}
