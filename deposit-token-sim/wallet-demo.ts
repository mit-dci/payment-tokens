// wallet-demo.ts - Demo script for the wallet functionality
import axios from 'axios';

const WALLET_API_URL = 'http://localhost:3000/wallet';
const BANK_API_URL = 'http://localhost:3000/bank';

async function demoWallet() {
  console.log('🏦 Payment Token Wallet Demo');
  console.log('============================\n');

  try {
    // 1. Get available accounts
    console.log('1. Getting available accounts...');
    const accountsResponse = await axios.get(`${WALLET_API_URL}/accounts`);
    const accounts = accountsResponse.data.accounts;
    console.log(`   Found ${accounts.length} accounts:`);
    accounts.forEach((acc: any) => {
      console.log(`   - ${acc.name}: ${acc.address}`);
    });
    console.log();

    // 2. Get account info for first account
    const firstAccount = accounts[0];
    console.log(`2. Getting account info for ${firstAccount.name}...`);
    const accountResponse = await axios.get(`${WALLET_API_URL}/accounts/${firstAccount.name}`);
    const accountInfo = accountResponse.data;
    console.log(`   Address: ${accountInfo.address}`);
    console.log(`   Balance: ${accountInfo.balance} DTK`);
    console.log(`   Registered: ${accountInfo.registered}`);
    console.log(`   Frozen: ${accountInfo.frozen}`);
    console.log(`   Nonce: ${accountInfo.nonce}`);
    console.log();

    // 3. Register account if not registered
    if (!accountInfo.registered) {
      console.log(`3. Registering ${firstAccount.name} with bank...`);
      const registerResponse = await axios.post(`${WALLET_API_URL}/accounts/${firstAccount.name}/register`);
      console.log(`   Registration result: ${registerResponse.data.message}`);
      console.log();
    } else {
      console.log(`3. Account ${firstAccount.name} is already registered.`);
      console.log();
    }

    // 4. Get bank info
    console.log('4. Getting bank server info...');
    const bankResponse = await axios.get(`${WALLET_API_URL}/bank/info`);
    const bankInfo = bankResponse.data;
    console.log(`   Bank Address: ${bankInfo.bankAddress}`);
    console.log(`   Message: ${bankInfo.message}`);
    console.log();

    // 5. Test XML parsing
    console.log('5. Testing XML parser...');
    const sampleXml = `
      <authorization>
        <sender>${accountInfo.address}</sender>
        <recipient>0x70997970C51812dc3A010C7d01b50e0d17dc79C8</recipient>
        <amount>1.5</amount>
        <expiration>1703980800</expiration>
        <nonce>42</nonce>
        <authorization>0x1234567890abcdef</authorization>
        <signature>0xfedcba0987654321</signature>
        <timestamp>1703894400</timestamp>
        <limit>10.0</limit>
      </authorization>
    `;
    
    const xmlResponse = await axios.post(`${WALLET_API_URL}/xml/parse`, {
      xmlContent: sampleXml
    });
    
    console.log(`   Parsed ${xmlResponse.data.fields.length} fields:`);
    xmlResponse.data.fields.forEach((field: any) => {
      console.log(`   - ${field.name}: ${field.value}`);
    });
    console.log();

    // 6. Simulate transfer (if we have multiple accounts)
    if (accounts.length > 1) {
      const secondAccount = accounts[1];
      console.log(`6. Simulating transfer from ${firstAccount.name} to ${secondAccount.address}...`);
      
      try {
        const transferResponse = await axios.post(`${WALLET_API_URL}/accounts/${firstAccount.name}/transfer`, {
          recipient: secondAccount.address,
          amount: '0.1'
        });
        
        console.log(`   Transfer successful!`);
        console.log(`   Transaction Hash: ${transferResponse.data.transactionHash}`);
        console.log(`   Block Number: ${transferResponse.data.blockNumber}`);
        console.log(`   Gas Used: ${transferResponse.data.gasUsed}`);
      } catch (error: any) {
        console.log(`   Transfer failed: ${error.response?.data?.error || error.message}`);
        console.log(`   This is expected if accounts don't have sufficient balance or aren't properly set up.`);
      }
    } else {
      console.log('6. Skipping transfer demo (only one account available)');
    }

    console.log('\n✅ Wallet demo completed successfully!');
    console.log('\n🌐 Access the wallet UI at: http://localhost:3000/wallet');

  } catch (error: any) {
    console.error('❌ Demo failed:', error.response?.data || error.message);
    console.log('\n💡 Make sure the server is running with: npm run dev');
  }
}

// Run demo
if (require.main === module) {
  demoWallet();
}