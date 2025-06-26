// wallet-client.ts - Deposit Token Wallet Client
import dotenv from 'dotenv';
import { ethers } from 'ethers';
import axios from 'axios';

// Load environment variables
dotenv.config();

// Configuration
const BANK_SERVER_URL = process.env.BANK_SERVER_URL || 'http://localhost:3000';
const RPC_URL = process.env.RPC_URL || 'http://localhost:8545'; // Local blockchain
const DEPOSIT_TOKEN_ADDRESS = process.env.DEPOSIT_TOKEN_ADDRESS || '0x5FbDB2315678afecb367f032d93F642f64180aa3'; // Default hardhat deployment
const WALLET_PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY || '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a'; // Default hardhat account

// Simple ABI for deposit token contract (just the functions we need)
const DEPOSIT_TOKEN_ABI = [
  "function transferWithAuthorization(address to, uint256 amount, (bytes authorization, bytes signature) calldata authorization) external",
  "function balanceOf(address account) external view returns (uint256)",
  "function registerUser(address user, address sponsor) external",
  "function isRegistered(address user) external view returns (bool)",
  "function accounts(address user) external view returns (uint256 balance, uint256 nonce, address sponsor, bool frozen, uint256 lockedBalance)"
];

interface AuthorizationRequest {
  sender: string;
  recipient: string;
  amount: string;
  expiration?: number;
}

interface BankAuthResponse {
  authorization: string;
  signature: string;
}

interface AccountInfo {
  balance: string;
  nonce: number;
  sponsor: string;
  frozen: boolean;
  lockedBalance: string;
}

class DepositTokenWallet {
  private provider: ethers.providers.JsonRpcProvider;
  private wallet: ethers.Wallet;
  private contract: ethers.Contract;

  constructor() {
    this.provider = new ethers.providers.JsonRpcProvider(RPC_URL);
    this.wallet = new ethers.Wallet(WALLET_PRIVATE_KEY, this.provider);
    this.contract = new ethers.Contract(DEPOSIT_TOKEN_ADDRESS, DEPOSIT_TOKEN_ABI, this.wallet);
  }

  // Get wallet address
  getAddress(): string {
    return this.wallet.address;
  }

  // Get bank server info
  async getBankInfo(): Promise<any> {
    try {
      const response = await axios.get(`${BANK_SERVER_URL}/bank/info`);
      return response.data;
    } catch (error) {
      console.error('Error getting bank info:', error);
      throw error;
    }
  }

  // Register with the bank
  async registerWithBank(): Promise<void> {
    try {
      console.log(`Registering ${this.wallet.address} with bank...`);
      const response = await axios.post(`${BANK_SERVER_URL}/bank/register`, {
        address: this.wallet.address
      });
      console.log('Registration successful:', response.data);
    } catch (error) {
      console.error('Error registering with bank:', error);
      throw error;
    }
  }

  // Check if user is registered on contract
  async isRegistered(): Promise<boolean> {
    try {
      return await this.contract.isRegistered(this.wallet.address);
    } catch (error) {
      console.error('Error checking registration:', error);
      return false;
    }
  }

  // Get account info from contract
  async getAccountInfo(): Promise<AccountInfo> {
    try {
      const accountData = await this.contract.accounts(this.wallet.address);
      return {
        balance: ethers.utils.formatEther(accountData.balance),
        nonce: accountData.nonce.toNumber(),
        sponsor: accountData.sponsor,
        frozen: accountData.frozen,
        lockedBalance: ethers.utils.formatEther(accountData.lockedBalance)
      };
    } catch (error) {
      console.error('Error getting account info:', error);
      throw error;
    }
  }

  // Get balance
  async getBalance(): Promise<string> {
    try {
      const balance = await this.contract.balanceOf(this.wallet.address);
      return ethers.utils.formatEther(balance);
    } catch (error) {
      console.error('Error getting balance:', error);
      throw error;
    }
  }

  // Get authorization from bank
  async getAuthorization(recipient: string, amount: string): Promise<BankAuthResponse> {
    try {
      const authRequest: AuthorizationRequest = {
        sender: this.wallet.address,
        recipient,
        amount
      };

      console.log(`Requesting authorization from bank for ${amount} ETH to ${recipient}...`);
      const response = await axios.post(`${BANK_SERVER_URL}/bank/authorize`, authRequest);
      return response.data;
    } catch (error) {
      console.error('Error getting authorization:', error);
      throw error;
    }
  }

