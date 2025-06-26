// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {BasicDepositERC4337} from "../contracts/src/BasicDepositERC4337.sol";
import {UUPSProxy} from "../contracts/src/UUPSProxy.sol";
import {IEntryPoint} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";

/// @title Deploy script for BasicDepositERC4337 with Account Abstraction using Foundry
/// @author MIT-DCI
contract DeployERC4337Script is Script {
    // Configuration
    string constant TOKEN_NAME = "Deposit Token ERC4337";
    string constant TOKEN_SYMBOL = "DEPT4337";
    string constant AUTHORIZATION_URI = "http://localhost:3000";
    
    // EntryPoint addresses for different networks
    // Ethereum Mainnet/Sepolia: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789
    // For local testing, we'll use a placeholder address
    address constant ENTRYPOINT_ADDRESS = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    
    // Hardhat default accounts for consistency
    address constant DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant BANK = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant WALLET1 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address constant WALLET2 = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;

    function run() external {
        console.log("=== Foundry ERC-4337 Deposit Token Deployment ===");
        console.log("");
        
        // Start broadcasting transactions
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Bank:", BANK);
        console.log("Wallet 1:", WALLET1);
        console.log("Wallet 2:", WALLET2);
        console.log("EntryPoint:", ENTRYPOINT_ADDRESS);
        console.log("");

        // Step 1: Deploy implementation contract
        console.log("Step 1: Deploying BasicDepositERC4337 implementation...");
        BasicDepositERC4337 implementation = new BasicDepositERC4337(IEntryPoint(ENTRYPOINT_ADDRESS));
        console.log("Implementation deployed to:", address(implementation));

        // Step 2: Encode initialization data
        console.log("");
        console.log("Step 2: Preparing proxy initialization...");
        bytes memory initData = abi.encodeWithSelector(
            BasicDepositERC4337.initialize.selector,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            BANK,
            AUTHORIZATION_URI
        );

        // Step 3: Deploy proxy
        console.log("Step 3: Deploying UUPS proxy...");
        UUPSProxy proxy = new UUPSProxy(address(implementation), initData);
        console.log("Proxy deployed to:", address(proxy));

        // Step 4: Initialize contract through proxy
        console.log("");
        console.log("Step 4: Configuring contract...");
        BasicDepositERC4337 depositToken = BasicDepositERC4337(payable(address(proxy)));
        
        // Verify initialization
        console.log("Token name:", depositToken.name());
        console.log("Token symbol:", depositToken.symbol());
        console.log("Owner:", depositToken.owner());
        console.log("Authorization URI:", depositToken.authorizationURI());
        console.log("EntryPoint:", address(depositToken.entryPoint()));

        // Step 5: Register users
        console.log("");
        console.log("Step 5: Registering users...");
        depositToken.registerUser(WALLET1, BANK);
        console.log("Registered WALLET1 with BANK as sponsor");
        
        depositToken.registerUser(WALLET2, BANK);
        console.log("Registered WALLET2 with BANK as sponsor");

        // Step 6: Mint initial tokens
        console.log("");
        console.log("Step 6: Minting initial tokens...");
        uint256 mintAmount = 1000 ether; // 1000 tokens
        
        depositToken.mint(WALLET1, mintAmount);
        console.log("Minted 1000 tokens to WALLET1");
        
        depositToken.mint(WALLET2, mintAmount);
        console.log("Minted 1000 tokens to WALLET2");

        // Step 7: Add ETH to contract for EntryPoint operations (if deployer has ETH)
        console.log("");
        console.log("Step 7: Adding ETH for EntryPoint operations...");
        uint256 ethAmount = 1 ether; // 1 ETH for gas fees
        if (address(vm.addr(deployerPrivateKey)).balance >= ethAmount) {
            // Send ETH to the contract for EntryPoint operations
            (bool success, ) = payable(address(proxy)).call{value: ethAmount}("");
            if (success) {
                console.log("Added 1 ETH to contract for EntryPoint operations");
            } else {
                console.log("Failed to add ETH to contract");
            }
        } else {
            console.log("Insufficient ETH balance to fund contract");
        }

        // Step 8: Verify final state
        console.log("");
        console.log("Step 8: Verifying deployment...");
        console.log("Total supply:", depositToken.totalSupply() / 1e18, "tokens");
        console.log("WALLET1 balance:", depositToken.balanceOf(WALLET1) / 1e18, "tokens");
        console.log("WALLET2 balance:", depositToken.balanceOf(WALLET2) / 1e18, "tokens");
        console.log("Contract ETH balance:", address(proxy).balance / 1e18, "ETH");

        vm.stopBroadcast();

        // Summary
        console.log("");
        console.log("=== ERC-4337 Deployment Complete ===");
        console.log("Proxy Address:", address(proxy));
        console.log("Implementation:", address(implementation));
        console.log("EntryPoint:", ENTRYPOINT_ADDRESS);
        console.log("Bank Address:", BANK);
        console.log("Wallet 1:", WALLET1);
        console.log("Wallet 2:", WALLET2);
        console.log("");
        console.log("Save these addresses:");
        console.log("DEPOSIT_TOKEN_ADDRESS=", vm.toString(address(proxy)));
        console.log("ENTRYPOINT_ADDRESS=", vm.toString(ENTRYPOINT_ADDRESS));
        console.log("BANK_ADDRESS=", vm.toString(BANK));
        console.log("WALLET_ADDRESS=", vm.toString(WALLET1));
        
        console.log("");
        console.log("=== Account Abstraction Setup ===");
        console.log("To use with ERC-4337 bundlers:");
        console.log("1. Fund the contract with ETH for gas fees");
        console.log("2. Use the contract address as the 'sender' in UserOperations");
        console.log("3. Sign UserOperations with the account owner's private key");
        console.log("4. Submit UserOperations to ERC-4337 bundlers");
    }
}