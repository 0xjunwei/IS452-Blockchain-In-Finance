// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
// Inherit foundry scripts to help deploy
import {Script} from "forge-std/Script.sol";
// Attach contract you wish to deploy
import {USDC} from "../src/USDC.sol";


contract DeployUSDC is Script {
    address public mintAddy = 0x272B97E93b3AccA272fB9ac7B9043d1Ba6472FC4;
	function run() external returns(USDC) {
		// From forge-std library
		vm.startBroadcast();
		// Any txn we wanna send, we put in between the start and stop broadcast
        
		// To deploy
		USDC mockToken = new USDC(mintAddy);
		
		//When done broadcasting
		vm.stopBroadcast();
		return mockToken;
	}
}