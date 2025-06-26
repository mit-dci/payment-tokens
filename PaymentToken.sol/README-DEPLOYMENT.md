# Deposit Token Deployment Guide

This guide covers deployment and initialization of the deposit token contracts to Ethereum networks.

## Setup

### Prerequisites
- Node.js and npm
- Hardhat or Foundry
- Ethereum node access (local: anvil / hardhat, etc.)

### Environment Configuration
```bash
# Copy and configure environment variables
cp .env.example .env
# Edit .env with your deployment configuration
```

## 🚀 Quick Start

### Complete Demo Setup
```bash
# Start local blockchain (Terminal 1)
npm run node

# Deploy and configure everything (Terminal 2)
npm run demo-setup

# Start bank server (Terminal 3)
cd ../simulation
npm run server

# Test the demo (Terminal 4)
cd ../simulation
npm run demo
```

## Deployment

### Hardhat

#### 1. Local Network
```bash
# Start local blockchain
npm run node

# Deploy to localhost
npm run deploy:localhost

# Initialize with demo data
npm run initialize:localhost
```

### Foundry

#### 1. Local
```bash
# Set environment variables
export RPC_URL=http://localhost:8545
# Pre-seeded anvil private key
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Build contracts
npm run forge:build

# Deploy
npm run forge:deploy
```

## Individual Scripts

### Deploy Contract
```bash
# Deploy basic contract
npx hardhat run scripts/deploy.ts --network <network>

# Returns: proxy address, implementation address, configured accounts
```

### Initialize Contract
```bash
# Initialize deployed contract
DEPOSIT_TOKEN_ADDRESS=0x... npx hardhat run scripts/initialize.ts --network <network>

# Registers wallets, mints tokens, sets authorization URI
```

### Upgrade Contract
```bash
# Upgrade existing proxy
DEPOSIT_TOKEN_ADDRESS=0x... npx hardhat run scripts/upgrade.ts --network <network>

# Deploys new implementation and upgrades proxy
```

## Deployment Scripts

### `scripts/deploy.ts`
- Deploys BasicDeposit as UUPS upgradeable proxy
- Configures initial sponsor (bank)
- Registers demo wallet accounts
- Mints initial token supply
- Returns all deployment addresses

### `scripts/initialize.ts`
- Configures existing deployed contract
- Registers additional wallet addresses
- Mints tokens to registered accounts
- Sets authorization URI
- Verifies contract state

### `scripts/upgrade.ts`
- Upgrades existing proxy to new implementation
- Preserves all contract state and addresses
- Verifies upgrade success

### `scripts/demo-setup.ts`
- Complete environment setup for demo
- Deploys contracts with demo configuration
- Creates .env files for simulation
- Generates quick start guide

## Contract Architecture

### UUPS Proxy Pattern
The contracts use OpenZeppelin's UUPS (Universal Upgradeable Proxy Standard):

```
┌─────────────────┐    ┌─────────────────┐
│   UUPSProxy     │────│  BasicDeposit   │
│   (Storage)     │    │ (Implementation)│
│   (User calls)  │    │   (Logic)       │
└─────────────────┘    └─────────────────┘
```

- **Proxy**: Stores state, receives calls, delegates to implementation
- **Implementation**: Contains contract logic, stateless
- **Upgrades**: Owner can upgrade implementation while preserving state

### Deployment Process
1. Deploy implementation contract
2. Deploy proxy with initialization data
3. Register user accounts with sponsors
4. Mint initial token supply
5. Configure authorization URI

## Security Considerations

### Private Key Management
- **Development**: Uses Hardhat's default accounts
- **Production**: Use hardware wallets or secure key management
- **Environment**: Never commit real private keys

### Network Configuration
- **Local**: Hardhat node with pre-funded accounts
- **Testnet**: Use faucet ETH for deployment
- **Mainnet**: Ensure sufficient ETH for deployment and configuration

### Access Control
- **Contract Owner**: Has full administrative control
- **Sponsors**: Can authorize transactions for their users
- **Upgrade Authority**: Only owner can upgrade implementation

## Contract Verification

### Etherscan Verification
```bash
# Verify proxy contract
npx hardhat verify --network <network> <proxy_address> <constructor_args>

# Verify implementation
npx hardhat verify --network <network> <implementation_address>
```

### Manual Verification
```bash
# Check contract state
npx hardhat console --network <network>
> const token = await ethers.getContractAt("BasicDeposit", "PROXY_ADDRESS")
> await token.name()
> await token.totalSupply()
> await token.owner()
```

## Testing Deployment

### Local Testing
```bash
# Deploy locally
npm run deploy:localhost

# Test with simulation
cd ../simulation
npm run test:all
```

### Integration Testing
```bash
# Full integration test
npm run demo-setup
cd ../simulation
npm run demo
```

## Monitoring

### Events to Monitor
- `Transfer`: Token transfers
- `UserRegistered`: New user registrations
- `Upgraded`: Contract upgrades
- `AuthorizationURIUpdated`: Authorization URL changes

### Key Metrics
- Total supply
- Number of registered users
- Authorization success rate
- Contract upgrade history

### Debug Commands
```bash
# Check network connection
npx hardhat console --network localhost

# Verify contract deployment
npx hardhat verify --list-networks

# Check account balances
npx hardhat run scripts/check-balances.ts --network localhost
```
### Upgrade Script Usage
```bash
# Set environment
export DEPOSIT_TOKEN_ADDRESS=0x...

# Run upgrade
npm run upgrade:localhost
```

## Additional Resources

- [OpenZeppelin Upgrades](https://docs.openzeppelin.com/upgrades-plugins/1.x/)
- [Hardhat Documentation](https://hardhat.org/docs)
- [Foundry Documentation](https://book.getfoundry.sh/)
- [UUPS Pattern](https://eips.ethereum.org/EIPS/eip-1822)
