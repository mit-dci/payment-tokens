// admin-api.ts - Backend API for admin frontend
import express from 'express';
import { ethers } from 'ethers';
import path from 'path';

const router = express.Router();

// Configuration
const RPC_URL = process.env.RPC_URL || 'http://localhost:8545';
const DEPOSIT_TOKEN_ADDRESS = process.env.DEPOSIT_TOKEN_ADDRESS || '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512';

// Enhanced ABI for deposit token contract with all admin functions
const DEPOSIT_TOKEN_ABI = [
  // View functions
  "function balanceOf(address account) external view returns (uint256)",
  "function isRegistered(address user) external view returns (bool)",
  "function accounts(address user) external view returns (uint256 balance, uint256 nonce, address sponsor, bool frozen, uint256 lockedBalance)",
  "function totalSupply() external view returns (uint256)",
  "function name() external view returns (string)",
  "function symbol() external view returns (string)",
  "function decimals() external view returns (uint8)",
  "function owner() external view returns (address)",
  "function isSponsor(address sponsor) external view returns (bool)",
  
  // Admin functions - Owner only
  "function registerUser(address user, address sponsor) external",
  "function mint(address to, uint256 amount) external",
  "function supplyBurn(uint256 amount) external",
  "function setSponsor(address account, address sponsor) external",
  "function newSponsor(address sponsor) external",
  "function removeSponsor(address sponsor) external",
  "function updateAuthorizationURI(string calldata newURI) external",
  "function upgradeTo(address newImplementation) external",
  "function upgradeToAndCall(address newImplementation, bytes memory data) external payable",
  "function _authorizeUpgrade(address newImplementation) external",
  
  // OpenZeppelin Ownable functions
  "function transferOwnership(address newOwner) external",
  "function renounceOwnership() external",
  
  // OpenZeppelin Upgradeable functions
  "function proxiableUUID() external view returns (bytes32)",
  
  // ERC20 Standard functions (view functions)
  "function allowance(address owner, address spender) external view returns (uint256)",
  
  // Pausable functions (if implemented - note: currently using custom isHalted)
  "function paused() external view returns (bool)",
  "function pause() external",
  "function unpause() external",
  
  // Additional custom admin functions that might be missing
  "function redeem(address to, uint256 amount) external returns (bool)",
  
  // Admin functions - Owner or Sponsor
  "function freeze(address account) external",
  "function unfreeze(address account) external",
  "function seize(address seizeFrom, uint256 amount) external",
  "function releaseLockedBalance(address account, uint256 amount) external",
  "function seizeLockedBalance(address account, uint256 amount) external",
  "function moveAccountAddress(address currentAddress, address newAddress) external",
  
  // Events for monitoring
  "event Transfer(address indexed from, address indexed to, uint256 value)",
  "event UserRegistered(address indexed user, address indexed sponsor)",
  "event SponsorAdded(address indexed sponsor)",
  "event SponsorRemoved(address indexed sponsor)",
  "event AccountFrozen(address indexed account)",
  "event AccountUnfrozen(address indexed account)",
  "event AssetsSeized(address indexed from, uint256 amount)",
  "event LockedBalanceReleased(address indexed account, uint256 amount)",
  "event LockedBalanceSeized(address indexed account, uint256 amount)"
];

interface AdminWalletInstance {
  provider: ethers.providers.JsonRpcProvider;
  wallet: ethers.Wallet;
  contract: ethers.Contract;
}

// Store admin wallet instances
const adminWallets: { [key: string]: AdminWalletInstance } = {};

// Serve admin frontend
router.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, '../admin.html'));
});

// Import admin wallet
router.post('/import', (req, res) => {
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
    if (adminWallets[id]) {
      return res.status(400).json({ error: 'Wallet ID already exists' });
    }

    // Create wallet instance
    const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
    const wallet = new ethers.Wallet(privateKey, provider);
    const contract = new ethers.Contract(DEPOSIT_TOKEN_ADDRESS, DEPOSIT_TOKEN_ABI, wallet);
    
    // Store the admin wallet
    adminWallets[id] = { provider, wallet, contract };
    
    console.log(`Imported admin wallet ${id} with address ${wallet.address}`);
    
    res.json({ 
      success: true,
      id: id,
      address: wallet.address,
      message: 'Admin wallet imported successfully'
    });
  } catch (error: any) {
    console.error('Error importing admin wallet:', error);
    res.status(500).json({ 
      error: 'Failed to import admin wallet',
      details: error.message 
    });
  }
});

