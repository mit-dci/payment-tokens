// multi-use-server.ts - Extended bank server with multi-use authorization support
import dotenv from 'dotenv';
import express, { Request, Response } from 'express';
import bodyParser from 'body-parser';
import { ethers } from 'ethers';

// Load environment variables
dotenv.config();

const app = express();
const PORT: number = 3001; // Different port to avoid conflicts

// Bank server configuration
const BANK_PRIVATE_KEY = process.env.BANK_PRIVATE_KEY || '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
const bankWallet = new ethers.Wallet(BANK_PRIVATE_KEY);

console.log(`Multi-use Bank server address: ${bankWallet.address}`);

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

// Types for multi-use authorization
interface MultiUseAuthorization {
  sender: string;
  spendingLimit: string;
  totalLimit: string;
  expiration: string;
  authNonce: string;
  maxUses: string;
}

interface MultiUseAuthorizationRequest {
  sender: string;
  recipient: string;
  amount: string;
  totalLimit?: string;
  maxUses?: number;
  expiration?: number;
}

interface SignedAuthorizationResponse {
  authorization: string;
  signature: string;
  authHash: string;
  usageInfo: {
    maxUses: number;
    totalLimit: string;
    perTransactionLimit: string;
  };
}

// Mock database for user accounts and nonces
const userAccounts: Record<string, {
  nonce: number;
  sponsor: string;
  isRegistered: boolean;
}> = {};

// Track issued authorizations
const issuedAuthorizations: Record<string, {
  authorization: MultiUseAuthorization;
  issuedAt: number;
  maxUses: number;
  totalLimit: string;
}> = {};

// Bank server endpoints

