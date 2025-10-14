// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {USDC} from "../src/USDC.sol";

contract USDCTest is Test {
    USDC public usdc;
    address public owner = address(this);
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    function setUp() public {
        usdc = new USDC(owner);
    }

    function test_InitialSupply() public view {
        uint256 expectedSupply = 100_000_000 * 1e6; // 100M USDC
        assertEq(usdc.totalSupply(), expectedSupply);
        assertEq(usdc.balanceOf(owner), expectedSupply);
    }

    function test_Decimals() public view {
        assertEq(usdc.decimals(), 6);
    }

    function test_NameAndSymbol() public view {
        assertEq(usdc.name(), "USDC");
        assertEq(usdc.symbol(), "USDC");
    }

    function test_Transfer() public {
        uint256 amount = 1000 * 1e6;
        usdc.transfer(user1, amount);
        assertEq(usdc.balanceOf(user1), amount);
        assertEq(usdc.balanceOf(owner), 100_000_000 * 1e6 - amount);
    }

    function test_TransferFrom() public {
        uint256 amount = 1000 * 1e6;
        usdc.approve(user1, amount);
        
        vm.prank(user1);
        usdc.transferFrom(owner, user2, amount);
        
        assertEq(usdc.balanceOf(user2), amount);
        assertEq(usdc.allowance(owner, user1), 0);
    }

    function test_Permit() public {
        uint256 privateKey = 0xA11CE;
        address alice = vm.addr(privateKey);
        
        uint256 amount = 1000 * 1e6;
        uint256 deadline = block.timestamp + 1 days;
        
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                alice,
                user1,
                amount,
                0, // nonce
                deadline
            )
        );
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                usdc.DOMAIN_SEPARATOR(),
                structHash
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        
        usdc.permit(alice, user1, amount, deadline, v, r, s);
        assertEq(usdc.allowance(alice, user1), amount);
    }

    function test_RevertIf_TransferInsufficientBalance() public {
        vm.prank(user1);
        vm.expectRevert();
        usdc.transfer(user2, 1000 * 1e6);
    }

    function test_RevertIf_TransferFromInsufficientAllowance() public {
        vm.prank(user1);
        vm.expectRevert();
        usdc.transferFrom(owner, user2, 1000 * 1e6);
    }
}