// Remove admin wallet
router.delete('/wallets/:id', (req, res) => {
  try {
    const { id } = req.params;
    
    if (!adminWallets[id]) {
      return res.status(404).json({ error: 'Admin wallet not found' });
    }
    
    delete adminWallets[id];
    
    console.log(`Removed admin wallet ${id}`);
    
    res.json({ 
      success: true,
      message: 'Admin wallet removed successfully'
    });
  } catch (error: any) {
    console.error('Error removing admin wallet:', error);
    res.status(500).json({ 
      error: 'Failed to remove admin wallet',
      details: error.message 
    });
  }
});

// Get account info for admin purposes
router.get('/account/:address', async (req, res) => {
  try {
    const { address } = req.params;
    
    if (!ethers.utils.isAddress(address)) {
      return res.status(400).json({ error: 'Invalid address format' });
    }

    // Use a temporary wallet to read contract info
    const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
    const contract = new ethers.Contract(DEPOSIT_TOKEN_ADDRESS, DEPOSIT_TOKEN_ABI, provider);

    const [balance, isRegistered] = await Promise.all([
      contract.balanceOf(address),
      contract.isRegistered(address)
    ]);

    let accountInfo: any = {
      address,
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
        const accountData = await contract.accounts(address);
        accountInfo.nonce = accountData.nonce.toNumber();
        accountInfo.sponsor = accountData.sponsor;
        accountInfo.frozen = accountData.frozen;
        accountInfo.lockedBalance = ethers.utils.formatEther(accountData.lockedBalance);
      } catch (error) {
        console.log('Could not fetch detailed account data:', (error as Error).message);
      }
    }

    res.json(accountInfo);
  } catch (error: any) {
    console.error('Error getting account info:', error);
    res.status(500).json({ 
      error: 'Failed to get account info',
      details: error.message 
    });
  }
});

// Get contract info
router.get('/contract/info', async (req, res) => {
  try {
    // Use a temporary wallet to read contract info
    const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
    const contract = new ethers.Contract(DEPOSIT_TOKEN_ADDRESS, DEPOSIT_TOKEN_ABI, provider);

    const [name, symbol, decimals, totalSupply, owner] = await Promise.all([
      contract.name(),
      contract.symbol(),
      contract.decimals(),
      contract.totalSupply(),
      contract.owner()
    ]);
    
    res.json({
      address: DEPOSIT_TOKEN_ADDRESS,
      name,
      symbol,
      decimals,
      totalSupply: ethers.utils.formatEther(totalSupply),
      owner,
      rpcUrl: RPC_URL,
      networkId: await provider.getNetwork().then(n => n.chainId),
      blockNumber: await provider.getBlockNumber()
    });
  } catch (error: any) {
    console.error('Error getting contract info:', error);
    res.status(500).json({ 
      error: 'Failed to get contract info',
      details: error.message 
    });
  }
});

// Helper function to execute admin functions
async function executeAdminFunction(
  adminWalletId: string, 
  functionName: string, 
  args: any[], 
  description: string
): Promise<any> {
  const adminWallet = adminWallets[adminWalletId];
  if (!adminWallet) {
    throw new Error('Admin wallet not found');
  }

  console.log(`Executing ${functionName} with args:`, args);
  
  const tx = await adminWallet.contract[functionName](...args);
  console.log(`${description} transaction submitted: ${tx.hash}`);
  
  const receipt = await tx.wait();
  console.log(`${description} confirmed in block ${receipt.blockNumber}`);
  
  return {
    success: true,
    transactionHash: tx.hash,
    blockNumber: receipt.blockNumber,
    gasUsed: receipt.gasUsed.toString(),
    description
  };
}

// User Management Functions

