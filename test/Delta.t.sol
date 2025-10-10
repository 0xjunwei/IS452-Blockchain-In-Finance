// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {DeltaVault} from "../src/Delta.sol";
import {USDC} from "../src/USDC.sol";
import {Lending} from "../src/Lending.sol";
import {Perpetuals} from "../src/Perpetuals.sol";
import {Dex} from "../src/Dex.sol";

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

// Mock WETH
contract MockWETH {
    string public name = "Wrapped ETH";
    string public symbol = "WETH";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount);
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount);
        require(allowance[from][msg.sender] >= amount);
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }

    receive() external payable {
        balanceOf[msg.sender] += msg.value;
    }
}

contract DeltaTest is Test {
    DeltaVault public vault;
    USDC public usdc;
    Lending public lending;
    Perpetuals public perps;
    Dex public dex;
    MockWETH public weth;
    MockV3Aggregator public priceFeed;
    
    address public owner = address(this);
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    
    uint256 constant INITIAL_PRICE = 3000e8; // $3000 with 8 decimals
    uint256 constant FEE_TO_STAKERS_BPS = 2000; // 20%

    function setUp() public {
        // Deploy core contracts
        usdc = new USDC(owner);
        lending = new Lending();
        priceFeed = new MockV3Aggregator(8, int256(INITIAL_PRICE));
        perps = new Perpetuals(address(usdc), address(priceFeed));
        weth = new MockWETH();
        dex = new Dex(address(priceFeed), address(weth), address(usdc));
        
        // Deploy Delta Vault
        vault = new DeltaVault(
            address(usdc),
            address(lending),
            address(perps),
            address(dex),
            FEE_TO_STAKERS_BPS,
            owner
        );
        
        // Setup liquidity
        usdc.transfer(address(dex), 10_000_000 * 1e6); // 10M USDC to Dex
        vm.deal(address(dex), 5000 ether); // 5000 ETH to Dex
        vm.deal(address(lending), 5000 ether); // 5000 ETH to Lending
        usdc.transfer(address(perps), 10_000_000 * 1e6); // 10M USDC to Perps
        
        // Fund users
        usdc.transfer(user1, 1_000_000 * 1e6);
        usdc.transfer(user2, 1_000_000 * 1e6);
    }

    function test_InitialState() public view {
        assertEq(vault.decimals(), 6);
        assertEq(vault.feeToStakersBps(), FEE_TO_STAKERS_BPS);
        assertEq(address(vault.usdc()), address(usdc));
        assertEq(address(vault.lending()), address(lending));
        assertEq(address(vault.perps()), address(perps));
        assertEq(address(vault.dex()), address(dex));
    }

    function test_Deposit() public {
        uint256 depositAmount = 10_000 * 1e6; // 10k USDC
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();
        
        // Check shares minted 1:1
        assertEq(vault.balanceOf(user1), depositAmount);
        
        // Check positions opened
        (uint256 perpsSize,, bool isOpen) = perps.positions(address(vault));
        assertTrue(isOpen);
        assertEq(perpsSize, depositAmount / 2); // 50% in perps
        
        // Check ETH deposited in lending
        uint256 lendingBalance = lending.getAccruedBalance(address(vault));
        assertGt(lendingBalance, 0); // Should have ETH in lending
    }

    function test_MultipleDeposits() public {
        uint256 deposit1 = 10_000 * 1e6;
        uint256 deposit2 = 5_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(vault), deposit1 + deposit2);
        vault.deposit(deposit1);
        vault.deposit(deposit2);
        vm.stopPrank();
        
        assertEq(vault.balanceOf(user1), deposit1 + deposit2);
    }

    function test_Withdraw() public {
        uint256 depositAmount = 10_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        
        // Withdraw half
        uint256 withdrawAmount = 5_000 * 1e6;
        uint256 usdcBefore = usdc.balanceOf(user1);
        vault.withdraw(withdrawAmount);
        uint256 usdcAfter = usdc.balanceOf(user1);
        
        vm.stopPrank();
        
        // Check shares burned and USDC received
        assertEq(vault.balanceOf(user1), depositAmount - withdrawAmount);
        assertEq(usdcAfter - usdcBefore, withdrawAmount);
    }

    function test_WithdrawAll() public {
        uint256 depositAmount = 10_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        
        vault.withdraw(depositAmount);
        vm.stopPrank();
        
        assertEq(vault.balanceOf(user1), 0);
        // Should get back approximately the deposit (minus swap slippage/fees)
        assertApproxEqRel(usdc.balanceOf(user1), 1_000_000 * 1e6, 0.05e18); // 5% tolerance
    }

    function test_HarvestLending() public {
        uint256 depositAmount = 100_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();
        
        // Fast forward to accrue interest
        vm.warp(block.timestamp + 180 days);
        
        // Harvest
        uint256 usdcBefore = usdc.balanceOf(address(vault));
        vault.harvestLending();
        uint256 usdcAfter = usdc.balanceOf(address(vault));
        
        // Should have harvested some USDC
        assertGt(usdcAfter, usdcBefore);
    }

    function test_HarvestFunding() public {
        uint256 depositAmount = 100_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();
        
        // Price drops (profitable for short)
        priceFeed.updateAnswer(2500e8);
        
        (uint256 sizeBefore,,) = perps.positions(address(vault));
        
        // Harvest funding
        uint256 harvestAmount = sizeBefore / 2;
        vault.harvestFunding(harvestAmount);
        
        // Position should be maintained at same size
        (uint256 sizeAfter,,) = perps.positions(address(vault));
        assertEq(sizeAfter, sizeBefore);
    }

    function test_Stake() public {
        uint256 depositAmount = 10_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        
        // Stake shares
        uint256 stakeAmount = 5_000 * 1e6;
        vault.stake(stakeAmount);
        vm.stopPrank();
        
        assertEq(vault.stakedShares(user1), stakeAmount);
        assertEq(vault.totalStakedShares(), stakeAmount);
        assertEq(vault.balanceOf(user1), depositAmount - stakeAmount);
        assertEq(vault.balanceOf(address(vault)), stakeAmount);
    }

    function test_UnstakeAndClaimRewards() public {
        // User1 stakes
        uint256 deposit1 = 10_000 * 1e6;
        vm.startPrank(user1);
        usdc.approve(address(vault), deposit1);
        vault.deposit(deposit1);
        vault.stake(deposit1);
        vm.stopPrank();
        
        // Generate some rewards by harvesting
        vm.warp(block.timestamp + 30 days);
        vault.harvestLending();
        
        // User2 deposits and stakes
        uint256 deposit2 = 10_000 * 1e6;
        vm.startPrank(user2);
        usdc.approve(address(vault), deposit2);
        vault.deposit(deposit2);
        vault.stake(deposit2);
        vm.stopPrank();
        
        // More rewards
        vm.warp(block.timestamp + 30 days);
        vault.harvestLending();
        
        // User1 claims rewards
        uint256 pending1 = vault.pendingRewards(user1);
        uint256 usdcBefore1 = usdc.balanceOf(user1);
        
        vm.prank(user1);
        vault.claimRewards();
        
        uint256 usdcAfter1 = usdc.balanceOf(user1);
        
        if (pending1 > 0) {
            assertEq(usdcAfter1 - usdcBefore1, pending1);
        }
        
        // User1 unstakes
        vm.prank(user1);
        vault.unstake(deposit1);
        
        assertEq(vault.stakedShares(user1), 0);
        assertEq(vault.balanceOf(user1), deposit1);
    }

    function test_RewardDistribution() public {
        // Two users stake equal amounts
        uint256 stakeAmount = 10_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(vault), stakeAmount);
        vault.deposit(stakeAmount);
        vault.stake(stakeAmount);
        vm.stopPrank();
        
        vm.startPrank(user2);
        usdc.approve(address(vault), stakeAmount);
        vault.deposit(stakeAmount);
        vault.stake(stakeAmount);
        vm.stopPrank();
        
        // Generate rewards
        vm.warp(block.timestamp + 90 days);
        vault.harvestLending();
        
        // Both should have equal pending rewards
        uint256 pending1 = vault.pendingRewards(user1);
        uint256 pending2 = vault.pendingRewards(user2);
        
        if (pending1 > 0 || pending2 > 0) {
            assertApproxEqRel(pending1, pending2, 0.01e18); // 1% tolerance
        }
    }

    function test_PauseUnpause() public {
        vault.pause();
        
        vm.expectRevert();
        vm.prank(user1);
        vault.deposit(1000 * 1e6);
        
        vault.unpause();
        
        vm.startPrank(user1);
        usdc.approve(address(vault), 1000 * 1e6);
        vault.deposit(1000 * 1e6);
        vm.stopPrank();
        
        assertEq(vault.balanceOf(user1), 1000 * 1e6);
    }

    function test_SetFeeToStakersBps() public {
        vault.setFeeToStakersBps(3000); // 30%
        assertEq(vault.feeToStakersBps(), 3000);
    }

    function test_TotalAssetsUSDC() public {
        uint256 depositAmount = 100_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();
        
        uint256 totalAssets = vault.totalAssetsUSDC();
        
        // Total assets should be approximately the deposit amount
        // (accounting for positions in lending and perps)
        assertApproxEqRel(totalAssets, depositAmount, 0.1e18); // 10% tolerance
    }

    function testFail_DepositZero() public {
        vm.prank(user1);
        vault.deposit(0);
    }

    function testFail_WithdrawMoreThanBalance() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 10_000 * 1e6);
        vault.deposit(10_000 * 1e6);
        vault.withdraw(20_000 * 1e6);
        vm.stopPrank();
    }

    function testFail_StakeWithoutShares() public {
        vm.prank(user1);
        vault.stake(1000 * 1e6);
    }

    function testFail_UnstakeMoreThanStaked() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 10_000 * 1e6);
        vault.deposit(10_000 * 1e6);
        vault.stake(5_000 * 1e6);
        vault.unstake(10_000 * 1e6);
        vm.stopPrank();
    }

    function testFail_SetFeeNotOwner() public {
        vm.prank(user1);
        vault.setFeeToStakersBps(5000);
    }

    function testFail_PauseNotOwner() public {
        vm.prank(user1);
        vault.pause();
    }

    function testFail_SetFeeTooHigh() public {
        vault.setFeeToStakersBps(10001); // > MAX_BPS
    }
}

