"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.DepositTokenWallet = void 0;
// wallet-client.ts - Payment Token Wallet Client
const dotenv_1 = __importDefault(require("dotenv"));
const ethers_1 = require("ethers");
const axios_1 = __importDefault(require("axios"));
// Load environment variables
dotenv_1.default.config();
// Configuration
const BANK_SERVER_URL = process.env.BANK_SERVER_URL || 'http://localhost:3000';
const RPC_URL = process.env.RPC_URL || 'http://localhost:8545'; // Local blockchain
const DEPOSIT_TOKEN_ADDRESS = process.env.DEPOSIT_TOKEN_ADDRESS || '0x5FbDB2315678afecb367f032d93F642f64180aa3'; // Default hardhat deployment
const WALLET_PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY || '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a'; // Default hardhat account
// Simple ABI for payment token contract (just the functions we need)
const DEPOSIT_TOKEN_ABI = [
    "function transferWithAuthorization(address to, uint256 amount, (bytes authorization, bytes signature) calldata authorization) external",
    "function balanceOf(address account) external view returns (uint256)",
    "function registerUser(address user, address sponsor) external",
    "function isRegistered(address user) external view returns (bool)",
    "function accounts(address user) external view returns (uint256 balance, uint256 nonce, address sponsor, bool frozen, uint256 lockedBalance)"
];
class DepositTokenWallet {
    constructor() {
        this.provider = new ethers_1.ethers.providers.JsonRpcProvider(RPC_URL);
        this.wallet = new ethers_1.ethers.Wallet(WALLET_PRIVATE_KEY, this.provider);
        this.contract = new ethers_1.ethers.Contract(DEPOSIT_TOKEN_ADDRESS, DEPOSIT_TOKEN_ABI, this.wallet);
    }
    // Get wallet address
    getAddress() {
        return this.wallet.address;
    }
    // Get bank server info
    getBankInfo() {
        return __awaiter(this, void 0, void 0, function* () {
            try {
                const response = yield axios_1.default.get(`${BANK_SERVER_URL}/bank/info`);
                return response.data;
            }
            catch (error) {
                console.error('Error getting bank info:', error);
                throw error;
            }
        });
    }
    // Register with the bank
    registerWithBank() {
        return __awaiter(this, void 0, void 0, function* () {
            try {
                console.log(`Registering ${this.wallet.address} with bank...`);
                const response = yield axios_1.default.post(`${BANK_SERVER_URL}/bank/register`, {
                    address: this.wallet.address
                });
                console.log('Registration successful:', response.data);
            }
            catch (error) {
                console.error('Error registering with bank:', error);
                throw error;
            }
        });
    }
    // Check if user is registered on contract
    isRegistered() {
        return __awaiter(this, void 0, void 0, function* () {
            try {
                return yield this.contract.isRegistered(this.wallet.address);
            }
            catch (error) {
                console.error('Error checking registration:', error);
                return false;
            }
        });
    }
    // Get account info from contract
    getAccountInfo() {
        return __awaiter(this, void 0, void 0, function* () {
            try {
                const accountData = yield this.contract.accounts(this.wallet.address);
                return {
                    balance: ethers_1.ethers.utils.formatEther(accountData.balance),
                    nonce: accountData.nonce.toNumber(),
                    sponsor: accountData.sponsor,
                    frozen: accountData.frozen,
                    lockedBalance: ethers_1.ethers.utils.formatEther(accountData.lockedBalance)
                };
            }
            catch (error) {
                console.error('Error getting account info:', error);
                throw error;
            }
        });
    }
    // Get balance
    getBalance() {
        return __awaiter(this, void 0, void 0, function* () {
            try {
                const balance = yield this.contract.balanceOf(this.wallet.address);
                return ethers_1.ethers.utils.formatEther(balance);
            }
            catch (error) {
                console.error('Error getting balance:', error);
                throw error;
            }
        });
    }
    // Get authorization from bank
    getAuthorization(recipient, amount) {
        return __awaiter(this, void 0, void 0, function* () {
            try {
                const authRequest = {
                    sender: this.wallet.address,
                    recipient,
                    amount
                };
                console.log(`Requesting authorization from bank for ${amount} ETH to ${recipient}...`);
                const response = yield axios_1.default.post(`${BANK_SERVER_URL}/bank/authorize`, authRequest);
                return response.data;
            }
            catch (error) {
                console.error('Error getting authorization:', error);
                throw error;
            }
        });
    }
    // Execute authorized transfer
    transfer(recipient, amount) {
        return __awaiter(this, void 0, void 0, function* () {
            try {
                console.log(`\n=== Initiating Transfer ===`);
                console.log(`From: ${this.wallet.address}`);
                console.log(`To: ${recipient}`);
                console.log(`Amount: ${amount} ETH`);
                // Check if recipient is a valid address
                if (!ethers_1.ethers.utils.isAddress(recipient)) {
                    throw new Error('Invalid recipient address');
                }
                // Get authorization from bank
                const auth = yield this.getAuthorization(recipient, amount);
                console.log('✓ Authorization received from bank');
                // Execute transfer on contract
                console.log('Executing transfer on contract...');
                const amountWei = ethers_1.ethers.utils.parseEther(amount);
                // Construct the SignedAuthorization struct
                const signedAuth = {
                    authorization: auth.authorization,
                    signature: auth.signature
                };
                const tx = yield this.contract.transferWithAuthorization(recipient, amountWei, signedAuth);
                console.log(`✓ Transaction submitted: ${tx.hash}`);
                console.log('Waiting for confirmation...');
                const receipt = yield tx.wait();
                console.log(`✓ Transfer confirmed in block ${receipt.blockNumber}`);
                return tx.hash;
            }
            catch (error) {
                console.error('Transfer failed:', error);
                throw error;
            }
        });
    }
    // Display wallet status
    displayStatus() {
        return __awaiter(this, void 0, void 0, function* () {
            try {
                console.log(`\n=== Wallet Status ===`);
                console.log(`Address: ${this.wallet.address}`);
                const isReg = yield this.isRegistered();
                console.log(`Registered on contract: ${isReg}`);
                if (isReg) {
                    const balance = yield this.getBalance();
                    console.log(`Balance: ${balance} tokens`);
                    const accountInfo = yield this.getAccountInfo();
                    console.log(`Nonce: ${accountInfo.nonce}`);
                    console.log(`Sponsor: ${accountInfo.sponsor}`);
                    console.log(`Frozen: ${accountInfo.frozen}`);
                    console.log(`Locked Balance: ${accountInfo.lockedBalance} tokens`);
                }
                console.log(`====================\n`);
            }
            catch (error) {
                console.error('Error displaying status:', error);
            }
        });
    }
}
exports.DepositTokenWallet = DepositTokenWallet;
// CLI interface
function main() {
    return __awaiter(this, void 0, void 0, function* () {
        const wallet = new DepositTokenWallet();
        const args = process.argv.slice(2);
        try {
            if (args.length === 0) {
                console.log(`
Payment Token Wallet Client

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
                    const bankInfo = yield wallet.getBankInfo();
                    console.log(JSON.stringify(bankInfo, null, 2));
                    console.log(`\n=== Wallet Info ===`);
                    console.log(`Address: ${wallet.getAddress()}`);
                    break;
                case 'register':
                    if (args.length > 1) {
                        console.error('Usage: npm run client register');
                        try {
                            console.log(`Registering ${args[1]} with bank...`);
                            const response = yield axios_1.default.post(`${BANK_SERVER_URL}/bank/register`, {
                                address: args[1]
                            });
                            console.log('Registration successful:', response.data);
                        }
                        catch (error) {
                            console.error('Error registering with bank:', error);
                            throw error;
                        }
                        break;
                    }
                    yield wallet.registerWithBank();
                    break;
                case 'status':
                    yield wallet.displayStatus();
                    break;
                case 'balance':
                    const balance = yield wallet.getBalance();
                    console.log(`Balance: ${balance} tokens`);
                    break;
                case 'transfer':
                    if (args.length < 3) {
                        console.error('Usage: npm run client transfer <to> <amount>');
                        process.exit(1);
                    }
                    const [, recipient, amount] = args;
                    const txHash = yield wallet.transfer(recipient, amount);
                    console.log(`Transfer completed! Transaction hash: ${txHash}`);
                    break;
                default:
                    console.error(`Unknown command: ${command}`);
                    process.exit(1);
            }
        }
        catch (error) {
            console.error('Error:', error.message);
            process.exit(1);
        }
    });
}
// Run if called directly
if (require.main === module) {
    main();
}