// Register user
router.post('/register-user', async (req, res) => {
  try {
    const { adminWalletId, userAddress, sponsorAddress } = req.body;
    
    if (!adminWalletId || !userAddress || !sponsorAddress) {
      return res.status(400).json({ error: 'Admin wallet ID, user address, and sponsor address are required' });
    }

    if (!ethers.utils.isAddress(userAddress) || !ethers.utils.isAddress(sponsorAddress)) {
      return res.status(400).json({ error: 'Invalid address format' });
    }

    const result = await executeAdminFunction(
      adminWalletId,
      'registerUser',
      [userAddress, sponsorAddress],
      'User registration'
    );
    
    res.json(result);
  } catch (error: any) {
    console.error('Error registering user:', error);
    res.status(500).json({ 
      error: 'Failed to register user',
      details: error.reason || error.message 
    });
  }
});

// Set sponsor
router.post('/set-sponsor', async (req, res) => {
  try {
    const { adminWalletId, accountAddress, sponsorAddress } = req.body;
    
    if (!adminWalletId || !accountAddress || !sponsorAddress) {
      return res.status(400).json({ error: 'Admin wallet ID, account address, and sponsor address are required' });
    }

    if (!ethers.utils.isAddress(accountAddress) || !ethers.utils.isAddress(sponsorAddress)) {
      return res.status(400).json({ error: 'Invalid address format' });
    }

    const result = await executeAdminFunction(
      adminWalletId,
      'setSponsor',
      [accountAddress, sponsorAddress],
      'Sponsor update'
    );
    
    res.json(result);
  } catch (error: any) {
    console.error('Error setting sponsor:', error);
    res.status(500).json({ 
      error: 'Failed to set sponsor',
      details: error.reason || error.message 
    });
  }
});

// Move account
router.post('/move-account', async (req, res) => {
  try {
    const { adminWalletId, currentAddress, newAddress } = req.body;
    
    if (!adminWalletId || !currentAddress || !newAddress) {
      return res.status(400).json({ error: 'Admin wallet ID, current address, and new address are required' });
    }

    if (!ethers.utils.isAddress(currentAddress) || !ethers.utils.isAddress(newAddress)) {
      return res.status(400).json({ error: 'Invalid address format' });
    }

    const result = await executeAdminFunction(
      adminWalletId,
      'moveAccountAddress',
      [currentAddress, newAddress],
      'Account move'
    );
    
    res.json(result);
  } catch (error: any) {
    console.error('Error moving account:', error);
    res.status(500).json({ 
      error: 'Failed to move account',
      details: error.reason || error.message 
    });
  }
});

// Sponsor Management Functions

// Add sponsor
router.post('/add-sponsor', async (req, res) => {
  try {
    const { adminWalletId, sponsorAddress } = req.body;
    
    if (!adminWalletId || !sponsorAddress) {
      return res.status(400).json({ error: 'Admin wallet ID and sponsor address are required' });
    }

    if (!ethers.utils.isAddress(sponsorAddress)) {
      return res.status(400).json({ error: 'Invalid sponsor address format' });
    }

    const result = await executeAdminFunction(
      adminWalletId,
      'newSponsor',
      [sponsorAddress],
      'Sponsor addition'
    );
    
    res.json(result);
  } catch (error: any) {
    console.error('Error adding sponsor:', error);
    res.status(500).json({ 
      error: 'Failed to add sponsor',
      details: error.reason || error.message 
    });
  }
});

// Remove sponsor
router.post('/remove-sponsor', async (req, res) => {
  try {
    const { adminWalletId, sponsorAddress } = req.body;
    
    if (!adminWalletId || !sponsorAddress) {
      return res.status(400).json({ error: 'Admin wallet ID and sponsor address are required' });
    }

    if (!ethers.utils.isAddress(sponsorAddress)) {
      return res.status(400).json({ error: 'Invalid sponsor address format' });
    }

    const result = await executeAdminFunction(
      adminWalletId,
      'removeSponsor',
      [sponsorAddress],
      'Sponsor removal'
    );
    
    res.json(result);
  } catch (error: any) {
    console.error('Error removing sponsor:', error);
    res.status(500).json({ 
      error: 'Failed to remove sponsor',
      details: error.reason || error.message 
    });
  }
});

