// wallet-api.ts - Backend API for wallet frontend
import express from 'express';
import { ethers } from 'ethers';
import axios from 'axios';
import path from 'path';

const router = express.Router();

// Configuration
const BANK_SERVER_URL = process.env.BANK_SERVER_URL || 'http://localhost:3000';
const RPC_URL = process.env.RPC_URL || 'http://localhost:8545';
const DEPOSIT_TOKEN_ADDRESS = process.env.DEPOSIT_TOKEN_ADDRESS || '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512';

// Wallet private keys (in production, these would be managed securely)
const DEMO_WALLETS = {
  'account1': '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a',
  'account2': '0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6',
  'account3': '0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a'
};

// Enhanced ABI for payment token contract
const DEPOSIT_TOKEN_ABI = [
  "function transferWithAuthorization(address to, uint256 amount, (bytes authorization, bytes signature) calldata signedAuth) external",
  "function transferWithMultiUseAuthorization(address to, uint256 amount, (bytes authorization, bytes signature) calldata signedAuth) external",
  "function balanceOf(address account) external view returns (uint256)",
  "function registerUser(address user, address sponsor) external",
  "function isRegistered(address user) external view returns (bool)",
  "function accounts(address user) external view returns (uint256 balance, uint256 nonce, address sponsor, bool frozen, uint256 lockedBalance)",
  "function totalSupply() external view returns (uint256)",
  "function name() external view returns (string)",
  "function symbol() external view returns (string)",
  "function decimals() external view returns (uint8)",
  "function owner() external view returns (address)",
  "function newSponsor(address sponsor) external",
  "function mint(address to, uint256 amount) external",
  "function freeze(address account) external",
  "function unfreeze(address account) external"
];

interface WalletInstance {
  provider: ethers.providers.JsonRpcProvider;
  wallet: ethers.Wallet;
  contract: ethers.Contract;
}

// Create wallet instances
const wallets: { [key: string]: WalletInstance } = {};
const customWallets: { [key: string]: WalletInstance } = {};

// Initialize wallets
function initializeWallets() {
  const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
  
  Object.entries(DEMO_WALLETS).forEach(([name, privateKey]) => {
    const wallet = new ethers.Wallet(privateKey, provider);
    const contract = new ethers.Contract(DEPOSIT_TOKEN_ADDRESS, DEPOSIT_TOKEN_ABI, wallet);
    wallets[name] = { provider, wallet, contract };
  });
}

// Initialize wallets on startup
initializeWallets();

// Serve wallet frontend
router.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, '../wallet.html'));
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
router.get('/accounts/:account', async (req, res) => {
  try {
    const { account } = req.params;
    let userAddress: string;
    let isCustomAddress = false;
    
    // Check if it's a demo account
    const wallet = wallets[account];
    if (wallet) {
      userAddress = wallet.wallet.address;
    } else {
      // Check if it's a custom wallet
      const customWallet = customWallets[account];
      if (customWallet) {
        userAddress = customWallet.wallet.address;
      } else if (ethers.utils.isAddress(account)) {
        // Handle custom address (read-only)
        userAddress = account;
        isCustomAddress = true;
      } else {
        return res.status(404).json({ error: 'Account not found' });
      }
    }

    // Use appropriate wallet for operations
    const readWallet = isCustomAddress ? wallets['account1'] : (customWallets[account] || wallet);

    // Get account data from smart contract
    const [balance, isRegistered] = await Promise.all([
      readWallet.contract.balanceOf(userAddress),
      readWallet.contract.isRegistered(userAddress)
    ]);

    let accountInfo: any = {
      address: userAddress,
      balance: ethers.utils.formatEther(balance),
      registered: isRegistered,
      frozen: false,
      nonce: 0,
      sponsor: '0x0000000000000000000000000000000000000000',
      lockedBalance: '0.00'
    };

    // If registered, get detailed account data
    if (isRegistered) {
      try {
        const accountData = await readWallet.contract.accounts(userAddress);
        accountInfo.nonce = accountData.nonce.toNumber();
        accountInfo.sponsor = accountData.sponsor;
        accountInfo.frozen = accountData.frozen;
        accountInfo.lockedBalance = ethers.utils.formatEther(accountData.lockedBalance);
      } catch (error) {
        console.log('Could not fetch detailed account data:', (error as Error).message);
      }
    }
    
    // Add note for custom addresses
    if (isCustomAddress) {
      accountInfo.isCustomAddress = true;
      accountInfo.note = 'Custom address - read-only access (cannot send transactions)';
    }

    res.json(accountInfo);
  } catch (error: any) {
    console.error('Error getting account info:', error);
    
    // Handle common blockchain errors
    let errorMessage = 'Failed to get account info';
    if (error.code === 'NETWORK_ERROR') {
      errorMessage = 'Could not connect to blockchain network';
    } else if (error.code === 'SERVER_ERROR') {
      errorMessage = 'Blockchain node error';
    }
    
    res.status(500).json({ 
      error: errorMessage,
      details: error.message 
    });
  }
});

