// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {USDC} from "../src/USDC.sol";
import {Lending} from "../src/Lending.sol";
import {Dex} from "../src/Dex.sol";
import {Perpetuals} from "../src/Perpetuals.sol";
import {DeltaVault} from "../src/Delta.sol";

// Mock WETH for Arbitrum Sepolia if needed
contract MockWETH {
    string public name = "Wrapped ETH";
    string public symbol = "WETH";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
        emit Transfer(msg.sender, address(0), amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        emit Transfer(from, to, amount);
        return true;
    }

    receive() external payable {
        balanceOf[msg.sender] += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }
}

contract DeployAll is Script {
    // Arbitrum Sepolia ETH/USD Price Feed
    address public constant PRICE_FEED = 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165;
    
    // Known WETH on Arbitrum Sepolia (if exists, otherwise deploy mock)
    address public constant ARBITRUM_SEPOLIA_WETH = 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("===========================================");
        console2.log("Deploying to Arbitrum Sepolia");
        console2.log("Deployer:", deployer);
        console2.log("Deployer Balance:", deployer.balance);
        console2.log("===========================================\n");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy USDC
        console2.log("Step 1: Deploying USDC...");
        USDC usdc = new USDC(deployer);
        console2.log("USDC deployed at:", address(usdc));
        console2.log("Initial USDC balance:", usdc.balanceOf(deployer));
        console2.log("");
        
        // Step 2: Deploy Lending and prefund with 1 ETH
        console2.log("Step 2: Deploying Lending...");
        Lending lending = new Lending();
        console2.log("Lending deployed at:", address(lending));
        
        console2.log("Prefunding Lending with 1 ETH...");
        lending.deposit{value: 1 ether}();
        console2.log("Lending funded with 1 ETH");
        console2.log("");
        
        // Step 3: Deploy or use existing WETH
        address weth = ARBITRUM_SEPOLIA_WETH;
        console2.log("Step 3: Setting up WETH...");
        
        // Try to verify if WETH exists, if not deploy mock
        uint256 wethCodeSize;
        assembly {
            wethCodeSize := extcodesize(weth)
        }
        
        if (wethCodeSize == 0) {
            console2.log("WETH not found at known address, deploying MockWETH...");
            MockWETH mockWeth = new MockWETH();
            weth = address(mockWeth);
            console2.log("MockWETH deployed at:", weth);
        } else {
            console2.log("Using existing WETH at:", weth);
        }
        console2.log("");
        
        // Step 4: Deploy Dex and prefund with 2M USDC + 1 ETH
        console2.log("Step 4: Deploying Dex...");
        Dex dex = new Dex(PRICE_FEED, weth, address(usdc));
        console2.log("Dex deployed at:", address(dex));
        
        console2.log("Prefunding Dex with 2,000,000 USDC...");
        uint256 dexUsdcAmount = 2_000_000 * 10**6; // 2M USDC (6 decimals)
        usdc.transfer(address(dex), dexUsdcAmount);
        console2.log("Dex funded with 2M USDC");
        
        console2.log("Prefunding Dex with 1 ETH...");
        dex.depositEth{value: 1 ether}();
        console2.log("Dex funded with 1 ETH");
        console2.log("");
        
        // Step 5: Deploy Perpetuals and prefund with 2M USDC
        console2.log("Step 5: Deploying Perpetuals...");
        Perpetuals perps = new Perpetuals(address(usdc), PRICE_FEED);
        console2.log("Perpetuals deployed at:", address(perps));
        
        console2.log("Prefunding Perpetuals with 2,000,000 USDC...");
        uint256 perpsUsdcAmount = 2_000_000 * 10**6; // 2M USDC (6 decimals)
        usdc.transfer(address(perps), perpsUsdcAmount);
        console2.log("Perpetuals funded with 2M USDC");
        console2.log("");
        
        // Step 6: Deploy Delta to link everything
        console2.log("Step 6: Deploying Delta Vault...");
        uint256 feeToStakersBps = 8000; // 80% fee to stakers
        DeltaVault delta = new DeltaVault(
            address(usdc),
            address(lending),
            address(perps),
            address(dex),
            feeToStakersBps,
            deployer
        );
        console2.log("Delta Vault deployed at:", address(delta));
        console2.log("");
        
        vm.stopBroadcast();
        
        // Print summary
        console2.log("===========================================");
        console2.log("DEPLOYMENT SUMMARY");
        console2.log("===========================================");
        console2.log("Network: Arbitrum Sepolia (Chain ID: 421614)");
        console2.log("Price Feed:", PRICE_FEED);
        console2.log("WETH:", weth);
        console2.log("");
        console2.log("Deployed Contracts:");
        console2.log("-------------------------------------------");
        console2.log("USDC:        ", address(usdc));
        console2.log("Lending:     ", address(lending), "(funded with 1 ETH)");
        console2.log("Dex:         ", address(dex), "(funded with 2M USDC + 1 ETH)");
        console2.log("Perpetuals:  ", address(perps), "(funded with 2M USDC)");
        console2.log("Delta Vault: ", address(delta));
        console2.log("===========================================");
        console2.log("");
        console2.log("Remaining deployer USDC balance:", usdc.balanceOf(deployer));
        console2.log("Remaining deployer ETH balance:", deployer.balance);
        console2.log("");
        console2.log("Next Steps:");
        console2.log("1. Approve Delta Vault to spend your USDC");
        console2.log("2. Deposit USDC into Delta Vault");
        console2.log("===========================================");
    }
}