// Token Operation Functions

// Mint tokens
router.post('/mint', async (req, res) => {
  try {
    const { adminWalletId, toAddress, amount } = req.body;
    
    if (!adminWalletId || !toAddress || !amount) {
      return res.status(400).json({ error: 'Admin wallet ID, recipient address, and amount are required' });
    }

    if (!ethers.utils.isAddress(toAddress)) {
      return res.status(400).json({ error: 'Invalid recipient address format' });
    }

    if (isNaN(amount) || parseFloat(amount) <= 0) {
      return res.status(400).json({ error: 'Invalid amount' });
    }

    const amountWei = ethers.utils.parseEther(amount.toString());

    const result = await executeAdminFunction(
      adminWalletId,
      'mint',
      [toAddress, amountWei],
      'Token minting'
    );
    
    res.json({
      ...result,
      mintedTo: toAddress,
      amount: amount.toString()
    });
  } catch (error: any) {
    console.error('Error minting tokens:', error);
    res.status(500).json({ 
      error: 'Failed to mint tokens',
      details: error.reason || error.message 
    });
  }
});

// Burn tokens from supply
router.post('/burn', async (req, res) => {
  try {
    const { adminWalletId, amount } = req.body;
    
    if (!adminWalletId || !amount) {
      return res.status(400).json({ error: 'Admin wallet ID and amount are required' });
    }

    if (isNaN(amount) || parseFloat(amount) <= 0) {
      return res.status(400).json({ error: 'Invalid amount' });
    }

    const amountWei = ethers.utils.parseEther(amount.toString());

    const result = await executeAdminFunction(
      adminWalletId,
      'supplyBurn',
      [amountWei],
      'Supply burn'
    );
    
    res.json({
      ...result,
      burnedAmount: amount.toString()
    });
  } catch (error: any) {
    console.error('Error burning tokens:', error);
    res.status(500).json({ 
      error: 'Failed to burn tokens',
      details: error.reason || error.message 
    });
  }
});

// Account Control Functions

// Freeze account
router.post('/freeze', async (req, res) => {
  try {
    const { adminWalletId, accountAddress } = req.body;
    
    if (!adminWalletId || !accountAddress) {
      return res.status(400).json({ error: 'Admin wallet ID and account address are required' });
    }

    if (!ethers.utils.isAddress(accountAddress)) {
      return res.status(400).json({ error: 'Invalid account address format' });
    }

    const result = await executeAdminFunction(
      adminWalletId,
      'freeze',
      [accountAddress],
      'Account freeze'
    );
    
    res.json({
      ...result,
      frozenAccount: accountAddress
    });
  } catch (error: any) {
    console.error('Error freezing account:', error);
    res.status(500).json({ 
      error: 'Failed to freeze account',
      details: error.reason || error.message 
    });
  }
});

// Unfreeze account
router.post('/unfreeze', async (req, res) => {
  try {
    const { adminWalletId, accountAddress } = req.body;
    
    if (!adminWalletId || !accountAddress) {
      return res.status(400).json({ error: 'Admin wallet ID and account address are required' });
    }

    if (!ethers.utils.isAddress(accountAddress)) {
      return res.status(400).json({ error: 'Invalid account address format' });
    }

    const result = await executeAdminFunction(
      adminWalletId,
      'unfreeze',
      [accountAddress],
      'Account unfreeze'
    );
    
    res.json({
      ...result,
      unfrozenAccount: accountAddress
    });
  } catch (error: any) {
    console.error('Error unfreezing account:', error);
    res.status(500).json({ 
      error: 'Failed to unfreeze account',
      details: error.reason || error.message 
    });
  }
});

// Asset Seizure Functions

