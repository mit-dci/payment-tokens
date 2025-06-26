# Payment Token Simulation

This demo shows the complete interaction between a regulated payment token, a bank authorization server, and a wallet client. The bank acts as a sponsor that provides signed authorizations for token transfers, while the wallet client requests these authorizations and executes transfers on the blockchain.

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Wallet Client │────│   Bank Server   │────│ Payment Token   │
│   (client.ts)   │    │   (server.ts)   │    │   Contract      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │ 1. Register account   │                       │
         │──────────────────────▶│                       │
         │                       │                       │
         │ 2. Request auth       │                       │
         │──────────────────────▶│                       │
         │   (sender, to, amount)│                       │
         │                       │                       │
         │ 3. Signed auth        │                       │
         │◀──────────────────────│                       │
         │   (auth + signature)  │                       │
         │                       │                       │
         │ 4. Transfer with auth                         │
         │───────────────────────────────────────────────▶│
         │                       │                       │
```

## Components

### 1. Bank Server (`src/server.ts`)
- **Purpose**: Acts as a regulated financial institution that authorizes token transfers
- **Key endpoints**:
  - `POST /bank/register` - Register wallet addresses
  - `POST /bank/authorize` - Create signed authorizations for transfers
  - `GET /bank/nonce/:address` - Get current nonce for an address
  - `GET /bank/info` - Get bank information

### 2. Demo Wallet (`src/client.ts`)
- **Purpose**: Ethereum wallet that interacts with the payment token contract
- **Features**:
  - Request authorizations from bank
  - Execute authorized transfers on-chain
  - Check balances, account status, etc.
  - CLI interface

## Quick Start

### Prerequisites
1. Node.js installed
2. Local node running (Anvil, Hardhat, Ganache, etc.)
3. Payment token contract deployed (via. )

### Setup
```bash
# Install dependencies
npm install

# Copy environment configuration
cp .env.example .env

# Edit .env with your contract address and RPC URL
```

### Running the Demo

#### Option 1: Full automated demo
```bash
# Terminal 1: Start bank server
npm run server

# Terminal 2: Run complete demo
npm run demo
```

#### Option 2: Manual testing
```bash
# Terminal 1: Start bank server
npm run server

# Terminal 2: Test wallet commands
npm run client info                    # Show wallet and bank info
npm run client register               # Register with bank
npm run client status                 # Show wallet status
npm run client balance                # Show balance
npm run client transfer <to> <amount> # Transfer tokens
```

## Configuration

The demo uses default Hardhat development accounts:

| Role | Address | Private Key |
|------|---------|-------------|
| Bank | `0x976EA74026E726554dB657fA54763abd0C3a0aa9` | `0x7c85...07a6` |
| Wallet | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | `0x5de4...365a` |

### Environment Variables (.env)
- `BANK_PRIVATE_KEY` - Bank's signing key
- `WALLET_PRIVATE_KEY` - Wallet's private key
- `DEPOSIT_TOKEN_ADDRESS` - Deployed contract address
- `RPC_URL` - Blockchain RPC endpoint
- `BANK_SERVER_URL` - Bank server URL

## Authorization Flow

### 1. Registration
```bash
POST /bank/register
{
  "address": "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
}
```

### 2. Authorization Request
```bash
POST /bank/authorize
{
  "sender": "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
  "recipient": "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
  "amount": "1.5"
}
```

### 3. Authorization Response
```json
{
  "authorization": "0x000000000000000000000000...",
  "signature": "0x1b2c3d4e5f..."
}
```

### 4. On-chain Transfer
```solidity
transferWithAuthorization(
  to,           // recipient address
  amount,       // amount in wei
  authorization,// encoded authorization
  signature     // bank signature
)
```

## Authorization Structure

The bank creates and signs a `BasicAuthorization` struct:

```solidity
struct BasicAuthorization {
  address sender;        // Wallet address
  uint256 spendingLimit; // Maximum amount (wei)
  uint256 expiration;    // Unix timestamp
  uint256 authNonce;     // Account nonce
}
```

The authorization is:
1. ABI-encoded: `abi.encode(sender, spendingLimit, expiration, authNonce)`
2. Hashed: `keccak256(encodedAuth)`
3. Signed: `ECDSA.sign(hash, bankPrivateKey)`

## Contract Integration

To use with a deployed payment token contract:

1. **Deploy contract** with bank as owner/sponsor
2. **Register wallet** in the contract: `registerUser(walletAddress, bankAddress)`
3. **Mint tokens** to wallet: `mint(walletAddress, amount)`
4. **Set authorization URI**: `updateAuthorizationURI("http://localhost:3000")`

## Example Contract Deployment (Hardhat)

```typescript
// In your Hardhat deploy script
const DepositToken = await ethers.getContractFactory("BasicDeposit");
const token = await upgrades.deployProxy(DepositToken, [
  "Payment Token",    // name
  "DEPT",            // symbol
  bankAddress,       // initial sponsor
  "http://localhost:3000" // authorization URI
]);

