// bank-server.ts - Deposit Token Authorization Server
import dotenv from 'dotenv';
import express, { Request, Response } from 'express';
import bodyParser from 'body-parser';
import { ethers } from 'ethers';
import walletApi from './wallet-api';
import adminApi from './admin-api';

// Load environment variables
dotenv.config();

const app = express();
const PORT: number = parseInt(process.env.PORT || '3000');
const RPC_URL = process.env.RPC_URL || 'http://localhost:8545';
const DEPOSIT_TOKEN_ADDRESS = process.env.DEPOSIT_TOKEN_ADDRESS || '0x5FbDB2315678afecb367f032d93F642f64180aa3';

// Bank server configuration (in production, use secure key management)
const BANK_PRIVATE_KEY = process.env.BANK_PRIVATE_KEY || '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
console.log("BANK_PRIVATE_KEY", BANK_PRIVATE_KEY);
const bankWallet = new ethers.Wallet(BANK_PRIVATE_KEY);

console.log(`Bank server address: ${bankWallet.address}`);

// Middleware
app.use(bodyParser.json());
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Headers', 'Content-Type');
  res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  if (req.method === 'OPTIONS') {
    res.sendStatus(200);
  } else {
    next();
  }
});

// Mount wallet API
app.use('/wallet', walletApi);

// Mount admin API
app.use('/admin', adminApi);

// Types for deposit token authorization
interface BasicAuthorization {
  sender: string;
  spendingLimit: string;
  expiration: string;
  authNonce: string;
}

interface AuthorizationRequest {
  sender: string;
  recipient: string;
  amount: string;
  nonce?: number;
  expiration?: number;
}

interface SignedAuthorizationResponse {
  authorization: string;
  signature: string;
}

// Mock database for user accounts and nonces
const userAccounts: Record<string, {
  nonce: number;
  sponsor: string;
  isRegistered: boolean;
}> = {};

// Bank server endpoints

// GET /bank/info - Get bank information
app.get('/bank/info', (_req: Request, res: Response) => {
  res.json({
    bankAddress: bankWallet.address,
    message: 'Deposit Token Bank Authorization Server',
    endpoints: [
      'GET /bank/info - Bank information',
      'POST /bank/register - Register user account',
      'POST /bank/authorize - Get transfer authorization',
      'GET /bank/nonce/:address - Get current nonce for address'
    ]
  });
});

// POST /bank/register - Register a user account with the bank as sponsor
app.post('/bank/register', (req: Request, res: Response) => {
  const { address } = req.body;
  
  if (!address || !ethers.utils.isAddress(address)) {
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
app.get('/bank/nonce/:address', (req: Request, res: Response) => {
  const { address } = req.params;
  
  if (!ethers.utils.isAddress(address)) {
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
app.post('/bank/authorize', async (req: Request, res: Response) => {
  try {
    const { sender, recipient, amount, nonce, expiration }: AuthorizationRequest = req.body;

    // Validate inputs
    if (!sender || !recipient || !amount) {
      return res.status(400).json({ error: 'sender, recipient, and amount are required' });
    }

    if (!ethers.utils.isAddress(sender) || !ethers.utils.isAddress(recipient)) {
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
    const authorization: BasicAuthorization = {
      sender: sender,
      spendingLimit: ethers.utils.parseEther(amount).toString(),
      expiration: authExpiration.toString(),
      authNonce: nonce?.toString() || senderAccount.nonce.toString()
    };

    // Encode authorization using ABI encoding
    const encodedAuth = ethers.utils.defaultAbiCoder.encode(
      ['address', 'uint256', 'uint256', 'uint256'],
      [authorization.sender, authorization.spendingLimit, authorization.expiration, authorization.authNonce]
    );

    // Create hash exactly like contract expects: keccak256(abi.encode(encodedAuth))
    // The contract's getAuthorizationHash wraps the message in abi.encode
    const authHash = ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(['bytes'], [encodedAuth]));
    // Use raw signature to avoid message prefixing
    const sig = await bankWallet._signingKey().signDigest(authHash);
    const signature = ethers.utils.joinSignature(sig);

    // DON'T increment nonce here - let the contract increment it on successful transfer

    const response: SignedAuthorizationResponse = {
      authorization: encodedAuth,
      signature: signature
    };

    console.log(`Authorization created for ${sender} -> ${recipient}: ${amount} ETH`);
    console.log(`Expiration: ${new Date(authExpiration * 1000).toISOString()}`);

    res.json(response);

  } catch (error) {
    console.error('Error creating authorization:', error);
    res.status(500).json({ error: 'Failed to create authorization' });
  }
});

// Configuration endpoint for frontend
app.get('/config', (_req: Request, res: Response) => {
  res.json({
    rpcUrl: RPC_URL,
    depositTokenAddress: DEPOSIT_TOKEN_ADDRESS,
    bankServerUrl: `http://localhost:${PORT}`,
    walletApiUrl: `http://localhost:${PORT}/wallet`,
    adminApiUrl: `http://localhost:${PORT}/admin`
  });
});

// Health check endpoint
app.get('/health', (_req: Request, res: Response) => {
  res.json({ 
    status: 'healthy', 
    timestamp: Date.now(),
    rpcUrl: RPC_URL,
    depositTokenAddress: DEPOSIT_TOKEN_ADDRESS
  });
});

// Start the server
app.listen(PORT, () => {
  console.log(`=== Deposit Token Bank Server ===`);
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