// Seize assets
router.post('/seize', async (req, res) => {
  try {
    const { adminWalletId, fromAddress, amount } = req.body;
    
    if (!adminWalletId || !fromAddress || !amount) {
      return res.status(400).json({ error: 'Admin wallet ID, account address, and amount are required' });
    }

    if (!ethers.utils.isAddress(fromAddress)) {
      return res.status(400).json({ error: 'Invalid account address format' });
    }

    if (isNaN(amount) || parseFloat(amount) <= 0) {
      return res.status(400).json({ error: 'Invalid amount' });
    }

    const amountWei = ethers.utils.parseEther(amount.toString());

    const result = await executeAdminFunction(
      adminWalletId,
      'seize',
      [fromAddress, amountWei],
      'Asset seizure'
    );
    
    res.json({
      ...result,
      seizedFrom: fromAddress,
      amount: amount.toString()
    });
  } catch (error: any) {
    console.error('Error seizing assets:', error);
    res.status(500).json({ 
      error: 'Failed to seize assets',
      details: error.reason || error.message 
    });
  }
});

// Release locked balance
router.post('/release-locked', async (req, res) => {
  try {
    const { adminWalletId, accountAddress, amount } = req.body;
    
    if (!adminWalletId || !accountAddress || !amount) {
      return res.status(400).json({ error: 'Admin wallet ID, account address, and amount are required' });
    }

    if (!ethers.utils.isAddress(accountAddress)) {
      return res.status(400).json({ error: 'Invalid account address format' });
    }

    if (isNaN(amount) || parseFloat(amount) <= 0) {
      return res.status(400).json({ error: 'Invalid amount' });
    }

    const amountWei = ethers.utils.parseEther(amount.toString());

    const result = await executeAdminFunction(
      adminWalletId,
      'releaseLockedBalance',
      [accountAddress, amountWei],
      'Locked balance release'
    );
    
    res.json({
      ...result,
      releasedTo: accountAddress,
      amount: amount.toString()
    });
  } catch (error: any) {
    console.error('Error releasing locked balance:', error);
    res.status(500).json({ 
      error: 'Failed to release locked balance',
      details: error.reason || error.message 
    });
  }
});

// Confiscate locked balance
router.post('/confiscate-locked', async (req, res) => {
  try {
    const { adminWalletId, accountAddress, amount } = req.body;
    
    if (!adminWalletId || !accountAddress || !amount) {
      return res.status(400).json({ error: 'Admin wallet ID, account address, and amount are required' });
    }

    if (!ethers.utils.isAddress(accountAddress)) {
      return res.status(400).json({ error: 'Invalid account address format' });
    }

    if (isNaN(amount) || parseFloat(amount) <= 0) {
      return res.status(400).json({ error: 'Invalid amount' });
    }

    const amountWei = ethers.utils.parseEther(amount.toString());

    const result = await executeAdminFunction(
      adminWalletId,
      'seizeLockedBalance',
      [accountAddress, amountWei],
      'Locked balance confiscation'
    );
    
    res.json({
      ...result,
      confiscatedFrom: accountAddress,
      amount: amount.toString()
    });
  } catch (error: any) {
    console.error('Error confiscating locked balance:', error);
    res.status(500).json({ 
      error: 'Failed to confiscate locked balance',
      details: error.reason || error.message 
    });
  }
});

// System Configuration Functions

// Update authorization URI
router.post('/update-auth-uri', async (req, res) => {
  try {
    const { adminWalletId, newUri } = req.body;
    
    if (!adminWalletId || !newUri) {
      return res.status(400).json({ error: 'Admin wallet ID and new URI are required' });
    }

    const result = await executeAdminFunction(
      adminWalletId,
      'updateAuthorizationURI',
      [newUri],
      'Authorization URI update'
    );
    
    res.json({
      ...result,
      newUri
    });
  } catch (error: any) {
    console.error('Error updating authorization URI:', error);
    res.status(500).json({ 
      error: 'Failed to update authorization URI',
      details: error.reason || error.message 
    });
  }
});

// Upgrade contract
router.post('/upgrade-contract', async (req, res) => {
  try {
    const { adminWalletId, newImplementation } = req.body;
    
    if (!adminWalletId || !newImplementation) {
      return res.status(400).json({ error: 'Admin wallet ID and new implementation address are required' });
    }

    if (!ethers.utils.isAddress(newImplementation)) {
      return res.status(400).json({ error: 'Invalid implementation address format' });
    }

    const result = await executeAdminFunction(
      adminWalletId,
      'upgradeTo',
      [newImplementation],
      'Contract upgrade'
    );
    
    res.json({
      ...result,
      newImplementation
    });
  } catch (error: any) {
    console.error('Error upgrading contract:', error);
    res.status(500).json({ 
      error: 'Failed to upgrade contract',
      details: error.reason || error.message 
    });
  }
});

