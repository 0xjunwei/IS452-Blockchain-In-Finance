// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {Lending} from "../src/Lending.sol";

contract LendingTest is Test {
    Lending public lending;
    address public owner = address(this);
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    function setUp() public {
        lending = new Lending();
        // Fund users with ETH
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(address(lending), 1000 ether); // Fund lending pool
    }

    function test_Deposit() public {
        uint256 depositAmount = 10 ether;
        
        vm.prank(user1);
        lending.deposit{value: depositAmount}();
        
        (uint256 amount, uint256 lastUpdate) = lending.deposits(user1);
        assertEq(amount, depositAmount);
        assertEq(lastUpdate, block.timestamp);
        assertEq(lending.totalDeposits(), depositAmount);
    }

    function test_MultipleDeposits() public {
        vm.startPrank(user1);
        lending.deposit{value: 5 ether}();
        lending.deposit{value: 5 ether}();
        vm.stopPrank();
        
        (uint256 amount,) = lending.deposits(user1);
        assertEq(amount, 10 ether);
    }

    function test_InterestAccrual() public {
        uint256 depositAmount = 10 ether;
        
        vm.prank(user1);
        lending.deposit{value: depositAmount}();
        
        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);
        
        uint256 expectedInterest = (depositAmount * 200 * 365 days) / (365 days * 10000);
        uint256 accruedBalance = lending.getAccruedBalance(user1);
        
        assertEq(accruedBalance, depositAmount + expectedInterest);
    }

    function test_WithdrawWithInterest() public {
        uint256 depositAmount = 10 ether;
        
        vm.prank(user1);
        lending.deposit{value: depositAmount}();
        
        // Fast forward 6 months
        vm.warp(block.timestamp + 182 days);
        
        uint256 accruedBalance = lending.getAccruedBalance(user1);
        uint256 balanceBefore = user1.balance;
        
        vm.prank(user1);
        lending.withdraw(accruedBalance);
        
        assertEq(user1.balance, balanceBefore + accruedBalance);
        (uint256 amount,) = lending.deposits(user1);
        assertEq(amount, 0);
    }

    function test_PartialWithdraw() public {
        uint256 depositAmount = 10 ether;
        
        vm.prank(user1);
        lending.deposit{value: depositAmount}();
        
        vm.warp(block.timestamp + 100 days);
        
        uint256 withdrawAmount = 5 ether;
        vm.prank(user1);
        lending.withdraw(withdrawAmount);
        
        (uint256 remaining,) = lending.deposits(user1);
        assertGt(remaining, 5 ether); // Should be > 5 due to interest
    }

    function test_CompoundingInterest() public {
        vm.startPrank(user1);
        lending.deposit{value: 10 ether}();
        
        vm.warp(block.timestamp + 180 days);
        lending.deposit{value: 1 wei}(); // Trigger interest accrual
        
        (uint256 amount1,) = lending.deposits(user1);
        
        vm.warp(block.timestamp + 180 days);
        vm.stopPrank();
        
        uint256 accrued = lending.getAccruedBalance(user1);
        assertGt(accrued, amount1); // Interest on interest
    }

    function test_OwnerWithdraw() public {
        vm.deal(address(lending), 100 ether);
        
        uint256 withdrawAmount = 50 ether;
        uint256 balanceBefore = owner.balance;
        
        lending.ownerWithdraw(withdrawAmount);
        
        assertEq(owner.balance, balanceBefore + withdrawAmount);
    }

    function testFail_WithdrawMoreThanBalance() public {
        vm.startPrank(user1);
        lending.deposit{value: 10 ether}();
        lending.withdraw(20 ether);
        vm.stopPrank();
    }

    function testFail_WithdrawWithoutDeposit() public {
        vm.prank(user1);
        lending.withdraw(1 ether);
    }

    function testFail_OwnerWithdrawNotOwner() public {
        vm.prank(user1);
        lending.ownerWithdraw(1 ether);
    }

    function testFail_DepositZero() public {
        vm.prank(user1);
        lending.deposit{value: 0}();
    }
}