// Register account with bank and smart contract
router.post('/accounts/:account/register', async (req, res) => {
  try {
    const { account } = req.params;
    let wallet = wallets[account];
    
    if (!wallet) {
      // Check if it's a custom wallet
      const customWallet = customWallets[account];
      if (customWallet) {
        wallet = customWallet;
      } else {
        return res.status(404).json({ error: 'Account not found' });
      }
    }

    const userAddress = wallet.wallet.address;
    
    // Step 1: Check if already registered on-chain
    const isAlreadyRegistered = await wallet.contract.isRegistered(userAddress);
    // if (isAlreadyRegistered) {
    //   return res.json({
    //     success: true,
    //     message: 'Account already registered on-chain',
    //     alreadyRegistered: true,
    //     address: userAddress
    //   });
    // }

    // Step 2: Register with bank server first to get sponsor assignment
    const bankResponse = await axios.post(`${BANK_SERVER_URL}/bank/register`, {
      address: userAddress
    });
    
    const bankSponsor = bankResponse.data.sponsor;
    console.log(`Bank assigned sponsor ${bankSponsor} for ${userAddress}`);

    if (isAlreadyRegistered) {
      return res.json({
        success: true,
        message: 'Account already registered on-chain',
        alreadyRegistered: true,
        address: userAddress
      });
    }

    // Step 3: Register on-chain with smart contract
    // Note: In a real system, the bank (contract owner) would call this
    // For demo purposes, we'll need the bank's wallet to call registerUser
    
    // Get bank wallet (this would be the contract owner in practice)
    const bankPrivateKey = process.env.BANK_PRIVATE_KEY || '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
    const bankWallet = new ethers.Wallet(bankPrivateKey, wallet.provider);
    const bankContract = wallet.contract.connect(bankWallet);
    
    console.log(`Registering ${userAddress} on-chain with sponsor ${bankSponsor}...`);
    const tx = await bankContract.registerUser(userAddress, bankSponsor);
    
    // Wait for transaction confirmation
    console.log(`Transaction submitted: ${tx.hash}`);
    const receipt = await tx.wait();
    console.log(`Registration confirmed in block ${receipt.blockNumber}`);

    res.json({ 
      success: true, 
      message: 'Account registered successfully on-chain and with bank',
      onChainRegistration: {
        transactionHash: tx.hash,
        blockNumber: receipt.blockNumber,
        gasUsed: receipt.gasUsed.toString()
      },
      bankResponse: bankResponse.data,
      address: userAddress,
      sponsor: bankSponsor
    });

  } catch (error: any) {
    console.error('Error registering account:', error);
    
    let errorMessage = 'Failed to register account';
    let errorDetails = error.message;
    
    // Handle specific blockchain errors
    if (error.code === 'CALL_EXCEPTION') {
      errorMessage = 'Smart contract call failed';
      errorDetails = error.reason || error.message;
    } else if (error.code === 'INSUFFICIENT_FUNDS') {
      errorMessage = 'Insufficient funds for gas';
      errorDetails = 'The bank wallet needs ETH for gas fees';
    } else if (error.response) {
      errorMessage = 'Bank server registration failed';
      errorDetails = error.response.data?.error || error.response.statusText;
    }
    
    res.status(500).json({ 
      error: errorMessage,
      details: errorDetails,
      code: error.code
    });
  }
});