// OpenZeppelin Ownable Functions

// Transfer ownership
router.post('/transfer-ownership', async (req, res) => {
  try {
    const { adminWalletId, newOwner } = req.body;
    
    if (!adminWalletId || !newOwner) {
      return res.status(400).json({ error: 'Admin wallet ID and new owner address are required' });
    }

    if (!ethers.utils.isAddress(newOwner)) {
      return res.status(400).json({ error: 'Invalid new owner address format' });
    }

    const result = await executeAdminFunction(
      adminWalletId,
      'transferOwnership',
      [newOwner],
      'Ownership transfer'
    );
    
    res.json({
      ...result,
      newOwner
    });
  } catch (error: any) {
    console.error('Error transferring ownership:', error);
    res.status(500).json({ 
      error: 'Failed to transfer ownership',
      details: error.reason || error.message 
    });
  }
});

// Renounce ownership
router.post('/renounce-ownership', async (req, res) => {
  try {
    const { adminWalletId } = req.body;
    
    if (!adminWalletId) {
      return res.status(400).json({ error: 'Admin wallet ID is required' });
    }

    const result = await executeAdminFunction(
      adminWalletId,
      'renounceOwnership',
      [],
      'Ownership renunciation'
    );
    
    res.json(result);
  } catch (error: any) {
    console.error('Error renouncing ownership:', error);
    res.status(500).json({ 
      error: 'Failed to renounce ownership',
      details: error.reason || error.message 
    });
  }
});

// Pausable Functions (if implemented)

// Pause contract
router.post('/pause', async (req, res) => {
  try {
    const { adminWalletId } = req.body;
    
    if (!adminWalletId) {
      return res.status(400).json({ error: 'Admin wallet ID is required' });
    }

    const result = await executeAdminFunction(
      adminWalletId,
      'pause',
      [],
      'Contract pause'
    );
    
    res.json(result);
  } catch (error: any) {
    console.error('Error pausing contract:', error);
    res.status(500).json({ 
      error: 'Failed to pause contract',
      details: error.reason || error.message 
    });
  }
});

// Unpause contract
router.post('/unpause', async (req, res) => {
  try {
    const { adminWalletId } = req.body;
    
    if (!adminWalletId) {
      return res.status(400).json({ error: 'Admin wallet ID is required' });
    }

    const result = await executeAdminFunction(
      adminWalletId,
      'unpause',
      [],
      'Contract unpause'
    );
    
    res.json(result);
  } catch (error: any) {
    console.error('Error unpausing contract:', error);
    res.status(500).json({ 
      error: 'Failed to unpause contract',
      details: error.reason || error.message 
    });
  }
});

// Additional Token Functions

// Redeem tokens
router.post('/redeem', async (req, res) => {
  try {
    const { adminWalletId, toAddress, amount } = req.body;
    
    if (!adminWalletId || !toAddress || !amount) {
      return res.status(400).json({ error: 'Admin wallet ID, recipient address, and amount are required' });
    }

    if (!ethers.utils.isAddress(toAddress)) {
      return res.status(400).json({ error: 'Invalid recipient address format' });
    }

    if (isNaN(amount) || parseFloat(amount) <= 0) {
      return res.status(400).json({ error: 'Invalid amount' });
    }

    const amountWei = ethers.utils.parseEther(amount.toString());

    const result = await executeAdminFunction(
      adminWalletId,
      'redeem',
      [toAddress, amountWei],
      'Token redemption'
    );
    
    res.json({
      ...result,
      redeemedTo: toAddress,
      amount: amount.toString()
    });
  } catch (error: any) {
    console.error('Error redeeming tokens:', error);
    res.status(500).json({ 
      error: 'Failed to redeem tokens',
      details: error.reason || error.message 
    });
  }
});

// Health check
router.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy',
    timestamp: new Date().toISOString(),
    adminWallets: Object.keys(adminWallets).length
  });
});

export default router;