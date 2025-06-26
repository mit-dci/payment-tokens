# Deposit Token Demo - Complete Setup Guide

A comprehensive demonstration of a regulated payment asset system with bank authorization and wallet client integration.

## 🎯 Overview

This repository demonstrates a complete **regulated deposit token ecosystem** consisting of:

- **📄 Smart Contracts** - Regulated payment asset with per-transaction authorization
- **🏦 Bank Server** - Authorization service that signs transfer approvals  
- **💼 Wallet Client** - User wallet that requests authorizations and executes transfers
- **🧪 Testing Suite** - Comprehensive tests for all components

## 🏗️ System Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Wallet Client │────│   Bank Server   │────│ Deposit Token   │
│   (TypeScript)  │    │   (Express.js)  │    │ Smart Contract  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │ 1. Register with bank │                       │
         │──────────────────────▶│                       │
         │                       │                       │
         │ 2. Request transfer   │                       │
         │    authorization      │                       │
         │──────────────────────▶│                       │
         │                       │                       │
         │ 3. Receive signed     │                       │
         │    authorization      │                       │
         │◀──────────────────────│                       │
         │                       │                       │
         │ 4. Execute transfer with authorization        │
         │───────────────────────────────────────────────▶│
         │                       │                       │
```

## 🚀 Quick Start (5 minutes)

### Prerequisites
- **Node.js** v16+ and npm
- **Git** for cloning the repository

### 1. Clone and Setup
```bash
git clone <repository-url>
cd DepositToken
```

### 2. Install Dependencies
```bash
# Install contract dependencies
cd DepositToken.sol
npm install

# Install simulation dependencies  
cd ../deposit-token-sim
npm install
```

### 3. Run Complete Demo
```bash
# Terminal 1: Start local blockchain
cd DepositToken.sol
npm run node

# Terminal 2: Deploy contracts and setup demo
npm run demo-setup

# Terminal 3: Start bank authorization server
cd ../deposit-token-sim
npm run server

# Terminal 4: Run the complete demo
npm run demo
```

























**🎉 That's it!** The demo will show the complete flow from user registration through authorized transfers.

## 📂 Repository Structure

```
DepositToken/
├── DepositToken.sol/           # Smart contracts and deployment
│   ├── contracts/
│   │   ├── src/                # Contract source code
│   │   ├── include/            # Interface definitions
│   │   └── lib/                # Libraries and dependencies
│   ├── scripts/                # Deployment and setup scripts
│   ├── docs/                   # Technical documentation
│   └── package.json
│
├── deposit-token-sim/          # Bank server and wallet client
│   ├── src/
│   │   ├── server.ts           # Bank authorization server
│   │   └── client.ts           # Wallet client
│   ├── test-*.ts               # Comprehensive test suites
│   └── package.json
│
└── README.md                   # This file
```

## 🏦 What the Demo Shows

### 1. Contract Deployment
- Deploys BasicDeposit contract with UUPS proxy
- Registers bank as authorized sponsor
- Mints initial tokens to demo wallets
- Configures authorization URI

### 2. Bank Authorization Service
- Receives registration requests from wallets
- Creates cryptographically signed transfer authorizations
- Manages user nonces for replay protection
- Provides REST API for authorization requests

### 3. Wallet Operations
- Registers with bank service
- Requests authorization for transfers
- Executes on-chain transfers with authorizations
- Checks balances and account status

### 4. Regulatory Features
- **Per-transaction authorization** - Every transfer needs bank approval
- **Account registration** - Only registered users can participate
- **Nonce management** - Prevents replay attacks
- **Asset seizure** - Bank can freeze/seize funds
- **Audit trail** - Complete transaction history

## 🔧 Detailed Setup Instructions

### Option 1: One-Command Demo Setup

The fastest way to see everything working:

```bash
# From DepositToken.sol directory
npm run demo-setup
```

This single command:
- ✅ Deploys all contracts to local blockchain
- ✅ Registers demo wallets with bank sponsor
- ✅ Mints initial token balances
- ✅ Creates .env files for simulation
- ✅ Generates quick start guide

### Option 2: Step-by-Step Setup

For understanding each component:

#### Step 1: Deploy Smart Contracts
```bash
cd DepositToken.sol

# Start local blockchain (keep running)
npm run node

# Deploy contracts (new terminal)
npm run deploy:localhost

# Initialize with demo data
npm run initialize:localhost
```

#### Step 2: Configure Simulation
```bash
cd ../deposit-token-sim

# Copy example environment
cp .env.example .env

# Edit .env with deployed contract address
# DEPOSIT_TOKEN_ADDRESS=0x...
```

#### Step 3: Start Bank Server
```bash
# From deposit-token-sim directory
npm run server

# Server starts on http://localhost:3000
# Bank address: 0x90F79bf6EB2c4f870365E785982E1f101E93b906
```

#### Step 4: Test Wallet Client
```bash
# From deposit-token-sim directory (new terminal)

# Show wallet and bank information
npm run client info

# Register wallet with bank
npm run client register

# Check wallet status
npm run client status

# Execute a transfer (requests authorization and executes)
npm run client transfer 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 1.5
```

## 🧪 Testing

### Comprehensive Test Suite
```bash
cd deposit-token-sim

# Run all tests
npm run test:all

# Individual test suites
npm run test:bank        # Bank server API tests
npm run test:wallet      # Wallet client tests
npm run test:integration # End-to-end flow tests
```

### Smart Contract Tests
```bash
cd DepositToken.sol

# Hardhat tests
npm run test

# Foundry tests (if available)
npm run forge:test
```

### Manual Testing Examples
```bash
# Test bank server endpoints
curl http://localhost:3000/bank/info
curl -X POST http://localhost:3000/bank/register \
  -H "Content-Type: application/json" \
  -d '{"address":"0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"}'

