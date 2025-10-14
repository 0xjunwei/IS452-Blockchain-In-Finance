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
        require(balanceOf[msg.sender] >= amount, "ERC20: transfer amount exceeds balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "ERC20: transfer amount exceeds balance");
        require(allowance[from][msg.sender] >= amount, "ERC20: insufficient allowance");
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
        
        assertEq(vault.balanceOf(user1), depositAmount);
        
        (uint256 perpsSize,, bool isOpen,) = perps.positions(address(vault));
        assertTrue(isOpen);
        assertEq(perpsSize, depositAmount / 2);
        
        uint256 lendingBalance = lending.getAccruedBalance(address(vault));
        assertGt(lendingBalance, 0);
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
        
        uint256 withdrawAmount = 5_000 * 1e6;
        uint256 usdcBefore = usdc.balanceOf(user1);
        vault.withdraw(withdrawAmount);
        uint256 usdcAfter = usdc.balanceOf(user1);
        
        vm.stopPrank();
        
        assertEq(vault.balanceOf(user1), depositAmount - withdrawAmount);
        // Should get back proportional value based on total vault value
        assertApproxEqRel(usdcAfter - usdcBefore, withdrawAmount, 0.02e18); // 2% tolerance for slippage
    }

    function test_WithdrawAll() public {
        uint256 depositAmount = 10_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        
        vault.withdraw(depositAmount);
        vm.stopPrank();
        
        assertEq(vault.balanceOf(user1), 0);
        assertApproxEqRel(usdc.balanceOf(user1), 1_000_000 * 1e6, 0.05e18);
    }

    function test_HarvestLending() public {
        uint256 depositAmount = 100_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();
        
        vm.warp(block.timestamp + 180 days);
        
        uint256 usdcBefore = usdc.balanceOf(address(vault));
        vault.harvestLending();
        uint256 usdcAfter = usdc.balanceOf(address(vault));
        
        assertGt(usdcAfter, usdcBefore);
    }

    function test_HarvestFunding() public {
        uint256 depositAmount = 100_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();
        
        // Wait 30 days for funding to accrue
        vm.warp(block.timestamp + 30 days);
        
        (uint256 sizeBefore,,,) = perps.positions(address(vault));
        
        // Check pending funding
        int256 pendingFunding = perps.getPendingFunding(address(vault));
        assertGt(pendingFunding, 0, "Should have positive funding");
        
        // Harvest funding
        vault.harvestFunding();
        
        // Position size should remain the same (no close/reopen)
        (uint256 sizeAfter,,,) = perps.positions(address(vault));
        assertEq(sizeAfter, sizeBefore, "Position size should not change");
    }

    function test_Stake() public {
        uint256 depositAmount = 10_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        
        uint256 stakeAmount = 5_000 * 1e6;
        vault.stake(stakeAmount);
        vm.stopPrank();
        
        assertEq(vault.stakedShares(user1), stakeAmount);
        assertEq(vault.totalStakedShares(), stakeAmount);
        assertEq(vault.balanceOf(user1), depositAmount - stakeAmount);
        assertEq(vault.balanceOf(address(vault)), stakeAmount);
    }

    function test_UnstakeAndClaimRewards() public {
        uint256 deposit1 = 10_000 * 1e6;
        vm.startPrank(user1);
        usdc.approve(address(vault), deposit1);
        vault.deposit(deposit1);
        vault.stake(deposit1);
        vm.stopPrank();
        
        vm.warp(block.timestamp + 30 days);
        vault.harvestLending();
        
        uint256 deposit2 = 10_000 * 1e6;
        vm.startPrank(user2);
        usdc.approve(address(vault), deposit2);
        vault.deposit(deposit2);
        vault.stake(deposit2);
        vm.stopPrank();
        
        vm.warp(block.timestamp + 30 days);
        vault.harvestLending();
        
        uint256 pending1 = vault.pendingRewards(user1);
        uint256 usdcBefore1 = usdc.balanceOf(user1);
        
        vm.prank(user1);
        vault.claimRewards();
        
        uint256 usdcAfter1 = usdc.balanceOf(user1);
        
        if (pending1 > 0) {
            assertApproxEqRel(usdcAfter1 - usdcBefore1, pending1, 0.01e18);
        }
        
        vm.prank(user1);
        vault.unstake(deposit1);
        
        assertEq(vault.stakedShares(user1), 0);
        assertEq(vault.balanceOf(user1), deposit1);
    }

    function test_RewardDistribution() public {
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
        
        vm.warp(block.timestamp + 90 days);
        vault.harvestLending();
        
        uint256 pending1 = vault.pendingRewards(user1);
        uint256 pending2 = vault.pendingRewards(user2);
        
        if (pending1 > 0 || pending2 > 0) {
            assertApproxEqRel(pending1, pending2, 0.01e18);
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
        vault.setFeeToStakersBps(3000);
        assertEq(vault.feeToStakersBps(), 3000);
    }

    function test_TotalAssetsUSDC() public {
        uint256 depositAmount = 100_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();
        
        uint256 totalAssets = vault.totalAssetsUSDC();
        
        assertApproxEqRel(totalAssets, depositAmount, 0.1e18);
    }

    function test_RevertIf_DepositZero() public {
        vm.prank(user1);
        vm.expectRevert(bytes("amount=0"));
        vault.deposit(0);
    }

    function test_RevertIf_WithdrawMoreThanBalance() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 10_000 * 1e6);
        vault.deposit(10_000 * 1e6);
        
        vm.expectRevert(bytes("insufficient shares"));
        vault.withdraw(20_000 * 1e6);
        vm.stopPrank();
    }

    function test_RevertIf_StakeWithoutShares() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.stake(1000 * 1e6);
    }

    function test_RevertIf_UnstakeMoreThanStaked() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 10_000 * 1e6);
        vault.deposit(10_000 * 1e6);
        vault.stake(5_000 * 1e6);

        vm.expectRevert(bytes("bad shares"));
        vault.unstake(10_000 * 1e6);
        vm.stopPrank();
    }

    function test_RevertIf_SetFeeNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.setFeeToStakersBps(5000);
    }

    function test_RevertIf_PauseNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.pause();
    }

    function test_RevertIf_SetFeeTooHigh() public {
        vm.expectRevert(bytes("fee too high"));
        vault.setFeeToStakersBps(10001);
    }

    function test_HarvestFundingDoesNotChangePosition() public {
        uint256 depositAmount = 100_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();
        
        // Verify initial position
        (uint256 initialShortSize,,,) = perps.positions(address(vault));
        uint256 initialVaultBalance = usdc.balanceOf(address(vault));
        
        // Wait 90 days for significant funding to accrue
        vm.warp(block.timestamp + 90 days);
        
        // Harvest funding (no position change, just collect funding payment)
        vault.harvestFunding();
        
        // Position should remain unchanged
        (uint256 finalShortSize,,,) = perps.positions(address(vault));
        assertEq(finalShortSize, initialShortSize, "Position size should not change");
        
        // Vault should have more USDC (from funding payment)
        uint256 finalVaultBalance = usdc.balanceOf(address(vault));
        assertGt(finalVaultBalance, initialVaultBalance, "Vault should receive funding");
    }

    function test_WithdrawAfterPriceChange() public {
        uint256 depositAmount = 100_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();
        
        // Price drops from 3000 to 2500 (16.67% drop)
        priceFeed.updateAnswer(2500e8);
        
        // Withdraw everything
        vm.startPrank(user1);
        uint256 usdcBefore = usdc.balanceOf(user1);
        vault.withdraw(depositAmount);
        uint256 usdcAfter = usdc.balanceOf(user1);
        vm.stopPrank();
        
        uint256 received = usdcAfter - usdcBefore;
        
        // Due to delta neutral strategy, user should get back close to deposit amount
        // Allow 2% tolerance for slippage and minor imbalances
        assertApproxEqRel(received, depositAmount, 0.02e18);
        
        // Verify user received at least 98% of their deposit
        assertGe(received, (depositAmount * 98) / 100);
    }

    function test_WithdrawAfterPriceIncrease() public {
        uint256 depositAmount = 100_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();
        
        // Price increases from 3000 to 3600 (20% increase)
        priceFeed.updateAnswer(3600e8);
        
        // Withdraw everything
        vm.startPrank(user1);
        uint256 usdcBefore = usdc.balanceOf(user1);
        vault.withdraw(depositAmount);
        uint256 usdcAfter = usdc.balanceOf(user1);
        vm.stopPrank();
        
        uint256 received = usdcAfter - usdcBefore;
        
        // Due to delta neutral strategy, user should get back close to deposit amount
        // Allow 2% tolerance for slippage and minor imbalances
        assertApproxEqRel(received, depositAmount, 0.02e18);
        
        // Verify user received at least 98% of their deposit
        assertGe(received, (depositAmount * 98) / 100);
    }
}

