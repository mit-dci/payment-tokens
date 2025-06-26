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
// wallet-api.ts - Backend API for wallet frontend
const express_1 = __importDefault(require("express"));
const ethers_1 = require("ethers");
const axios_1 = __importDefault(require("axios"));
const path_1 = __importDefault(require("path"));
const router = express_1.default.Router();
// Configuration
const BANK_SERVER_URL = process.env.BANK_SERVER_URL || 'http://localhost:3000';
const RPC_URL = process.env.RPC_URL || 'http://localhost:8545';
const DEPOSIT_TOKEN_ADDRESS = process.env.DEPOSIT_TOKEN_ADDRESS || '0x5FbDB2315678afecb367f032d93F642f64180aa3';
// Wallet private keys (in production, these would be managed securely)
const DEMO_WALLETS = {
    'account1': '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a',
    'account2': '0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6',
    'account3': '0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926'
};
// Simple ABI for deposit token contract
const DEPOSIT_TOKEN_ABI = [
    "function transferWithAuthorization(address to, uint256 amount, (bytes authorization, bytes signature) calldata signedAuth) external",
    "function balanceOf(address account) external view returns (uint256)",
    "function registerUser(address user, address sponsor) external",
    "function isRegistered(address user) external view returns (bool)",
    "function accounts(address user) external view returns (uint256 balance, uint256 nonce, address sponsor, bool frozen, uint256 lockedBalance)",
    "function totalSupply() external view returns (uint256)"
];
// Create wallet instances
const wallets = {};
// Initialize wallets
function initializeWallets() {
    const provider = new ethers_1.ethers.providers.JsonRpcProvider(RPC_URL);
    Object.entries(DEMO_WALLETS).forEach(([name, privateKey]) => {
        const wallet = new ethers_1.ethers.Wallet(privateKey, provider);
        const contract = new ethers_1.ethers.Contract(DEPOSIT_TOKEN_ADDRESS, DEPOSIT_TOKEN_ABI, wallet);
        wallets[name] = { provider, wallet, contract };
    });
}
// Initialize wallets on startup
initializeWallets();
// Serve wallet frontend
router.get('/', (req, res) => {
    res.sendFile(path_1.default.join(__dirname, '../wallet.html'));
});
// Get available accounts
router.get('/accounts', (req, res) => {
    const accounts = Object.entries(wallets).map(([name, wallet]) => ({
        name,
        address: wallet.wallet.address
    }));
    res.json({ accounts });
});
// Get account info
router.get('/accounts/:account', (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    try {
        const { account } = req.params;
        const wallet = wallets[account];
        if (!wallet) {
            return res.status(404).json({ error: 'Account not found' });
        }
        // Get account data from contract
        const [balance, accountData, isRegistered] = yield Promise.all([
            wallet.contract.balanceOf(wallet.wallet.address),
            wallet.contract.accounts(wallet.wallet.address).catch(() => null),
            wallet.contract.isRegistered(wallet.wallet.address).catch(() => false)
        ]);
        const accountInfo = {
            address: wallet.wallet.address,
            balance: ethers_1.ethers.utils.formatEther(balance),
            registered: isRegistered,
            frozen: false,
            nonce: 0,
            sponsor: '0x0000000000000000000000000000000000000000',
            lockedBalance: '0.00'
        };
        if (accountData) {
            accountInfo.nonce = accountData.nonce.toNumber();
            accountInfo.sponsor = accountData.sponsor;
            accountInfo.frozen = accountData.frozen;
            accountInfo.lockedBalance = ethers_1.ethers.utils.formatEther(accountData.lockedBalance);
        }
        res.json(accountInfo);
    }
    catch (error) {
        console.error('Error getting account info:', error);
        res.status(500).json({ error: 'Failed to get account info' });
    }
}));
// Register account with bank
router.post('/accounts/:account/register', (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    var _a;
    try {
        const { account } = req.params;
        console.log("account", account);
        const wallet = wallets[account];
        console.log("wallet", wallet);
        if (!wallet) {
            return res.status(404).json({ error: 'Account not found' });
        }
        console.log("wallet", wallet);
        // Register with bank server
        const response = yield axios_1.default.post(`${BANK_SERVER_URL}/bank/register`, {
            address: wallet.wallet.address
        });
        console.log("response", response);
        res.json({
            success: true,
            message: 'Account registered with bank',
            bankResponse: response.data
        });
    }
    catch (error) {
        console.error('Error registering account:', error);
        res.status(500).json({
            error: 'Failed to register account',
            details: ((_a = error.response) === null || _a === void 0 ? void 0 : _a.data) || error.message
        });
    }
}));
// Execute transfer
router.post('/accounts/:account/transfer', (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    var _a;
    try {
        const { account } = req.params;
        const { recipient, amount } = req.body;
        const wallet = wallets[account];
        if (!wallet) {
            return res.status(404).json({ error: 'Account not found' });
        }
        if (!recipient || !amount) {
            return res.status(400).json({ error: 'Recipient and amount are required' });
        }
        if (!ethers_1.ethers.utils.isAddress(recipient)) {
            return res.status(400).json({ error: 'Invalid recipient address' });
        }
        // Get authorization from bank
        const authResponse = yield axios_1.default.post(`${BANK_SERVER_URL}/bank/authorize`, {
            sender: wallet.wallet.address,
            recipient,
            amount
        });
        const { authorization, signature } = authResponse.data;
        // Execute transfer on contract
        const amountWei = ethers_1.ethers.utils.parseEther(amount);
        const signedAuth = { authorization, signature };
        const tx = yield wallet.contract.transferWithAuthorization(recipient, amountWei, signedAuth);
        // Wait for confirmation
        const receipt = yield tx.wait();
        res.json({
            success: true,
            transactionHash: tx.hash,
            blockNumber: receipt.blockNumber,
            gasUsed: receipt.gasUsed.toString()
        });
    }
    catch (error) {
        console.error('Error executing transfer:', error);
        res.status(500).json({
            error: 'Transfer failed',
            details: ((_a = error.response) === null || _a === void 0 ? void 0 : _a.data) || error.message
        });
    }
}));
// Get bank info
router.get('/bank/info', (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    try {
        const response = yield axios_1.default.get(`${BANK_SERVER_URL}/bank/info`);
        res.json(response.data);
    }
    catch (error) {
        console.error('Error getting bank info:', error);
        res.status(500).json({ error: 'Failed to get bank info' });
    }
}));
// Parse XML authorization
router.post('/xml/parse', (req, res) => {
    try {
        const { xmlContent } = req.body;
        if (!xmlContent) {
            return res.status(400).json({ error: 'XML content is required' });
        }
        // Parse XML and extract fields
        const fields = parseAuthorizationXml(xmlContent);
        res.json({ fields });
    }
    catch (error) {
        console.error('Error parsing XML:', error);
        res.status(500).json({ error: 'Failed to parse XML' });
    }
});
// Helper function to parse authorization XML
function parseAuthorizationXml(xmlContent) {
    try {
        // This is a simplified XML parser for demonstration
        // In production, you'd use a proper XML parser library
        const fields = [];
        // Extract common authorization fields using regex
        const patterns = {
            sender: /<sender[^>]*>([^<]+)<\/sender>/i,
            recipient: /<recipient[^>]*>([^<]+)<\/recipient>/i,
            amount: /<amount[^>]*>([^<]+)<\/amount>/i,
            expiration: /<expiration[^>]*>([^<]+)<\/expiration>/i,
            nonce: /<nonce[^>]*>([^<]+)<\/nonce>/i,
            authorization: /<authorization[^>]*>([^<]+)<\/authorization>/i,
            signature: /<signature[^>]*>([^<]+)<\/signature>/i,
            timestamp: /<timestamp[^>]*>([^<]+)<\/timestamp>/i,
            limit: /<limit[^>]*>([^<]+)<\/limit>/i
        };
        Object.entries(patterns).forEach(([fieldName, pattern]) => {
            const match = xmlContent.match(pattern);
            if (match) {
                fields.push({
                    name: fieldName,
                    value: match[1].trim(),
                    type: 'text'
                });
            }
        });
        return fields;
    }
    catch (error) {
        console.error('Error in parseAuthorizationXml:', error);
        return [];
    }
}
// Get contract info
router.get('/contract/info', (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    try {
        const wallet = wallets['account1']; // Use first account for read operations
        if (!wallet) {
            return res.status(500).json({ error: 'No wallet available' });
        }
        const totalSupply = yield wallet.contract.totalSupply();
        res.json({
            address: DEPOSIT_TOKEN_ADDRESS,
            totalSupply: ethers_1.ethers.utils.formatEther(totalSupply),
            rpcUrl: RPC_URL
        });
    }
    catch (error) {
        console.error('Error getting contract info:', error);
        res.status(500).json({ error: 'Failed to get contract info' });
    }
}));
// Health check
router.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        wallets: Object.keys(wallets).length
    });
});
exports.default = router;
