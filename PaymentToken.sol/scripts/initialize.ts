// scripts/initialize.ts - Initialize and configure deployed contract
import { ethers } from "hardhat";

async function main() {
  console.log("=== Contract Initialization ===\n");

  const [deployer, bank] = await ethers.getSigners();
  
  // Get contract address from command line or environment
  const contractAddress = process.argv[2] || process.env.DEPOSIT_TOKEN_ADDRESS;
  
  if (!contractAddress) {
    console.error("Error: Contract address required");
    console.log("Usage: npx hardhat run scripts/initialize.ts --network <network> <contract_address>");
    console.log("Or set DEPOSIT_TOKEN_ADDRESS environment variable");
    process.exit(1);
  }

  console.log(`Initializing contract at: ${contractAddress}`);
  console.log(`Deployer: ${deployer.address}`);
  console.log(`Bank: ${bank.address}\n`);

  try {
    // Connect to deployed contract
    const depositToken = await ethers.getContractAt("BasicDeposit", contractAddress);

    // Configuration
    const wallets = [
      process.env.WALLET_ADDRESS || "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
      "0x70997970C51812dc3A010C7d01b50e0d17dc79C8", // Hardhat account #1
      "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC", // Hardhat account #2
    ];

    // Step 1: Register wallets
    console.log("👤 Step 1: Registering wallet addresses...");
    
    for (const walletAddress of wallets) {
      try {
        const isRegistered = await depositToken.isRegistered(walletAddress);
        if (!isRegistered) {
          const tx = await depositToken.connect(deployer).registerUser(walletAddress, bank.address);
          await tx.wait();
          console.log(`Registered ${walletAddress}`);
        } else {
          console.log(`${walletAddress} already registered`);
        }
      } catch (error: any) {
        console.log(`Failed to register ${walletAddress}: ${error.message}`);
      }
    }

    // Step 2: Mint tokens to wallets
    console.log("\nStep 2: Minting tokens to wallets...");
    const mintAmount = ethers.parseEther("100"); // 100 tokens each
    
    for (const walletAddress of wallets) {
      try {
        const currentBalance = await depositToken.balanceOf(walletAddress);
        if (currentBalance === 0n) {
          const tx = await depositToken.connect(deployer).mint(walletAddress, mintAmount);
          await tx.wait();
          console.log(`Minted ${ethers.formatEther(mintAmount)} tokens to ${walletAddress}`);
        } else {
          console.log(`${walletAddress} already has ${ethers.formatEther(currentBalance)} tokens`);
        }
      } catch (error: any) {
        console.log(`Failed to mint to ${walletAddress}: ${error.message}`);
      }
    }

    // Step 3: Set authorization URI
    console.log("\nStep 3: Setting authorization URI...");
    const authUri = process.env.AUTHORIZATION_URI || "http://localhost:3000";
    
    try {
      const currentUri = await depositToken.authorizationURI();
      if (currentUri !== authUri) {
        const tx = await depositToken.connect(deployer).updateAuthorizationURI(authUri);
        await tx.wait();
        console.log(`Authorization URI set to: ${authUri}`);
      } else {
        console.log(`Authorization URI already set to: ${authUri}`);
      }
    } catch (error: any) {
      console.log(`Failed to set authorization URI: ${error.message}`);
    }

    // Step 4: Add bank as sponsor (if not owner)
    console.log("\nStep 4: Configuring bank sponsor...");
    try {
      const owner = await depositToken.owner();
      if (owner.toLowerCase() !== bank.address.toLowerCase()) {
        // If bank is not the owner, we need to add it as a sponsor
        // This would require owner permissions, so we'll just log the requirement
        console.log(`Bank ${bank.address} should be added as sponsor by owner ${owner}`);
      } else {
        console.log(`Bank ${bank.address} is the contract owner`);
      }
    } catch (error: any) {
      console.log(`Failed to check sponsor status: ${error.message}`);
    }

    // Step 5: Display final status
    console.log("\nStep 5: Final contract status...");
    
    const totalSupply = await depositToken.totalSupply();
    const name = await depositToken.name();
    const symbol = await depositToken.symbol();
    const owner = await depositToken.owner();
    const authorizationURI = await depositToken.authorizationURI();
    
    console.log(`Token: ${name} (${symbol})`);
    console.log(`Owner: ${owner}`);
    console.log(`Total Supply: ${ethers.formatEther(totalSupply)} tokens`);
    console.log(`Authorization URI: ${authorizationURI}`);
    
    console.log("\nWallet Balances:");
    for (const walletAddress of wallets) {
      try {
        const balance = await depositToken.balanceOf(walletAddress);
        const isRegistered = await depositToken.isRegistered(walletAddress);
        console.log(`  ${walletAddress}: ${ethers.formatEther(balance)} tokens (registered: ${isRegistered})`);
      } catch (error) {
        console.log(`  ${walletAddress}: Error reading balance`);
      }
    }

    console.log("\n=== Initialization Complete ===");
    console.log("The contract is now ready for use with the deposit-token-sim!");
    console.log("\nTo test:");
    console.log("1. Start bank server: cd ../deposit-token-sim && npm run server");
    console.log("2. Update .env with contract address if needed");
    console.log("3. Test transfers: npm run client transfer <recipient> <amount>");

  } catch (error) {
    console.error("Initialization failed:", error);
    throw error;
  }
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}