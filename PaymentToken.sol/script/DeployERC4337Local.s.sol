// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {BasicDepositERC4337} from "../contracts/src/BasicDepositERC4337.sol";
import {UUPSProxy} from "../contracts/src/UUPSProxy.sol";
import {IEntryPoint, PackedUserOperation, IAggregator} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";

/// @title Mock EntryPoint for local testing
contract MockEntryPoint {
    mapping(address => uint256) public balanceOf;
    
    function depositTo(address account) external payable {
        balanceOf[account] += msg.value;
    }
    
    function withdrawTo(address payable withdrawAddress, uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        withdrawAddress.transfer(amount);
    }
    
    function getNonce(address, uint192) external pure returns (uint256) {
        return 0;
    }
    
    // Mock functions for IEntryPointStake interface
    function addStake(uint32) external payable {}
    function unlockStake() external {}
    function withdrawStake(address payable) external {}
    
    // Define UserOpsPerAggregator struct for mock
    struct UserOpsPerAggregator {
        PackedUserOperation[] userOps;
        IAggregator aggregator;
        bytes signature;
    }
    
    // Mock functions for IEntryPoint interface  
    function handleOps(PackedUserOperation[] calldata, address payable) external {}
    function handleAggregatedOps(UserOpsPerAggregator[] calldata, address payable) external {}
    
    receive() external payable {}
}

/// @title Deploy script for BasicDepositERC4337 with Mock EntryPoint for local testing
/// @author MIT-DCI
contract DeployERC4337LocalScript is Script {
    // Configuration
    string constant TOKEN_NAME = "Deposit Token ERC4337 Local";
    string constant TOKEN_SYMBOL = "DEPT4337L";
    string constant AUTHORIZATION_URI = "http://localhost:3000";
    
    // Hardhat default accounts for consistency
    address constant DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant BANK = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant WALLET1 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address constant WALLET2 = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;

    function run() external {
        console.log("=== Local ERC-4337 Deposit Token Deployment with Mock EntryPoint ===");
        console.log("");
        
        // Start broadcasting transactions
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Bank:", BANK);
        console.log("Wallet 1:", WALLET1);
        console.log("Wallet 2:", WALLET2);
        console.log("");

        // Step 1: Deploy Mock EntryPoint for local testing
        console.log("Step 1: Deploying Mock EntryPoint for local testing...");
        MockEntryPoint mockEntryPoint = new MockEntryPoint();
        console.log("Mock EntryPoint deployed to:", address(mockEntryPoint));

        // Step 2: Deploy implementation contract
        console.log("");
        console.log("Step 2: Deploying BasicDepositERC4337 implementation...");
        BasicDepositERC4337 implementation = new BasicDepositERC4337(IEntryPoint(address(mockEntryPoint)));
        console.log("Implementation deployed to:", address(implementation));

        // Step 3: Encode initialization data
        console.log("");
        console.log("Step 3: Preparing proxy initialization...");
        bytes memory initData = abi.encodeWithSelector(
            BasicDepositERC4337.initialize.selector,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            BANK,
            AUTHORIZATION_URI
        );

        // Step 4: Deploy proxy
        console.log("Step 4: Deploying UUPS proxy...");
        UUPSProxy proxy = new UUPSProxy(address(implementation), initData);
        console.log("Proxy deployed to:", address(proxy));

        // Step 5: Initialize contract through proxy
        console.log("");
        console.log("Step 5: Configuring contract...");
        BasicDepositERC4337 depositToken = BasicDepositERC4337(payable(address(proxy)));
        
        // Verify initialization
        console.log("Token name:", depositToken.name());
        console.log("Token symbol:", depositToken.symbol());
        console.log("Owner:", depositToken.owner());
        console.log("Authorization URI:", depositToken.authorizationURI());
        console.log("EntryPoint:", address(depositToken.entryPoint()));

        // Step 6: Register users
        console.log("");
        console.log("Step 6: Registering users...");
        depositToken.registerUser(WALLET1, BANK);
        console.log("Registered WALLET1 with BANK as sponsor");
        
        depositToken.registerUser(WALLET2, BANK);
        console.log("Registered WALLET2 with BANK as sponsor");

        // Step 7: Mint initial tokens
        console.log("");
        console.log("Step 7: Minting initial tokens...");
        uint256 mintAmount = 1000 ether; // 1000 tokens
        
        depositToken.mint(WALLET1, mintAmount);
        console.log("Minted 1000 tokens to WALLET1");
        
        depositToken.mint(WALLET2, mintAmount);
        console.log("Minted 1000 tokens to WALLET2");

        // Step 8: Fund the mock EntryPoint and deposit to contract
        console.log("");
        console.log("Step 8: Funding EntryPoint operations...");
        uint256 ethAmount = 2 ether; // 2 ETH for gas fees
        if (address(vm.addr(deployerPrivateKey)).balance >= ethAmount) {
            // Send ETH to the contract and deposit to EntryPoint
            depositToken.deposit{value: ethAmount}();
            console.log("Deposited 2 ETH to EntryPoint for gas operations");
            console.log("EntryPoint balance for contract:", depositToken.getDeposit() / 1e18, "ETH");
        } else {
            console.log("Insufficient ETH balance to fund EntryPoint");
        }

        // Step 9: Verify final state
        console.log("");
        console.log("Step 9: Verifying deployment...");
        console.log("Total supply:", depositToken.totalSupply() / 1e18, "tokens");
        console.log("WALLET1 balance:", depositToken.balanceOf(WALLET1) / 1e18, "tokens");
        console.log("WALLET2 balance:", depositToken.balanceOf(WALLET2) / 1e18, "tokens");
        console.log("Contract ETH balance:", address(proxy).balance / 1e18, "ETH");
        console.log("EntryPoint deposit:", depositToken.getDeposit() / 1e18, "ETH");

        vm.stopBroadcast();

        // Summary
        console.log("");
        console.log("=== Local ERC-4337 Deployment Complete ===");
        console.log("Proxy Address:", address(proxy));
        console.log("Implementation:", address(implementation));
        console.log("Mock EntryPoint:", address(mockEntryPoint));
        console.log("Bank Address:", BANK);
        console.log("Wallet 1:", WALLET1);
        console.log("Wallet 2:", WALLET2);
        console.log("");
        console.log("Environment Variables:");
        console.log("DEPOSIT_TOKEN_ADDRESS=", vm.toString(address(proxy)));
        console.log("ENTRYPOINT_ADDRESS=", vm.toString(address(mockEntryPoint)));
        console.log("BANK_ADDRESS=", vm.toString(BANK));
        console.log("WALLET_ADDRESS=", vm.toString(WALLET1));
        
        console.log("");
        console.log("=== Testing Instructions ===");
        console.log("1. This deployment uses a mock EntryPoint for local testing");
        console.log("2. For production, use DeployERC4337.s.sol with real EntryPoint");
        console.log("3. Contract supports both traditional ERC-20 and ERC-4337 operations");
        console.log("4. All regulatory features (authorization, freezing, etc.) are preserved");
    }
}