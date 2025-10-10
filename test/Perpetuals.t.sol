// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {Perpetuals} from "../src/Perpetuals.sol";
import {USDC} from "../src/USDC.sol";

// Mock Chainlink price feed
contract MockV3Aggregator {
    uint8 private _decimals;
    int256 private _answer;

    constructor(uint8 decimals_, int256 initialAnswer_) {
        _decimals = decimals_;
        _answer = initialAnswer_;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, _answer, block.timestamp, block.timestamp, 1);
    }

    function updateAnswer(int256 newAnswer) external {
        _answer = newAnswer;
    }
}

contract PerpetualsTest is Test {
    Perpetuals public perps;
    USDC public usdc;
    MockV3Aggregator public priceFeed;
    
    address public owner = address(this);
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    
    uint256 constant INITIAL_PRICE = 3000e8; // $3000 with 8 decimals

    function setUp() public {
        // Deploy contracts
        usdc = new USDC(owner);
        priceFeed = new MockV3Aggregator(8, int256(INITIAL_PRICE));
        perps = new Perpetuals(address(usdc), address(priceFeed));
        
        // Fund users with USDC
        usdc.transfer(user1, 100_000 * 1e6);
        usdc.transfer(user2, 100_000 * 1e6);
        
        // Fund perps contract with USDC for payouts
        usdc.transfer(address(perps), 1_000_000 * 1e6);
    }

    function test_GetLatestPrice() public view {
        uint256 price = perps.getLatestPrice();
        assertEq(price, INITIAL_PRICE);
    }

    function test_OpenShortPosition() public {
        uint256 shortSize = 10_000 * 1e6; // 10k USDC
        
        vm.startPrank(user1);
        usdc.approve(address(perps), shortSize);
        perps.short(shortSize);
        vm.stopPrank();
        
        (uint256 size, uint256 entryPrice, bool isOpen) = perps.positions(user1);
        assertEq(size, shortSize);
        assertEq(entryPrice, INITIAL_PRICE);
        assertTrue(isOpen);
    }

    function test_IncreaseShortPosition() public {
        uint256 firstShort = 5_000 * 1e6;
        uint256 secondShort = 5_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(perps), firstShort + secondShort);
        
        perps.short(firstShort);
        
        // Price changes
        priceFeed.updateAnswer(3500e8);
        
        perps.short(secondShort);
        vm.stopPrank();
        
        (uint256 size, uint256 entryPrice,) = perps.positions(user1);
        assertEq(size, firstShort + secondShort);
        
        // Entry price should be weighted average: (3000*5000 + 3500*5000) / 10000 = 3250
        uint256 expectedEntry = (INITIAL_PRICE * firstShort + 3500e8 * secondShort) / (firstShort + secondShort);
        assertEq(entryPrice, expectedEntry);
    }

    function test_CloseShortProfit() public {
        uint256 shortSize = 10_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(perps), shortSize);
        perps.short(shortSize);
        
        // Price drops to $2500 (profitable for short)
        priceFeed.updateAnswer(2500e8);
        
        uint256 balanceBefore = usdc.balanceOf(user1);
        perps.closeShort();
        uint256 balanceAfter = usdc.balanceOf(user1);
        
        vm.stopPrank();
        
        // PnL = size * (entry - current) / entry
        // = 10000 * (3000 - 2500) / 3000 = 10000 * 500/3000 ≈ 1666.67
        uint256 profit = balanceAfter - balanceBefore;
        assertGt(profit, shortSize); // Should get back more than deposited
        assertApproxEqRel(profit, shortSize + 1_666 * 1e6, 0.01e18); // 1% tolerance
    }

    function test_CloseShortLoss() public {
        uint256 shortSize = 10_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(perps), shortSize);
        perps.short(shortSize);
        
        // Price rises to $3500 (loss for short)
        priceFeed.updateAnswer(3500e8);
        
        uint256 balanceBefore = usdc.balanceOf(user1);
        perps.closeShort();
        uint256 balanceAfter = usdc.balanceOf(user1);
        
        vm.stopPrank();
        
        // Loss = size * (current - entry) / entry
        // = 10000 * (3500 - 3000) / 3000 ≈ -1666.67
        uint256 payout = balanceAfter - balanceBefore;
        assertLt(payout, shortSize); // Should get back less than deposited
        assertApproxEqRel(payout, shortSize - 1_666 * 1e6, 0.01e18);
    }

    function test_ReduceShort() public {
        uint256 shortSize = 10_000 * 1e6;
        uint256 reduceAmount = 3_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(perps), shortSize);
        perps.short(shortSize);
        
        // Price drops
        priceFeed.updateAnswer(2500e8);
        
        uint256 balanceBefore = usdc.balanceOf(user1);
        perps.reduceShort(reduceAmount);
        uint256 balanceAfter = usdc.balanceOf(user1);
        
        vm.stopPrank();
        
        // Position should be reduced
        (uint256 size,,) = perps.positions(user1);
        assertEq(size, shortSize - reduceAmount);
        
        // Should have received payout with profit
        uint256 payout = balanceAfter - balanceBefore;
        assertGt(payout, reduceAmount);
    }

    function test_MultipleUsersShort() public {
        uint256 shortSize = 10_000 * 1e6;
        
        // User1 shorts
        vm.startPrank(user1);
        usdc.approve(address(perps), shortSize);
        perps.short(shortSize);
        vm.stopPrank();
        
        // User2 shorts
        vm.startPrank(user2);
        usdc.approve(address(perps), shortSize);
        perps.short(shortSize);
        vm.stopPrank();
        
        (uint256 size1,,) = perps.positions(user1);
        (uint256 size2,,) = perps.positions(user2);
        
        assertEq(size1, shortSize);
        assertEq(size2, shortSize);
    }

    function test_OwnerWithdraw() public {
        uint256 withdrawAmount = 100_000 * 1e6;
        uint256 balanceBefore = usdc.balanceOf(owner);
        
        perps.ownerWithdraw(withdrawAmount);
        
        assertEq(usdc.balanceOf(owner), balanceBefore + withdrawAmount);
    }

    function test_LargePositionPnL() public {
        uint256 shortSize = 100_000 * 1e6; // 100k USDC
        
        vm.startPrank(user1);
        usdc.approve(address(perps), shortSize);
        perps.short(shortSize);
        
        // 50% price drop
        priceFeed.updateAnswer(1500e8);
        
        uint256 balanceBefore = usdc.balanceOf(user1);
        perps.closeShort();
        uint256 balanceAfter = usdc.balanceOf(user1);
        
        vm.stopPrank();
        
        // Should make ~50% profit
        uint256 profit = balanceAfter - balanceBefore - shortSize;
        assertApproxEqRel(profit, 50_000 * 1e6, 0.01e18);
    }

    function testFail_ShortZeroAmount() public {
        vm.prank(user1);
        perps.short(0);
    }

    function testFail_CloseShortNoPosition() public {
        vm.prank(user1);
        perps.closeShort();
    }

    function testFail_ReduceShortTooMuch() public {
        uint256 shortSize = 10_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(perps), shortSize);
        perps.short(shortSize);
        perps.reduceShort(20_000 * 1e6); // More than position size
        vm.stopPrank();
    }

    function testFail_OwnerWithdrawNotOwner() public {
        vm.prank(user1);
        perps.ownerWithdraw(1000 * 1e6);
    }

    function testFail_ShortWithoutApproval() public {
        vm.prank(user1);
        perps.short(10_000 * 1e6);
    }
}
