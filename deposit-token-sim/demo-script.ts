// demo-script.ts - Complete deposit token demo
import dotenv from 'dotenv';
import { DepositTokenWallet } from './src/client';
import axios from 'axios';

// Load environment variables
dotenv.config();

const BANK_SERVER_URL = 'http://localhost:3000';
const RECIPIENT_ADDRESS = process.env.WALLET2_ADDRESS || '0x90F79bf6EB2c4f870365E785982E1f101E93b906'; // Use second wallet as recipient

async function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function waitForBankServer(): Promise<void> {
  console.log('Waiting for bank server to be ready...');
  let attempts = 0;
  const maxAttempts = 30;
  
  while (attempts < maxAttempts) {
    try {
      await axios.get(`${BANK_SERVER_URL}/health`);
      console.log('✓ Bank server is ready');
      return;
    } catch (error) {
      attempts++;
      if (attempts === maxAttempts) {
        throw new Error('Bank server failed to start');
      }
      await sleep(1000);
    }
  }
}

async function runDemo(): Promise<void> {
  console.log('🏦 === Deposit Token Demo ===');
  console.log('This demo shows a complete flow of:');
  console.log('1. Bank server providing authorizations');
  console.log('2. Wallet client requesting and using authorizations');
  console.log('3. Executing transfers on the deposit token contract\n');

  try {
    // Wait for bank server
    await waitForBankServer();

    // Initialize wallet
    const wallet = new DepositTokenWallet();
    
    console.log('\n📋 Step 1: Getting bank and wallet info');
    console.log(`Wallet address: ${wallet.getAddress()}`);
    
    const bankInfo = await wallet.getBankInfo();
    console.log(`Bank address: ${bankInfo.bankAddress}`);

    console.log('\n📝 Step 2: Registering wallet with bank');
    await wallet.registerWithBank();
    
    console.log('\n📊 Step 3: Checking wallet status');
    await wallet.displayStatus();

    console.log('\n💰 Step 4: Checking wallet balance');
    const balance = await wallet.getBalance();
    console.log(`Current balance: ${balance} tokens`);

    console.log('\n🔄 Step 5: Attempting transfer');
    console.log(`This will request authorization from the bank and execute the transfer`);
    
    try {
      const transferAmount = '1.0';
      await wallet.transfer(RECIPIENT_ADDRESS, transferAmount);
      console.log(`✅ Transfer of ${transferAmount} tokens completed successfully!`);
    } catch (error) {
      console.log(`❌ Transfer failed (expected if contract not deployed or no balance): ${(error as Error).message}`);
    }

    console.log('\n📊 Step 6: Final wallet status');
    await wallet.displayStatus();

    console.log('\n🎉 Demo completed!');
    console.log('\nNext steps:');
    console.log('1. Deploy the deposit token contract using Hardhat/Foundry');
    console.log('2. Set the bank as a sponsor in the contract');
    console.log('3. Register the wallet address in the contract');
    console.log('4. Mint some tokens to the wallet');
    console.log('5. Run transfers with real authorizations!');

  } catch (error) {
    console.error('\n❌ Demo failed:', (error as Error).message);
    console.log('\nTroubleshooting:');
    console.log('- Make sure the bank server is running: npm run server');
    console.log('- Check that the blockchain is running (Hardhat network)');
    console.log('- Verify the contract address in .env');
  }
}

// Run demo
if (require.main === module) {
  runDemo().then(() => {
    console.log('\nDemo script finished');
    process.exit(0);
  }).catch((error) => {
    console.error('Demo script error:', error);
    process.exit(1);
  });
}

export { runDemo };