// Execute transfer
router.post('/accounts/:account/transfer', async (req, res) => {
  try {
    const { account } = req.params;
    const { recipient, amount, useMultiUse = false, nonce, extraData } = req.body;
    
    let wallet = wallets[account];
    if (!wallet) {
      // Check if it's a custom wallet
      const customWallet = customWallets[account];
      if (customWallet) {
        wallet = customWallet;
      } else if (ethers.utils.isAddress(account)) {
        return res.status(400).json({ error: 'Cannot send transactions from custom addresses. Custom addresses are read-only.' });
      } else {
        return res.status(404).json({ error: 'Account not found' });
      }
    }

    if (!recipient || !amount) {
      return res.status(400).json({ error: 'Recipient and amount are required' });
    }

    if (!ethers.utils.isAddress(recipient)) {
      return res.status(400).json({ error: 'Invalid recipient address' });
    }

    const userAddress = wallet.wallet.address;
    
    // Check if user is registered
    const isRegistered = await wallet.contract.isRegistered(userAddress);
    if (!isRegistered) {
      return res.status(400).json({ error: 'Account must be registered before making transfers' });
    }

    // Check if recipient is registered
    const isRecipientRegistered = await wallet.contract.isRegistered(recipient);
    if (!isRecipientRegistered) {
      return res.status(400).json({ error: 'Recipient must be registered' });
    }

    // Get authorization from bank
    const authEndpoint = useMultiUse ? '/bank/authorize-multiuse' : '/bank/authorize';
    const authRequest: any = {
      sender: userAddress,
      recipient,
      amount
    };
    
    // Include nonce if provided (for synchronization with on-chain state)
    if (nonce !== undefined && nonce !== null) {
      authRequest.nonce = nonce;
      console.log(`Including nonce ${nonce} in authorization request for ${userAddress}`);
    }
    
    // Include extra data if provided
    if (extraData) {
      authRequest.extraData = extraData;
    }
    
    const authResponse = await axios.post(`${BANK_SERVER_URL}${authEndpoint}`, authRequest);

    const { authorization, signature } = authResponse.data;

    // Execute transfer on contract
    const amountWei = ethers.utils.parseEther(amount);
    const signedAuth = { authorization, signature };

    // Choose transfer function based on authorization type
    const transferFunction = useMultiUse 
      ? 'transferWithMultiUseAuthorization' 
      : 'transferWithAuthorization';

    console.log(`Executing ${transferFunction} for ${amount} tokens from ${userAddress} to ${recipient}${nonce !== undefined ? ` with nonce ${nonce}` : ''}`);
    
    const tx = await wallet.contract[transferFunction](
      recipient,
      amountWei,
      signedAuth
    );

    console.log(`Transaction submitted: ${tx.hash}`);
    
    // Wait for confirmation
    const receipt = await tx.wait();
    console.log(`Transfer confirmed in block ${receipt.blockNumber}`);

    const responseData: any = {
      success: true,
      transactionHash: tx.hash,
      blockNumber: receipt.blockNumber,
      gasUsed: receipt.gasUsed.toString(),
      transferType: useMultiUse ? 'multi-use' : 'single-use',
      from: userAddress,
      to: recipient,
      amount: amount
    };
    
    // Include nonce in response if it was provided
    if (nonce !== undefined && nonce !== null) {
      responseData.nonce = nonce;
    }
    
    // Include extra data in response if it was provided
    if (extraData) {
      responseData.extraData = extraData;
    }
    
    res.json(responseData);

  } catch (error: any) {
    console.error('Error executing transfer:', error);
    
    let errorMessage = 'Transfer failed';
    let errorDetails = error.message;
    
    // Handle specific blockchain errors
    if (error.code === 'CALL_EXCEPTION') {
      errorMessage = 'Smart contract call failed';
      errorDetails = error.reason || error.message;
    } else if (error.code === 'INSUFFICIENT_FUNDS') {
      errorMessage = 'Insufficient funds for gas or transfer';
    } else if (error.response) {
      errorMessage = 'Authorization failed';
      errorDetails = error.response.data?.error || error.response.statusText;
    }
    
    res.status(500).json({ 
      error: errorMessage,
      details: errorDetails,
      code: error.code
    });
  }
});

