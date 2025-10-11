// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {Dex} from "../src/Dex.sol";
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
        require(balanceOf[msg.sender] >= amount, "MockWETH: transfer amount exceeds balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "MockWETH: transfer amount exceeds balance");
        require(allowance[from][msg.sender] >= amount, "MockWETH: insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }

    receive() external payable {
        balanceOf[msg.sender] += msg.value;
    }
}

contract DexTest is Test {
    Dex public dex;
    USDC public usdc;
    MockWETH public weth;
    MockV3Aggregator public priceFeed;
    
    address public owner = address(this);
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    
    uint256 constant INITIAL_ETH_PRICE = 3000e8; // $3000 with 8 decimals

    function setUp() public {
        // Deploy contracts
        usdc = new USDC(owner);
        weth = new MockWETH();
        priceFeed = new MockV3Aggregator(8, int256(INITIAL_ETH_PRICE));
        dex = new Dex(address(priceFeed), address(weth), address(usdc));
        
        // Fund Dex with liquidity
        usdc.transfer(address(dex), 1_000_000 * 1e6); // 1M USDC
        vm.deal(address(dex), 1000 ether); // 1000 ETH
        
        // Fund users
        vm.deal(user1, 100 ether);
        usdc.transfer(user1, 100_000 * 1e6); // 100k USDC
        vm.deal(user2, 100 ether);
        usdc.transfer(user2, 100_000 * 1e6);
    }

    function test_GetLatestPrice() public view {
        uint256 price = dex.getLatestPrice();
        assertEq(price, INITIAL_ETH_PRICE);
    }

    function test_SwapETHToUSDC() public {
        uint256 ethAmount = 1 ether;
        uint256 expectedUsdc = (ethAmount * INITIAL_ETH_PRICE) / 1e8 / 1e12; // 3000 USDC
        
        uint256 usdcBefore = usdc.balanceOf(user1);
        
        vm.prank(user1);
        dex.swap{value: ethAmount}(address(0), address(usdc), ethAmount);
        
        uint256 usdcAfter = usdc.balanceOf(user1);
        assertEq(usdcAfter - usdcBefore, expectedUsdc);
    }

    function test_SwapUSDCToETH() public {
        uint256 usdcAmount = 3000 * 1e6; // 3000 USDC
        uint256 expectedEth = (usdcAmount * 1e12) * 1e8 / INITIAL_ETH_PRICE; // ~1 ETH
        
        uint256 ethBefore = user1.balance;
        
        vm.startPrank(user1);
        usdc.approve(address(dex), usdcAmount);
        dex.swap(address(usdc), address(0), usdcAmount);
        vm.stopPrank();
        
        uint256 ethAfter = user1.balance;
        
        // Note: ETH transfers change gas, so we check for approximate value
        assertApproxEqAbs(ethAfter - ethBefore, expectedEth, 1e15); // Allow small diff for gas
    }

    function test_SwapWETHToUSDC() public {
        uint256 wethAmount = 1 ether;
        
        // User deposits ETH to get WETH
        vm.prank(user1);
        weth.deposit{value: wethAmount}();
        
        weth.deposit{value: 100 ether}();
        weth.transfer(address(dex), 100 ether);
        
        uint256 expectedUsdc = (wethAmount * INITIAL_ETH_PRICE) / 1e8 / 1e12;
        
        uint256 usdcBefore = usdc.balanceOf(user1);
        vm.startPrank(user1);
        weth.approve(address(dex), wethAmount);
        dex.swap(address(weth), address(usdc), wethAmount);
        vm.stopPrank();
        uint256 usdcAfter = usdc.balanceOf(user1);
        
        assertEq(usdcAfter - usdcBefore, expectedUsdc);
    }

    function test_SwapUSDCToWETH() public {

        weth.deposit{value: 100 ether}();
        weth.transfer(address(dex), 100 ether); // Fund dex with WETH
        
        uint256 usdcAmount = 3000 * 1e6;
        uint256 expectedWeth = (usdcAmount * 1e12) * 1e8 / INITIAL_ETH_PRICE;
        
        uint256 wethBefore = weth.balanceOf(user1);
        vm.startPrank(user1);
        usdc.approve(address(dex), usdcAmount);
        dex.swap(address(usdc), address(weth), usdcAmount);
        vm.stopPrank();
        uint256 wethAfter = weth.balanceOf(user1);
        
        assertEq(wethAfter - wethBefore, expectedWeth);
    }

    function test_PriceUpdate() public {
        priceFeed.updateAnswer(4000e8);
        assertEq(dex.getLatestPrice(), 4000e8);
        
        uint256 ethAmount = 1 ether;
        uint256 initialUserBalance = usdc.balanceOf(user1);
        
        vm.prank(user1);
        dex.swap{value: ethAmount}(address(0), address(usdc), ethAmount);
        
        uint256 expectedUsdc = 4000 * 1e6;
        uint256 finalUserBalance = usdc.balanceOf(user1);
        assertEq(finalUserBalance - initialUserBalance, expectedUsdc);
    }

    function test_DepositToken() public {
        uint256 amount = 1000 * 1e6;
        uint256 dexBalanceBefore = usdc.balanceOf(address(dex));
        
        vm.startPrank(user1);
        usdc.approve(address(dex), amount);
        dex.depositToken(address(usdc), amount);
        vm.stopPrank();
        
        assertEq(usdc.balanceOf(address(dex)), dexBalanceBefore + amount);
    }

    function test_DepositEth() public {
        uint256 amount = 10 ether;
        uint256 balanceBefore = address(dex).balance;
        
        vm.prank(user1);
        dex.depositEth{value: amount}();
        
        assertEq(address(dex).balance, balanceBefore + amount);
    }


    function test_RevertIf_SwapSameToken() public {
        vm.expectRevert(bytes("Cannot swap same token"));
        vm.prank(user1);
        dex.swap(address(usdc), address(usdc), 1000 * 1e6);
    }

    function test_RevertIf_SwapETHWithoutValue() public {
        vm.expectRevert(bytes("ETH amount mismatch"));
        vm.prank(user1);
        dex.swap(address(0), address(usdc), 1 ether);
    }

    function test_RevertIf_SwapInsufficientLiquidity() public {
        uint256 largeAmount = 4_000_000 * 1e6; // Amount of USDC that would require > 1000 ETH
        
        usdc.transfer(user1, largeAmount); // Give user enough USDC
        
        vm.startPrank(user1);
        usdc.approve(address(dex), largeAmount);
        
        vm.expectRevert(bytes("Insufficient ETH liquidity"));
        dex.swap(address(usdc), address(0), largeAmount);
        vm.stopPrank();
    }
}