// GET /bank/info - Get bank information
app.get('/bank/info', (_req: Request, res: Response) => {
  res.json({
    bankAddress: bankWallet.address,
    message: 'Multi-Use Payment Token Bank Authorization Server',
    features: ['multi-use-authorizations', 'usage-tracking', 'authorization-revocation'],
    endpoints: [
      'GET /bank/info - Bank information',
      'POST /bank/register - Register user account',
      'POST /bank/authorize-multiuse - Get multi-use transfer authorization',
      'GET /bank/authorization/:authHash - Get authorization info',
      'POST /bank/revoke/:authHash - Revoke authorization',
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

// POST /bank/authorize-multiuse - Create signed multi-use authorization for transfers
app.post('/bank/authorize-multiuse', async (req: Request, res: Response) => {
  try {
    const { 
      sender, 
      recipient, 
      amount, 
      totalLimit,
      maxUses = 5,
      expiration 
    }: MultiUseAuthorizationRequest = req.body;

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

    // Calculate defaults
    const authExpiration = expiration || Math.floor(Date.now() / 1000) + 3600; // 1 hour default
    const amountWei = ethers.utils.parseEther(amount);
    const calculatedTotalLimit = totalLimit 
      ? ethers.utils.parseEther(totalLimit)
      : amountWei.mul(maxUses); // Default: allow maxUses * amount

    // Create MultiUseAuthorization struct
    const authorization: MultiUseAuthorization = {
      sender: sender,
      spendingLimit: amountWei.toString(),
      totalLimit: calculatedTotalLimit.toString(),
      expiration: authExpiration.toString(),
      authNonce: senderAccount.nonce.toString(),
      maxUses: maxUses.toString()
    };

    // Encode authorization using ABI encoding
    const encodedAuth = ethers.utils.defaultAbiCoder.encode(
      ['address', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256'],
      [
        authorization.sender, 
        authorization.spendingLimit, 
        authorization.totalLimit,
        authorization.expiration, 
        authorization.authNonce,
        authorization.maxUses
      ]
    );

    // Create hash exactly like contract expects: keccak256(abi.encode(encodedAuth))
    const authHash = ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(['bytes'], [encodedAuth]));
    
    // Use raw signature to avoid message prefixing
    const sig = await bankWallet._signingKey().signDigest(authHash);
    const signature = ethers.utils.joinSignature(sig);

    // Store authorization info for tracking
    issuedAuthorizations[authHash] = {
      authorization,
      issuedAt: Date.now(),
      maxUses,
      totalLimit: ethers.utils.formatEther(calculatedTotalLimit)
    };

    const response: SignedAuthorizationResponse = {
      authorization: encodedAuth,
      signature: signature,
      authHash: authHash,
      usageInfo: {
        maxUses,
        totalLimit: ethers.utils.formatEther(calculatedTotalLimit),
        perTransactionLimit: ethers.utils.formatEther(amountWei)
      }
    };

    console.log(`Multi-use authorization created for ${sender}`);
    console.log(`Max uses: ${maxUses}, Total limit: ${ethers.utils.formatEther(calculatedTotalLimit)} ETH`);
    console.log(`Per-transaction limit: ${amount} ETH`);
    console.log(`Expiration: ${new Date(authExpiration * 1000).toISOString()}`);
    console.log(`Authorization hash: ${authHash}`);

    res.json(response);

  } catch (error) {
    console.error('Error creating multi-use authorization:', error);
    res.status(500).json({ error: 'Failed to create authorization' });
  }
});

// GET /bank/authorization/:authHash - Get authorization information
app.get('/bank/authorization/:authHash', (req: Request, res: Response) => {
  const { authHash } = req.params;
  
  const authInfo = issuedAuthorizations[authHash];
  if (!authInfo) {
    return res.status(404).json({ error: 'Authorization not found' });
  }

  const { authorization, issuedAt, maxUses, totalLimit } = authInfo;
  
  res.json({
    authHash,
    sender: authorization.sender,
    spendingLimit: ethers.utils.formatEther(authorization.spendingLimit),
    totalLimit,
    maxUses,
    expiration: new Date(parseInt(authorization.expiration) * 1000).toISOString(),
    authNonce: authorization.authNonce,
    issuedAt: new Date(issuedAt).toISOString()
  });
});

// POST /bank/revoke/:authHash - Revoke an authorization (for demonstration)
app.post('/bank/revoke/:authHash', (req: Request, res: Response) => {
  const { authHash } = req.params;
  
  const authInfo = issuedAuthorizations[authHash];
  if (!authInfo) {
    return res.status(404).json({ error: 'Authorization not found' });
  }

  // In a real implementation, you'd call the contract's revokeAuthorization function
  // For now, just remove from our tracking
  delete issuedAuthorizations[authHash];
  
  res.json({
    message: 'Authorization revoked successfully',
    authHash
  });
});

// Legacy endpoint for compatibility with existing wallet
app.post('/bank/authorize', async (req: Request, res: Response) => {
  try {
    const { sender, recipient, amount, expiration } = req.body;

    // Convert to multi-use authorization with single use
    const multiUseRequest: MultiUseAuthorizationRequest = {
      sender,
      recipient,
      amount,
      maxUses: 1,
      totalLimit: amount,
      expiration
    };

    // Reuse the multi-use authorization logic
    req.body = multiUseRequest;
    return app._router.handle({ ...req, url: '/bank/authorize-multiuse', path: '/bank/authorize-multiuse' }, res, () => {});

  } catch (error) {
    console.error('Error creating legacy authorization:', error);
    res.status(500).json({ error: 'Failed to create authorization' });
  }
});

// Health check endpoint
app.get('/health', (_req: Request, res: Response) => {
  res.json({ 
    status: 'healthy', 
    timestamp: Date.now(),
    activeAuthorizations: Object.keys(issuedAuthorizations).length
  });
});

// Start the server
app.listen(PORT, () => {
  console.log(`=== Multi-Use Payment Token Bank Server ===`);
  console.log(`Server running at http://localhost:${PORT}`);
  console.log(`Bank address: ${bankWallet.address}`);
  console.log(`Endpoints available:`);
  console.log(`  GET  /bank/info - Bank information`);
  console.log(`  POST /bank/register - Register user`);
  console.log(`  POST /bank/authorize-multiuse - Get multi-use authorization`);
  console.log(`  GET  /bank/authorization/:authHash - Get authorization info`);
  console.log(`  POST /bank/revoke/:authHash - Revoke authorization`);
  console.log(`  GET  /bank/nonce/:address - Get nonce`);
  console.log(`  POST /bank/authorize - Legacy single-use authorization`);
  console.log(`==========================================`);
});