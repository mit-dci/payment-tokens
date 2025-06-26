// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ModularDepositToken} from "../contracts/src/ModularDepositToken.sol";
import {RegulatoryValidator} from "../contracts/src/modules/RegulatoryValidator.sol";
import {ComplianceHook} from "../contracts/src/modules/ComplianceHook.sol";
import {TreasuryExecutor} from "../contracts/src/modules/TreasuryExecutor.sol";
import {UUPSProxy} from "../contracts/src/UUPSProxy.sol";

// Module type constants
uint256 constant MODULE_TYPE_VALIDATOR = 1;
uint256 constant MODULE_TYPE_EXECUTOR = 2;
uint256 constant MODULE_TYPE_HOOK = 4;

/// @title Deploy script for Modular Deposit Token with ERC-7579 modules
/// @author MIT-DCI
contract DeployModularERC7579Script is Script {
    // Configuration
    string constant TOKEN_NAME = "Modular Deposit Token";
    string constant TOKEN_SYMBOL = "MDT";
    string constant AUTHORIZATION_URI = "https://compliance.example.com/auth";
    
    // Hardhat default accounts for consistency
    address constant DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant REGULATORY_AUTHORITY = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant BANK_SPONSOR = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address constant COMPLIANCE_OFFICER = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
    address constant TREASURY_MANAGER = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65;
    address constant RISK_MANAGER = 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc;
    address constant USER1 = 0x976EA74026E726554dB657fA54763abd0C3a0aa9;
    address constant USER2 = 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955;

    function run() external {
        console.log("=== Modular ERC-7579 Deposit Token Deployment ===");
        console.log("");
        
        // Start broadcasting transactions
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Regulatory Authority:", REGULATORY_AUTHORITY);
        console.log("Bank Sponsor:", BANK_SPONSOR);
        console.log("Compliance Officer:", COMPLIANCE_OFFICER);
        console.log("Treasury Manager:", TREASURY_MANAGER);
        console.log("Risk Manager:", RISK_MANAGER);
        console.log("");

        // Step 1: Deploy core contract implementation
        console.log("Step 1: Deploying ModularDepositToken implementation...");
        ModularDepositToken implementation = new ModularDepositToken();
        console.log("Implementation deployed to:", address(implementation));

        // Step 2: Deploy proxy and initialize
        console.log("");
        console.log("Step 2: Deploying proxy and initializing...");
        bytes memory initData = abi.encodeWithSelector(
            ModularDepositToken.initialize.selector,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            BANK_SPONSOR,
            AUTHORIZATION_URI
        );
        
        UUPSProxy proxy = new UUPSProxy(address(implementation), initData);
        ModularDepositToken depositToken = ModularDepositToken(payable(address(proxy)));
        
        console.log("Proxy deployed to:", address(proxy));
        console.log("Token name:", depositToken.name());
        console.log("Token symbol:", depositToken.symbol());
        console.log("Account ID:", depositToken.accountId());

        // Step 3: Deploy modules
        console.log("");
        console.log("Step 3: Deploying ERC-7579 modules...");
        
        // Deploy Regulatory Validator
        RegulatoryValidator regulatoryValidator = new RegulatoryValidator(REGULATORY_AUTHORITY);
        console.log("Regulatory Validator deployed to:", address(regulatoryValidator));
        
        // Deploy Compliance Hook
        ComplianceHook complianceHook = new ComplianceHook(COMPLIANCE_OFFICER, REGULATORY_AUTHORITY);
        console.log("Compliance Hook deployed to:", address(complianceHook));
        
        // Deploy Treasury Executor
        TreasuryExecutor treasuryExecutor = new TreasuryExecutor(TREASURY_MANAGER, RISK_MANAGER);
        console.log("Treasury Executor deployed to:", address(treasuryExecutor));

        // Step 4: Install modules
        console.log("");
        console.log("Step 4: Installing modules...");
        
        // Install Regulatory Validator with minimal data
        depositToken.installModule(MODULE_TYPE_VALIDATOR, address(regulatoryValidator), "");
        console.log("Regulatory Validator installed");
        
        // Install Compliance Hook with minimal data
        depositToken.installModule(MODULE_TYPE_HOOK, address(complianceHook), "");
        console.log("Compliance Hook installed");
        
        // Install Treasury Executor with minimal data
        depositToken.installModule(MODULE_TYPE_EXECUTOR, address(treasuryExecutor), "");
        console.log("Treasury Executor installed");

        // Step 5: Register users and setup accounts
        console.log("");
        console.log("Step 5: Setting up user accounts...");
        
        depositToken.registerUser(USER1, BANK_SPONSOR);
        console.log("Registered USER1 with BANK_SPONSOR");
        
        depositToken.registerUser(USER2, BANK_SPONSOR);
        console.log("Registered USER2 with BANK_SPONSOR");

        // Step 6: Mint initial tokens
        console.log("");
        console.log("Step 6: Minting initial tokens...");
        
        uint256 initialMintAmount = 10000 * 1e18; // 10,000 tokens each
        
        depositToken.mint(USER1, initialMintAmount);
        console.log("Minted 10,000 tokens to USER1");
        
        depositToken.mint(USER2, initialMintAmount);
        console.log("Minted 10,000 tokens to USER2");

        // Step 7: Verify module installation and functionality
        console.log("");
        console.log("Step 7: Verifying module installation...");
        
        // Check installed modules
        address[] memory validators = depositToken.getInstalledModules(MODULE_TYPE_VALIDATOR);
        address[] memory hooks = depositToken.getInstalledModules(MODULE_TYPE_HOOK);
        address[] memory executors = depositToken.getInstalledModules(MODULE_TYPE_EXECUTOR);
        
        console.log("Installed Validators:", validators.length);
        console.log("Installed Hooks:", hooks.length);
        console.log("Installed Executors:", executors.length);
        
        // Verify module functionality
        bool validatorInstalled = depositToken.isModuleInstalled(
            MODULE_TYPE_VALIDATOR,
            address(regulatoryValidator),
            ""
        );
        console.log("Regulatory Validator properly installed:", validatorInstalled);
        
        bool hookInstalled = depositToken.isModuleInstalled(
            MODULE_TYPE_HOOK,
            address(complianceHook),
            ""
        );
        console.log("Compliance Hook properly installed:", hookInstalled);
        
        bool executorInstalled = depositToken.isModuleInstalled(
            MODULE_TYPE_EXECUTOR,
            address(treasuryExecutor),
            ""
        );
        console.log("Treasury Executor properly installed:", executorInstalled);

        // Step 8: Verify account states
        console.log("");
        console.log("Step 8: Verifying account states...");
        
        console.log("Total supply:", depositToken.totalSupply() / 1e18, "tokens");
        console.log("USER1 balance:", depositToken.balanceOf(USER1) / 1e18, "tokens");
        console.log("USER2 balance:", depositToken.balanceOf(USER2) / 1e18, "tokens");
        console.log("USER1 registered:", depositToken.isRegistered(USER1));
        console.log("USER2 registered:", depositToken.isRegistered(USER2));
        console.log("USER1 frozen:", depositToken.isFrozen(USER1));
        console.log("USER2 frozen:", depositToken.isFrozen(USER2));

        vm.stopBroadcast();

        // Summary
        console.log("");
        console.log("=== Modular ERC-7579 Deployment Complete ===");
        console.log("Core Contract (Proxy):", address(proxy));
        console.log("Implementation:", address(implementation));
        console.log("Regulatory Validator:", address(regulatoryValidator));
        console.log("Compliance Hook:", address(complianceHook));
        console.log("Treasury Executor:", address(treasuryExecutor));
        console.log("");
        console.log("Key Addresses:");
        console.log("REGULATORY_AUTHORITY=", vm.toString(REGULATORY_AUTHORITY));
        console.log("BANK_SPONSOR=", vm.toString(BANK_SPONSOR));
        console.log("COMPLIANCE_OFFICER=", vm.toString(COMPLIANCE_OFFICER));
        console.log("TREASURY_MANAGER=", vm.toString(TREASURY_MANAGER));
        console.log("RISK_MANAGER=", vm.toString(RISK_MANAGER));
        console.log("USER1=", vm.toString(USER1));
        console.log("USER2=", vm.toString(USER2));
        console.log("");
        console.log("Environment Variables:");
        console.log("MODULAR_DEPOSIT_TOKEN_ADDRESS=", vm.toString(address(proxy)));
        console.log("REGULATORY_VALIDATOR_ADDRESS=", vm.toString(address(regulatoryValidator)));
        console.log("COMPLIANCE_HOOK_ADDRESS=", vm.toString(address(complianceHook)));
        console.log("TREASURY_EXECUTOR_ADDRESS=", vm.toString(address(treasuryExecutor)));
        
        console.log("");
        console.log("=== ERC-7579 Modular Architecture Benefits ===");
        console.log("+ Modular compliance validation");
        console.log("+ Real-time transaction monitoring");
        console.log("+ Automated treasury management");
        console.log("+ Pluggable regulatory modules");
        console.log("+ Cross-institution module compatibility");
        console.log("+ Future-proof architecture");
        
        console.log("");
        console.log("Next Steps:");
        console.log("1. Test module interactions with real transactions");
        console.log("2. Configure compliance rules and risk parameters");
        console.log("3. Set up treasury operations and schedules");
        console.log("4. Integrate with external compliance systems");
        console.log("5. Deploy additional specialized modules as needed");
    }
}