// scripts/upgrade.ts - Upgrade deposit token contract
import { ethers, upgrades } from "hardhat";

async function main() {
  console.log("🔄 === Deposit Token Upgrade ===\n");

  const [deployer] = await ethers.getSigners();
  console.log(`Upgrading with account: ${deployer.address}`);

  // Get proxy address from command line or environment
  const proxyAddress = process.argv[2] || process.env.DEPOSIT_TOKEN_ADDRESS;
  
  if (!proxyAddress) {
    console.error("❌ Error: Proxy address required");
    console.log("Usage: npx hardhat run scripts/upgrade.ts --network <network> <proxy_address>");
    console.log("Or set DEPOSIT_TOKEN_ADDRESS environment variable");
    process.exit(1);
  }

  console.log(`Proxy address: ${proxyAddress}`);

  try {
    // Get current implementation
    const currentImpl = await upgrades.erc1967.getImplementationAddress(proxyAddress);
    console.log(`Current implementation: ${currentImpl}`);

    // Deploy new implementation
    console.log("\n📦 Deploying new implementation...");
    const BasicDepositV2 = await ethers.getContractFactory("BasicDeposit");
    
    const upgraded = await upgrades.upgradeProxy(proxyAddress, BasicDepositV2);
    await upgraded.waitForDeployment();

    const newImpl = await upgrades.erc1967.getImplementationAddress(proxyAddress);
    console.log(`✅ New implementation: ${newImpl}`);

    // Verify upgrade
    console.log("\n🔍 Verifying upgrade...");
    const contract = await ethers.getContractAt("BasicDeposit", proxyAddress);
    const name = await contract.name();
    const owner = await contract.owner();
    
    console.log(`Contract name: ${name}`);
    console.log(`Contract owner: ${owner}`);
    console.log(`Proxy address unchanged: ${proxyAddress}`);

    console.log("\n🎉 Upgrade complete!");
    console.log(`Proxy: ${proxyAddress}`);
    console.log(`Old implementation: ${currentImpl}`);
    console.log(`New implementation: ${newImpl}`);

  } catch (error) {
    console.error("❌ Upgrade failed:", error);
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