  // Execute authorized transfer
  async transfer(recipient: string, amount: string): Promise<string> {
    try {
      console.log(`\n=== Initiating Transfer ===`);
      console.log(`From: ${this.wallet.address}`);
      console.log(`To: ${recipient}`);
      console.log(`Amount: ${amount} ETH`);

      // Check if recipient is a valid address
      if (!ethers.utils.isAddress(recipient)) {
        throw new Error('Invalid recipient address');
      }

      // Get authorization from bank
      const auth = await this.getAuthorization(recipient, amount);
      console.log('✓ Authorization received from bank');

      // Execute transfer on contract
      console.log('Executing transfer on contract...');
      const amountWei = ethers.utils.parseEther(amount);
      
      // Construct the SignedAuthorization struct
      const signedAuth = {
        authorization: auth.authorization,
        signature: auth.signature
      };

      const tx = await this.contract.transferWithAuthorization(
        recipient,
        amountWei,
        signedAuth
      );

      console.log(`✓ Transaction submitted: ${tx.hash}`);
      console.log('Waiting for confirmation...');

      const receipt = await tx.wait();
      console.log(`✓ Transfer confirmed in block ${receipt.blockNumber}`);
      
      return tx.hash;
    } catch (error) {
      console.error('Transfer failed:', error);
      throw error;
    }
  }

  // Display wallet status
  async displayStatus(): Promise<void> {
    try {
      console.log(`\n=== Wallet Status ===`);
      console.log(`Address: ${this.wallet.address}`);
      
      const isReg = await this.isRegistered();
      console.log(`Registered on contract: ${isReg}`);
      
      if (isReg) {
        const balance = await this.getBalance();
        console.log(`Balance: ${balance} tokens`);
        
        const accountInfo = await this.getAccountInfo();
        console.log(`Nonce: ${accountInfo.nonce}`);
        console.log(`Sponsor: ${accountInfo.sponsor}`);
        console.log(`Frozen: ${accountInfo.frozen}`);
        console.log(`Locked Balance: ${accountInfo.lockedBalance} tokens`);
      }
      console.log(`====================\n`);
    } catch (error) {
      console.error('Error displaying status:', error);
    }
  }
}

// CLI interface
async function main() {
  const wallet = new DepositTokenWallet();
  const args = process.argv.slice(2);

  try {
    if (args.length === 0) {
      console.log(`
Deposit Token Wallet Client

Usage:
  npm run client info                    - Show wallet and bank info
  npm run client register               - Register with bank
  npm run client status                 - Show wallet status
  npm run client balance                - Show balance
  npm run client transfer <to> <amount> - Transfer tokens

Examples:
  npm run client transfer 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 1.5
      `);
      return;
    }

    const command = args[0];

    switch (command) {
      case 'info':
        console.log('=== Bank Info ===');
        const bankInfo = await wallet.getBankInfo();
        console.log(JSON.stringify(bankInfo, null, 2));
        console.log(`\n=== Wallet Info ===`);
        console.log(`Address: ${wallet.getAddress()}`);
        break;

      case 'register':
        if (args.length > 1) {
          console.error('Usage: npm run client register');
          try {
            console.log(`Registering ${args[1]} with bank...`);
            const response = await axios.post(`${BANK_SERVER_URL}/bank/register`, {
              address: args[1]
            });
            console.log('Registration successful:', response.data);
          } catch (error) {
            console.error('Error registering with bank:', error);
            throw error;
          }
          break;
        }
        await wallet.registerWithBank();
        break;

      case 'status':
        await wallet.displayStatus();
        break;

      case 'balance':
        const balance = await wallet.getBalance();
        console.log(`Balance: ${balance} tokens`);
        break;

      case 'transfer':
        if (args.length < 3) {
          console.error('Usage: npm run client transfer <to> <amount>');
          process.exit(1);
        }
        const [, recipient, amount] = args;
        const txHash = await wallet.transfer(recipient, amount);
        console.log(`Transfer completed! Transaction hash: ${txHash}`);
        break;

      default:
        console.error(`Unknown command: ${command}`);
        process.exit(1);
    }

  } catch (error) {
    console.error('Error:', (error as Error).message);
    process.exit(1);
  }
}

// Run if called directly
if (require.main === module) {
  main();
}

export { DepositTokenWallet };