# Test wallet operations
npm run client balance
npm run client transfer 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 2.0
```

## 📊 Key Demo Scenarios

### Scenario 1: Successful Transfer
1. **User registers** with bank service
2. **Bank verifies** user eligibility
3. **User requests** transfer authorization
4. **Bank creates** signed authorization
5. **User executes** on-chain transfer
6. **Contract validates** authorization and processes transfer

### Scenario 2: Invalid Authorization
1. User attempts transfer with **expired authorization**
2. Contract **rejects** transaction
3. User receives **clear error message**
4. User requests **new authorization**

### Scenario 3: Regulatory Action
1. Bank detects **suspicious activity**
2. Bank **freezes user account**
3. Transfers are **blocked** until investigation
4. Bank can **seize assets** if necessary

## 🔒 Security Features Demonstrated

### Cryptographic Security
- **ECDSA signatures** for authorization verification
- **Nonce-based replay protection**
- **Time-limited authorizations**
- **Spending limit enforcement**

### Regulatory Controls
- **Account registration** requirements
- **Sponsor-based authorization**
- **Real-time asset seizure**
- **Emergency halt capabilities**

### Audit and Compliance
- **Complete transaction logs**
- **Authorization audit trail**
- **Regulatory reporting data**
- **Immutable compliance records**

## 🌐 Network Configuration

### Local Development (Default)
- **Blockchain**: Hardhat local node
- **RPC URL**: http://localhost:8545
- **Bank Server**: http://localhost:3000
- **Accounts**: Pre-funded Hardhat accounts

### Testnet Deployment
```bash
# Configure for Sepolia testnet
cd DepositToken.sol
cp .env.example .env
# Edit SEPOLIA_URL and PRIVATE_KEY

# Deploy to testnet
npm run deploy:sepolia

# Update simulation config
cd ../deposit-token-sim
# Edit .env with testnet contract address and RPC URL
```

### Production Considerations
- Use hardware wallets for private key management
- Configure proper RPC endpoints with redundancy
- Implement comprehensive monitoring and alerting
- Set up automated backup and recovery procedures

## 📈 Monitoring and Analytics

### Real-time Monitoring
The demo includes monitoring capabilities:

```bash
# View transaction events
npm run client status

# Monitor bank server logs
# (Shows authorization requests and approvals)

# Check contract events
npx hardhat console --network localhost
> const events = await contract.queryFilter('Transfer')
```

### Key Metrics Tracked
- **Transaction volume** and frequency
- **Authorization success/failure rates**
- **Account registration trends**
- **Regulatory action frequency**
- **System health and uptime**

## 🔧 Troubleshooting

### Common Issues

#### 1. "Contract not found" Error
```bash
# Verify contract is deployed
npx hardhat console --network localhost
> await ethers.provider.getCode("CONTRACT_ADDRESS")

# Should return bytecode, not "0x"
```

#### 2. "Bank server not responding"
```bash
# Check server is running
curl http://localhost:3000/health

# Check port availability
lsof -i :3000
```

#### 3. "Authorization failed"
```bash
# Check wallet is registered
npm run client status

# Verify bank address matches
npm run client info
```

#### 4. "Insufficient balance"
```bash
# Check token balance
npm run client balance

# Mint more tokens (owner only)
npm run initialize:localhost
```

### Debug Mode
```bash
# Enable verbose logging
DEBUG=true npm run server
DEBUG=true npm run client status
```

## 📚 Additional Resources

### Documentation
- **[Technical Overview](./DepositToken.sol/docs/TECHNICAL_OVERVIEW.md)** - Complete system architecture
- **[API Reference](./DepositToken.sol/docs/API_REFERENCE.md)** - Detailed API documentation
- **[Regulatory Compliance](./DepositToken.sol/docs/REGULATORY_COMPLIANCE.md)** - Compliance framework
- **[Deployment Guide](./DepositToken.sol/README-DEPLOYMENT.md)** - Advanced deployment options

### Example Use Cases
- **CBDC Implementation** - Central bank digital currency
- **Regulated Stablecoin** - Compliant payment token
- **Corporate Treasury** - Internal payment system
- **Cross-border Payments** - International transfers

### Integration Examples
- **KYC/AML Integration** - Identity verification
- **Regulatory Reporting** - Automated compliance
- **Multi-jurisdiction Deployment** - Global compliance
- **Enterprise Integration** - Corporate systems

## 🤝 Contributing

### Development Setup
```bash
# Install development dependencies
npm install --dev

# Run linting
npm run lint

# Run type checking
npm run typecheck
```

### Testing New Features
```bash
# Run comprehensive tests
npm run test:all

# Test specific components
npm run test:bank
npm run test:integration
```

### Reporting Issues
- Include reproduction steps
- Provide environment details
- Include relevant log outputs
- Describe expected vs actual behavior

## 📄 License

This project is provided for educational and research purposes. Please review the license file for detailed terms and conditions.

## ⚠️ Important Notes

### Development vs Production
- This demo uses **development private keys** - never use in production
- Local blockchain state is **not persistent** - data resets on restart
- Bank server uses **in-memory storage** - not suitable for production

### Security Considerations
- Always use **hardware wallets** for production
- Implement **proper key management** systems
- Enable **comprehensive monitoring** and alerting
- Conduct **thorough security audits** before deployment

### Regulatory Compliance
- Consult **legal experts** for your jurisdiction
- Implement **proper KYC/AML** procedures
- Establish **regulatory reporting** mechanisms
- Maintain **comprehensive audit trails**

---

🎉 **Congratulations!** You now have a complete regulated payment asset system running locally. This demonstrates how blockchain technology can be used for compliant digital payments while maintaining regulatory oversight and control.