// Register wallet
await token.registerUser(walletAddress, bankAddress);

// Mint initial tokens
await token.mint(walletAddress, ethers.utils.parseEther("100"));
```

## Testing

The demo includes comprehensive test suites for all components:

### Automated Test Suites
```bash
# Run all tests
npm run test:all

# Individual test suites
npm run test:bank        # Bank server endpoint tests
npm run test:wallet      # Wallet client functionality tests  
npm run test:integration # End-to-end integration tests
```

### Bank Server Tests (`test-endpoints.ts`)
Tests all RPC endpoints with various scenarios:
- Health check and info endpoints
- User registration (valid/invalid addresses)
- Nonce tracking and increment
- Authorization creation and validation
- CORS headers
- Error handling

```bash
# Test specific endpoint
npm run test:bank health     # Health check only
npm run test:bank authorize  # Authorization tests only
```

### Wallet Client Tests (`test-wallet.ts`)
Tests wallet functionality:
- Address generation and validation
- Bank server communication
- Authorization requests
- Contract interactions (skipped without blockchain)
- Error handling for invalid inputs

### Integration Tests (`test-integration.ts`)
Tests complete authorization flows:
- Full registration → authorization → nonce increment flow
- Concurrent request handling
- Authorization format validation
- Error condition handling

### Manual Testing
```bash
# Bank server API tests
curl http://localhost:3000/bank/info
curl -X POST http://localhost:3000/bank/register -H "Content-Type: application/json" -d '{"address":"0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"}'

# Wallet client tests
npm run client info
npm run client register
npm run client balance
npm run client transfer 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 1.0
```

## Security Notes

- **Development keys only**: Never use these private keys in production
- **Authorization expiration**: Authorizations expire after 1 hour by default
- **Nonce protection**: Prevents replay attacks with incrementing nonces
- **Spending limits**: Each authorization has a maximum amount limit
- **Registration required**: Both sender and recipient must be registered

## Troubleshooting

### Common Issues

1. **Account not registered**
   ```
   Error: Sender not registered with bank
   Solution: Run npm run client register
   ```

2. **Insufficient balance**
   ```
   Error: transfer amount exceeds balance
   Solution: Mint tokens to wallet address in contract
   ```

## API Reference

### Bank Server Endpoints

#### GET /bank/info
Returns bank information and available endpoints.

#### POST /bank/register
Register a wallet address with the bank.
- **Body**: `{ "address": "0x..." }`
- **Response**: Registration confirmation

#### POST /bank/authorize
Request signed authorization for transfer.
- **Body**: `{ "sender": "0x...", "recipient": "0x...", "amount": "1.5" }`
- **Response**: `{ "authorization": "0x...", "signature": "0x..." }`

#### GET /bank/nonce/:address
Get current nonce for an address.
- **Response**: `{ "address": "0x...", "nonce": 0 }`

### Wallet Client Commands

#### info
Show wallet address and bank information.

#### register
Register wallet with bank server.

#### status
Show complete wallet status including balance, nonce, sponsor.

#### balance
Show token balance only.

#### transfer <to> <amount>
Execute authorized transfer to recipient.

---

This demo provides an example of how regulated digital assets can work with off-chain authorization and on-chain verification, suitable for financial institutions requiring compliance with regulatory requirements.
It has NOT been audited, it's simply a sample that we find useful for those
interested in developing on-chain regulated assets. 