// Get bank info
router.get('/bank/info', async (req, res) => {
  try {
    const response = await axios.get(`${BANK_SERVER_URL}/bank/info`);
    res.json(response.data);
  } catch (error) {
    console.error('Error getting bank info:', error);
    res.status(500).json({ error: 'Failed to get bank info' });
  }
});

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
  } catch (error) {
    console.error('Error parsing XML:', error);
    res.status(500).json({ error: 'Failed to parse XML' });
  }
});

// Helper function to parse authorization XML
function parseAuthorizationXml(xmlContent: string): Array<{name: string, value: string, type: string}> {
  try {
    // This is a simplified XML parser for demonstration
    // In production, you'd use a proper XML parser library
    const fields: Array<{name: string, value: string, type: string}> = [];
    
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
  } catch (error) {
    console.error('Error in parseAuthorizationXml:', error);
    return [];
  }
}

// Get contract info
router.get('/contract/info', async (req, res) => {
  try {
    const wallet = wallets['account1']; // Use first account for read operations
    if (!wallet) {
      return res.status(500).json({ error: 'No wallet available' });
    }

    const [name, symbol, decimals, totalSupply, owner] = await Promise.all([
      wallet.contract.name(),
      wallet.contract.symbol(),
      wallet.contract.decimals(),
      wallet.contract.totalSupply(),
      wallet.contract.owner()
    ]);
    
    res.json({
      address: DEPOSIT_TOKEN_ADDRESS,
      name,
      symbol,
      decimals,
      totalSupply: ethers.utils.formatEther(totalSupply),
      owner,
      rpcUrl: RPC_URL,
      networkId: await wallet.provider.getNetwork().then(n => n.chainId),
      blockNumber: await wallet.provider.getBlockNumber()
    });
  } catch (error: any) {
    console.error('Error getting contract info:', error);
    res.status(500).json({ 
      error: 'Failed to get contract info',
      details: error.message 
    });
  }
});

// Mint tokens (for testing - only works if current account is owner)
router.post('/accounts/:account/mint', async (req, res) => {
  try {
    const { account } = req.params;
    const { amount } = req.body;
    
    let wallet = wallets[account];
    if (!wallet) {
      // Check if it's a custom wallet
      const customWallet = customWallets[account];
      if (customWallet) {
        wallet = customWallet;
      } else {
        return res.status(404).json({ error: 'Account not found' });
      }
    }

    if (!amount) {
      return res.status(400).json({ error: 'Amount is required' });
    }

    const amountWei = ethers.utils.parseEther(amount);
    const userAddress = wallet.wallet.address;

    console.log(`Minting ${amount} tokens to ${userAddress}`);
    
    const tx = await wallet.contract.mint(userAddress, amountWei);
    const receipt = await tx.wait();

    console.log(`Mint confirmed in block ${receipt.blockNumber}`);

    res.json({
      success: true,
      transactionHash: tx.hash,
      blockNumber: receipt.blockNumber,
      gasUsed: receipt.gasUsed.toString(),
      mintedTo: userAddress,
      amount: amount
    });

  } catch (error: any) {
    console.error('Error minting tokens:', error);
    
    let errorMessage = 'Mint failed';
    if (error.code === 'CALL_EXCEPTION') {
      errorMessage = 'Smart contract call failed - account may not be owner';
    }
    
    res.status(500).json({ 
      error: errorMessage,
      details: error.reason || error.message 
    });
  }
});

