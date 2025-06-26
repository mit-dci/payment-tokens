// scripts/deploy.ts - Deploy deposit token contracts using Hardhat
import { ethers, upgrades } from "hardhat";
import { Contract } from "ethers";

async function main() {
  console.log("=== Deposit Token Deployment ===\n");

  // Get signers
  const [deployer, bankAccount, wallet1, wallet2] = await ethers.getSigners();
  
  console.log("Deployment Configuration:");
  console.log(`Deployer: ${deployer.address}`);
  console.log(`Bank: ${bankAccount.address}`);
  console.log(`Wallet 1: ${wallet1.address}`);
  console.log(`Wallet 2: ${wallet2.address}`);
  
  // Get deployer balance
  const deployerBalance = await ethers.provider.getBalance(deployer.address);
  console.log(`Deployer balance: ${ethers.formatEther(deployerBalance)} ETH\n`);

  // Contract configuration
  const TOKEN_NAME = process.env.TOKEN_NAME || "Deposit Token";
  const TOKEN_SYMBOL = process.env.TOKEN_SYMBOL || "DEPT";
  const AUTHORIZATION_URI = process.env.AUTHORIZATION_URI || "http://localhost:3000";

  try {
    // Step 1: Deploy BasicDeposit implementation
    console.log("Step 1: Deploying BasicDeposit implementation...");
    const BasicDeposit = await ethers.getContractFactory("BasicDeposit");
    
    // Deploy as upgradeable proxy
    const depositToken = await upgrades.deployProxy(
      BasicDeposit,
      [
        TOKEN_NAME,           // tokenName
        TOKEN_SYMBOL,         // tokenSymbol
        bankAccount.address,  // initialSponsor
        AUTHORIZATION_URI     // initial_uri
      ],
      {
        initializer: "initialize",
        kind: "uups"
      }
    ) as unknown as Contract;

    await depositToken.waitForDeployment();
    const proxyAddress = await depositToken.getAddress();
    
    console.log(`BasicDeposit proxy deployed to: ${proxyAddress}`);
    
    // Get implementation address
    const implementationAddress = await upgrades.erc1967.getImplementationAddress(proxyAddress);
    console.log(`Implementation deployed to: ${implementationAddress}\n`);

    // Step 2: Verify initial state
    console.log("Step 2: Verifying initial contract state...");
    const name = await depositToken.name();
    const symbol = await depositToken.symbol();
    const owner = await depositToken.owner();
    const authUri = await depositToken.authorizationURI();
    
    console.log(`Token name: ${name}`);
    console.log(`Token symbol: ${symbol}`);
    console.log(`Contract owner: ${owner}`);
    console.log(`Authorization URI: ${authUri}\n`);

    // Step 3: Register wallet accounts
    console.log("Step 3: Registering wallet accounts...");
    
    // Register wallet1 with bank as sponsor
    const tx1 = await depositToken.connect(deployer).registerUser(wallet1.address, bankAccount.address);
    await tx1.wait();
    console.log(`Registered ${wallet1.address} with sponsor ${bankAccount.address}`);
    
    // Register wallet2 with bank as sponsor
    const tx2 = await depositToken.connect(deployer).registerUser(wallet2.address, bankAccount.address);
    await tx2.wait();
    console.log(`Registered ${wallet2.address} with sponsor ${bankAccount.address}\n`);

    // Step 4: Mint initial tokens
    console.log("Step 4: Minting initial tokens...");
    const mintAmount = ethers.parseEther("1000"); // 1000 tokens
    
    // Mint to wallet1
    const mintTx1 = await depositToken.connect(deployer).mint(wallet1.address, mintAmount);
    await mintTx1.wait();
    console.log(`Minted ${ethers.formatEther(mintAmount)} tokens to ${wallet1.address}`);
    
    // Mint to wallet2
    const mintTx2 = await depositToken.connect(deployer).mint(wallet2.address, mintAmount);
    await mintTx2.wait();
    console.log(`Minted ${ethers.formatEther(mintAmount)} tokens to ${wallet2.address}\n`);

    // Step 5: Verify balances
    console.log("Step 5: Verifying balances...");
    const balance1 = await depositToken.balanceOf(wallet1.address);
    const balance2 = await depositToken.balanceOf(wallet2.address);
    const totalSupply = await depositToken.totalSupply();
    
    console.log(`${wallet1.address} balance: ${ethers.formatEther(balance1)} tokens`);
    console.log(`${wallet2.address} balance: ${ethers.formatEther(balance2)} tokens`);
    console.log(`Total supply: ${ethers.formatEther(totalSupply)} tokens\n`);

    // Step 6: Test account info
    console.log("Step 6: Testing account information...");
    const account1 = await depositToken.accounts(wallet1.address);
    console.log(`Account 1 info:`);
    console.log(`  Balance: ${ethers.formatEther(account1.balance)} tokens`);
    console.log(`  Nonce: ${account1.nonce}`);
    console.log(`  Sponsor: ${account1.sponsor}`);
    console.log(`  Frozen: ${account1.isFrozen}`);
    console.log(`  Locked Balance: ${ethers.formatEther(account1.lockedBalance)} tokens\n`);

    // Summary
    console.log("=== Deployment Complete ===");
    console.log(`Proxy Address: ${proxyAddress}`);
    console.log(`Implementation: ${implementationAddress}`);
    console.log(`Bank Address: ${bankAccount.address}`);
    console.log(`Wallet 1: ${wallet1.address} (${ethers.formatEther(balance1)} tokens)`);
    console.log(`Wallet 2: ${wallet2.address} (${ethers.formatEther(balance2)} tokens)`);
    console.log("");
    console.log("Next Steps:");
    console.log("1. Update deposit-token-sim/.env with the proxy address");
    console.log("2. Start the bank server: cd ../deposit-token-sim && npm run server");
    console.log("3. Test transfers: npm run client transfer <recipient> <amount>");
    console.log("");
    console.log("Save these addresses:");
    console.log(`DEPOSIT_TOKEN_ADDRESS=${proxyAddress}`);
    console.log(`BANK_ADDRESS=${bankAccount.address}`);
    console.log(`WALLET_ADDRESS=${wallet1.address}`);

    return {
      proxyAddress,
      implementationAddress,
      bankAddress: bankAccount.address,
      wallet1Address: wallet1.address,
      wallet2Address: wallet2.address
    };

  } catch (error) {
    console.error("Deployment failed:", error);
    throw error;
  }
}

// Run deployment
if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}

export { main as deployDepositToken };