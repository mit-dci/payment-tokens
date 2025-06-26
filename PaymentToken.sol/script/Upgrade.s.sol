// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {BasicDeposit} from "../contracts/src/BasicDeposit.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title Upgrade script for BasicDeposit using Foundry
/// @author MIT-DCI
contract UpgradeScript is Script {
    function run() external {
        console.log("=== Foundry Deposit Token Upgrade ===");
        console.log("");

        // Get proxy address from environment
        address proxyAddress = vm.envAddress("DEPOSIT_TOKEN_ADDRESS");
        require(proxyAddress != address(0), "DEPOSIT_TOKEN_ADDRESS not set");
        
        console.log("Proxy address:", proxyAddress);

        // Start broadcasting
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("Upgrading with account:", vm.addr(deployerPrivateKey));

        // Connect to existing proxy
        BasicDeposit existingContract = BasicDeposit(proxyAddress);
        
        // Verify current state
        console.log("");
        console.log("Current contract state:");
        console.log("Name:", existingContract.name());
        console.log("Symbol:", existingContract.symbol());
        console.log("Owner:", existingContract.owner());

        // Deploy new implementation
        console.log("");
        console.log("Deploying new implementation...");
        BasicDeposit newImplementation = new BasicDeposit();
        console.log("New implementation deployed to:", address(newImplementation));

        // Perform upgrade
        console.log("");
        console.log("Performing upgrade...");
        existingContract.upgradeToAndCall(address(newImplementation), "");
        
        // Verify upgrade
        console.log("");
        console.log("Verifying upgrade...");
        console.log("Contract still at proxy address:", proxyAddress);
        console.log("Name after upgrade:", existingContract.name());
        console.log("Owner after upgrade:", existingContract.owner());

        vm.stopBroadcast();

        console.log("");
        console.log("=== Upgrade Complete ===");
        console.log("Proxy address (unchanged):", proxyAddress);
        console.log("New implementation:", address(newImplementation));
    }
}