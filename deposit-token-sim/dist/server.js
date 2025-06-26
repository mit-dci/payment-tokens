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
// bank-server.ts - Payment Token Authorization Server
const dotenv_1 = __importDefault(require("dotenv"));
const express_1 = __importDefault(require("express"));
const body_parser_1 = __importDefault(require("body-parser"));
const ethers_1 = require("ethers");
const wallet_api_1 = __importDefault(require("./wallet-api"));
const admin_api_1 = __importDefault(require("./admin-api"));
// Load environment variables
dotenv_1.default.config();
const app = (0, express_1.default)();
const PORT = parseInt(process.env.PORT || '3000');
const RPC_URL = process.env.RPC_URL || 'http://localhost:8545';
const DEPOSIT_TOKEN_ADDRESS = process.env.DEPOSIT_TOKEN_ADDRESS || '0x5FbDB2315678afecb367f032d93F642f64180aa3';
// Bank server configuration (in production, use secure key management)
const BANK_PRIVATE_KEY = process.env.BANK_PRIVATE_KEY || '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
console.log("BANK_PRIVATE_KEY", BANK_PRIVATE_KEY);
const bankWallet = new ethers_1.ethers.Wallet(BANK_PRIVATE_KEY);
console.log(`Bank server address: ${bankWallet.address}`);
// Middleware
app.use(body_parser_1.default.json());
app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Headers', 'Content-Type');
    res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    if (req.method === 'OPTIONS') {
        res.sendStatus(200);
    }
    else {
        next();
    }
});
// Mount wallet API
app.use('/wallet', wallet_api_1.default);
// Mount admin API
app.use('/admin', admin_api_1.default);
// Mock database for user accounts and nonces
const userAccounts = {};
// Bank server endpoints
// GET /bank/info - Get bank information
app.get('/bank/info', (_req, res) => {
    res.json({
        bankAddress: bankWallet.address,
        message: 'Payment Token Bank Authorization Server',
        endpoints: [
            'GET /bank/info - Bank information',
            'POST /bank/register - Register user account',
            'POST /bank/authorize - Get transfer authorization',
            'GET /bank/nonce/:address - Get current nonce for address'
        ]
    });
});
// POST /bank/register - Register a user account with the bank as sponsor
app.post('/bank/register', (req, res) => {
    const { address } = req.body;
    if (!address || !ethers_1.ethers.utils.isAddress(address)) {
        return res.status(400).json({ error: 'Valid address required' });
    }
    userAccounts[address.toLowerCase()] = {
        nonce: 0,
        sponsor: bankWallet.address,
        isRegistered: true
    };
    res.json({
        message: 'User registered successfully',
        address,
        sponsor: bankWallet.address,
        nonce: 0
    });
});
// GET /bank/nonce/:address - Get current nonce for an address
app.get('/bank/nonce/:address', (req, res) => {
    const { address } = req.params;
    if (!ethers_1.ethers.utils.isAddress(address)) {
        return res.status(400).json({ error: 'Invalid address' });
    }
    const account = userAccounts[address.toLowerCase()];
    if (!account) {
        return res.status(404).json({ error: 'Account not registered' });
    }
    res.json({
        address,
        nonce: account.nonce
    });
});
// POST /bank/authorize - Create signed authorization for transfer
app.post('/bank/authorize', (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    try {
        const { sender, recipient, amount, nonce, expiration } = req.body;
        // Validate inputs
        if (!sender || !recipient || !amount) {
            return res.status(400).json({ error: 'sender, recipient, and amount are required' });
        }
        if (!ethers_1.ethers.utils.isAddress(sender) || !ethers_1.ethers.utils.isAddress(recipient)) {
            return res.status(400).json({ error: 'Invalid addresses' });
        }
        // Check if sender is registered
        const senderAccount = userAccounts[sender.toLowerCase()];
        if (!senderAccount) {
            return res.status(404).json({ error: 'Sender not registered with bank' });
        }
        // Create authorization expiration (default: 1 hour from now)
        const authExpiration = expiration || Math.floor(Date.now() / 1000) + 3600;
        // Create BasicAuthorization struct using CURRENT nonce (don't increment yet)
        const authorization = {
            sender: sender,
            spendingLimit: ethers_1.ethers.utils.parseEther(amount).toString(),
            expiration: authExpiration.toString(),
            authNonce: (nonce === null || nonce === void 0 ? void 0 : nonce.toString()) || senderAccount.nonce.toString()
        };
        // Encode authorization using ABI encoding
        const encodedAuth = ethers_1.ethers.utils.defaultAbiCoder.encode(['address', 'uint256', 'uint256', 'uint256'], [authorization.sender, authorization.spendingLimit, authorization.expiration, authorization.authNonce]);
        // Create hash exactly like contract expects: keccak256(abi.encode(encodedAuth))
        // The contract's getAuthorizationHash wraps the message in abi.encode
        const authHash = ethers_1.ethers.utils.keccak256(ethers_1.ethers.utils.defaultAbiCoder.encode(['bytes'], [encodedAuth]));
        // Use raw signature to avoid message prefixing
        const sig = yield bankWallet._signingKey().signDigest(authHash);
        const signature = ethers_1.ethers.utils.joinSignature(sig);
        // DON'T increment nonce here - let the contract increment it on successful transfer
        const response = {
            authorization: encodedAuth,
            signature: signature
        };
        console.log(`Authorization created for ${sender} -> ${recipient}: ${amount} ETH`);
        console.log(`Expiration: ${new Date(authExpiration * 1000).toISOString()}`);
        res.json(response);
    }
    catch (error) {
        console.error('Error creating authorization:', error);
        res.status(500).json({ error: 'Failed to create authorization' });
    }
}));
// Configuration endpoint for frontend
app.get('/config', (_req, res) => {
    res.json({
        rpcUrl: RPC_URL,
        depositTokenAddress: DEPOSIT_TOKEN_ADDRESS,
        bankServerUrl: `http://localhost:${PORT}`,
        walletApiUrl: `http://localhost:${PORT}/wallet`,
        adminApiUrl: `http://localhost:${PORT}/admin`
    });
});
// Health check endpoint
app.get('/health', (_req, res) => {
    res.json({
        status: 'healthy',
        timestamp: Date.now(),
        rpcUrl: RPC_URL,
        depositTokenAddress: DEPOSIT_TOKEN_ADDRESS
    });
});
// Start the server
app.listen(PORT, () => {
    console.log(`=== Payment Token Bank Server ===`);
    console.log(`Server running at http://localhost:${PORT}`);
    console.log(`RPC URL: ${RPC_URL}`);
    console.log(`Contract Address: ${DEPOSIT_TOKEN_ADDRESS}`);
    console.log(`Bank address: ${bankWallet.address}`);
    console.log(`Endpoints available:`);
    console.log(`  GET  /config - Server configuration`);
    console.log(`  GET  /bank/info - Bank information`);
    console.log(`  POST /bank/register - Register user`);
    console.log(`  POST /bank/authorize - Get authorization`);
    console.log(`  GET  /bank/nonce/:address - Get nonce`);
    console.log(`Wallet UI available:`);
    console.log(`  GET  /wallet - Wallet frontend`);
    console.log(`  GET  /wallet/accounts - List accounts`);
    console.log(`Admin Panel available:`);
    console.log(`  GET  /admin - Admin panel frontend`);
    console.log(`  POST /admin/import - Import admin wallet`);
    console.log(`=====================================`);
});