// Get account nonce
router.get('/accounts/:account/nonce', async (req, res) => {
  try {
    const { account } = req.params;
    let userAddress: string;
    
    // Check if it's a demo account
    const wallet = wallets[account];
    if (wallet) {
      userAddress = wallet.wallet.address;
    } else {
      // Check if it's a custom wallet
      const customWallet = customWallets[account];
      if (customWallet) {
        userAddress = customWallet.wallet.address;
      } else if (ethers.utils.isAddress(account)) {
        userAddress = account;
      } else {
        return res.status(404).json({ error: 'Account not found' });
      }
    }

    // Use appropriate wallet for operations
    const readWallet = customWallets[account] || wallet || wallets['account1'];

    // Get account nonce from smart contract
    try {
      const accountData = await readWallet.contract.accounts(userAddress);
      const nonce = accountData.nonce.toNumber();
      
      res.json({ 
        address: userAddress,
        nonce: nonce 
      });
    } catch (error) {
      // Account might not be registered
      res.json({ 
        address: userAddress,
        nonce: 0,
        note: 'Account not registered or error fetching nonce'
      });
    }
  } catch (error: any) {
    console.error('Error getting account nonce:', error);
    res.status(500).json({ 
      error: 'Failed to get account nonce',
      details: error.message 
    });
  }
});

// Derive address from private key
router.post('/derive-address', (req, res) => {
  try {
    const { privateKey } = req.body;
    
    if (!privateKey) {
      return res.status(400).json({ error: 'Private key is required' });
    }

    // Validate private key format
    const cleanKey = privateKey.replace(/^0x/, '');
    if (!/^[a-fA-F0-9]{64}$/.test(cleanKey)) {
      return res.status(400).json({ error: 'Invalid private key format' });
    }

    // Create wallet instance to derive address
    const wallet = new ethers.Wallet(privateKey);
    
    res.json({ address: wallet.address });
  } catch (error: any) {
    console.error('Error deriving address:', error);
    res.status(500).json({ 
      error: 'Failed to derive address',
      details: error.message 
    });
  }
});

// Import custom wallet
router.post('/wallets/import', (req, res) => {
  try {
    const { id, privateKey } = req.body;
    
    if (!id || !privateKey) {
      return res.status(400).json({ error: 'ID and private key are required' });
    }

    // Validate private key format
    const cleanKey = privateKey.replace(/^0x/, '');
    if (!/^[a-fA-F0-9]{64}$/.test(cleanKey)) {
      return res.status(400).json({ error: 'Invalid private key format' });
    }

    // Check if wallet ID already exists
    if (customWallets[id]) {
      return res.status(400).json({ error: 'Wallet ID already exists' });
    }

    // Create wallet instance
    const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
    const wallet = new ethers.Wallet(privateKey, provider);
    const contract = new ethers.Contract(DEPOSIT_TOKEN_ADDRESS, DEPOSIT_TOKEN_ABI, wallet);
    
    // Store the custom wallet
    customWallets[id] = { provider, wallet, contract };
    
    console.log(`Imported custom wallet ${id} with address ${wallet.address}`);
    
    res.json({ 
      success: true,
      id: id,
      address: wallet.address,
      message: 'Wallet imported successfully'
    });
  } catch (error: any) {
    console.error('Error importing wallet:', error);
    res.status(500).json({ 
      error: 'Failed to import wallet',
      details: error.message 
    });
  }
});

// Remove custom wallet
router.delete('/wallets/:id', (req, res) => {
  try {
    const { id } = req.params;
    
    if (!customWallets[id]) {
      return res.status(404).json({ error: 'Wallet not found' });
    }
    
    delete customWallets[id];
    
    console.log(`Removed custom wallet ${id}`);
    
    res.json({ 
      success: true,
      message: 'Wallet removed successfully'
    });
  } catch (error: any) {
    console.error('Error removing wallet:', error);
    res.status(500).json({ 
      error: 'Failed to remove wallet',
      details: error.message 
    });
  }
});

// Health check
router.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy',
    timestamp: new Date().toISOString(),
    wallets: Object.keys(wallets).length,
    customWallets: Object.keys(customWallets).length
  });
});

export default router;