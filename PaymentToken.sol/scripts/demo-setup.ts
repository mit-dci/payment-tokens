// scripts/demo-setup.ts - Complete demo environment setup
import { ethers } from "hardhat";
import { deployDepositToken } from "./deploy";

async function main() {
  console.log("=== Complete Demo Environment Setup ===\n");

  try {
    // Step 1: Deploy contracts
    console.log("Step 1: Deploying deposit token contracts...");
    const deployment = await deployDepositToken();
    
    console.log("\nContracts deployed successfully!");
    console.log(`Proxy: ${deployment.proxyAddress}`);
    console.log(`Bank: ${deployment.bankAddress}`);
    console.log(`Wallet 1: ${deployment.wallet1Address}`);
    console.log(`Wallet 2: ${deployment.wallet2Address}`);

    // Step 2: Create environment file for simulation
    console.log("\nStep 2: Creating environment configuration...");
    
    const envContent = `# Auto-generated deposit token demo configuration
# Generated on ${new Date().toISOString()}

# Bank Server Configuration
BANK_PRIVATE_KEY=0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
BANK_SERVER_URL=http://localhost:3000

# Blockchain Configuration
RPC_URL=http://localhost:8545
DEPOSIT_TOKEN_ADDRESS=${deployment.proxyAddress}

# Wallet Configuration
WALLET_PRIVATE_KEY=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a

# Contract Addresses
BANK_ADDRESS=${deployment.bankAddress}
WALLET_ADDRESS=${deployment.wallet1Address}
WALLET2_ADDRESS=${deployment.wallet2Address}

# Token Configuration
TOKEN_NAME="Payment Token"
TOKEN_SYMBOL="MONY"
AUTHORIZATION_URI="http://localhost:3000"
`;

    // Write to both directories
    const fs = require('fs');
    const path = require('path');
    
    // Write to contracts directory
    fs.writeFileSync('.env', envContent);
    console.log("Created .env in contracts directory");
    
    // Write to simulation directory
    const simPath = path.join('..', 'simulation', '.env');
    fs.writeFileSync(simPath, envContent);
    console.log("Created .env in simulation directory");

    // Step 3: Test contract functionality
    console.log("\nStep 3: Testing contract functionality...");
    
    const [deployer, bank, wallet1, wallet2] = await ethers.getSigners();
    const depositToken = await ethers.getContractAt("BasicDeposit", deployment.proxyAddress);

    // Test authorization URI
    const authUri = await depositToken.authorizationURI();
    console.log(`Authorization URI: ${authUri}`);

    // Test account registration
    const isWallet1Registered = await depositToken.isRegistered(wallet1.address);
    const isWallet2Registered = await depositToken.isRegistered(wallet2.address);
    console.log(`Wallet 1 registered: ${isWallet1Registered}`);
    console.log(`Wallet 2 registered: ${isWallet2Registered}`);

    // Test balances
    const balance1 = await depositToken.balanceOf(wallet1.address);
    const balance2 = await depositToken.balanceOf(wallet2.address);
    console.log(`Wallet 1 balance: ${ethers.formatEther(balance1)} tokens`);
    console.log(`Wallet 2 balance: ${ethers.formatEther(balance2)} tokens`);

    // Step 4: Verify bank can sign authorizations (simulation)
    console.log("\n🔐 Step 4: Verifying authorization capabilities...");
    
    // Create a sample authorization (what the bank server would do)
    const sampleAuth = {
      sender: wallet1.address,
      spendingLimit: ethers.parseEther("10").toString(),
      expiration: Math.floor(Date.now() / 1000) + 3600,
      authNonce: "0"
    };

    const encodedAuth = ethers.AbiCoder.defaultAbiCoder().encode(
      ['address', 'uint256', 'uint256', 'uint256'],
      [sampleAuth.sender, sampleAuth.spendingLimit, sampleAuth.expiration, sampleAuth.authNonce]
    );

    const authHash = ethers.keccak256(encodedAuth);
    const signature = await bank.signMessage(ethers.getBytes(authHash));
    
    console.log(`Sample authorization created`);
    console.log(`  Authorization length: ${encodedAuth.length} characters`);
    console.log(`  Signature length: ${signature.length} characters`);
    console.log(`  Bank can sign`);

    // Step 5: Create quick start guide
    console.log("\nStep 5: Generating quick start guide...");
    
    const quickStartGuide = `# 🚀 Deposit Token Demo Quick Start

## Deployed Contracts
- **Proxy Address**: \`${deployment.proxyAddress}\`
- **Bank Address**: \`${deployment.bankAddress}\`
- **Wallet 1**: \`${deployment.wallet1Address}\` (1000 tokens)
- **Wallet 2**: \`${deployment.wallet2Address}\` (1000 tokens)

## Quick Commands

### Start Local Blockchain (if needed)
\`\`\`bash
npx hardhat node
\`\`\`

### Start Bank Server
\`\`\`bash
cd ../simulation
npm run server
\`\`\`

### Test Wallet Client
\`\`\`bash
cd ../simulation
npm run client info
npm run client status
npm run client transfer ${deployment.wallet2Address} 5.0
\`\`\`

### Run Tests
\`\`\`bash
cd ../simulation
npm run test:all
\`\`\`

### Run Complete Demo
\`\`\`bash
cd ../simulation
npm run demo
\`\`\`

## Contract Interactions

### Check Balance
\`\`\`bash
npx hardhat console --network localhost
> const token = await ethers.getContractAt("BasicDeposit", "${deployment.proxyAddress}")
> await token.balanceOf("${deployment.wallet1Address}")
\`\`\`

### Mint More Tokens
\`\`\`bash
npx hardhat run scripts/initialize.ts --network localhost
\`\`\`

## Troubleshooting

1. **Bank server not responding**: Make sure it's running on port 3000
2. **Contract not found**: Verify the RPC URL is correct (http://localhost:8545)
3. **Insufficient balance**: Use the initialize script to mint more tokens
4. **Authorization failed**: Check that the bank address matches in both .env files

## Generated Files
- \`.env\` - Environment configuration
- \`../simulation/.env\` - Simulation environment
- \`QUICKSTART.md\` - This guide

Happy testing! 🎉
`;

    fs.writeFileSync('QUICKSTART.md', quickStartGuide);
    console.log("Created QUICKSTART.md");

    // Final summary
    console.log("\n=== Demo Environment Ready ===");
    console.log("");
    console.log("Next Steps:");
    console.log("1. Start local blockchain (if not running): npx hardhat node");
    console.log("2. Start bank server: cd ../simulation && npm run server");
    console.log("3. Test the demo: cd ../simulation && npm run demo");
    console.log("");
    console.log("Key Information:");
    console.log(`   Contract Address: ${deployment.proxyAddress}`);
    console.log(`   Bank Address: ${deployment.bankAddress}`);
    console.log(`   Test Wallet: ${deployment.wallet1Address}`);
    console.log("");
    console.log("Documentation:");
    console.log("   - See QUICKSTART.md for detailed instructions");
    console.log("   - Environment files created in both directories");
    console.log("   - All accounts pre-registered and funded");
    console.log("");
    console.log("The complete deposit token demo is ready to use!");

    return {
      success: true,
      addresses: deployment,
      files: ['.env', '../simulation/.env', 'QUICKSTART.md']
    };

  } catch (error) {
    console.error("Demo setup failed:", error);
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

export { main as setupDemo };