# Payment Token Demo - Complete Setup Guide

A comprehensive demonstration of a regulated payment asset system with bank authorization and wallet client integration.

## Overview

This repository demonstrates a complete regulated payment token ecosystem consisting of:

- Smart Contracts - Regulated payment asset with per-transaction authorization
- Bank Server - Authorization service that signs transfer approvals  
- Wallet Client - User wallet that requests authorizations and executes transfers
- Testing Suite - Comprehensive tests for all components

## Model Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Wallet Client │────│   Bank Server   │────│ Ledger          │
│            │    │                 │    │ (Smart Contract)│
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

## Quick Start

### Prerequisites
- **Node.js** v16+ and npm
- Hardhat or Anvil, to run a local Ethereum node

### 1. Clone and Setup
```bash
git clone https://github.com/mit-dci/payment-tokens
cd payment-tokens
```

### 2. Install Dependencies
```bash
# Install dependencies for deploying the contracts
cd PaymentToken.sol
npm install

# Install dependencies to run the simulation
cd ../simulation
npm install
```

### 3. Run The Demo
```bash
# Terminal 1: Start local Ethereum node
anvil

# Terminal 2: Deploy contracts and setup demo
cd PaymentToken.sol
npm run demo-setup

# Terminal 2: Start bank authorization server
cd ../simulation
npm run server

# Terminal 3: Test out the demo
npm run demo
```

### 4. UI Demo
```bash
cd simulation
npm run dev
# Can access the sample wallet at http://localhost:3000/wallet
# and the admin page at http://localhost:3000/admin
# This interacts with the deployed contract(s) specified in .env
```

## Troubleshooting

Monitor the logs of the bank server or anvil to debug issues. Generally, the issues are related to the authorization requirements for the parties of the transaction. 
Most administrative features can be handled from the /admin page, or handled via direct requests to the payment token contract with ethereum tooling.

## Repository Structure

```
PaymentToken/
├── PaymentToken.sol/           # Smart contracts and deployment
│   ├── contracts/
│   │   ├── src/                # Contract source code
│   │   ├── include/            # Interface definitions
│   │   └── lib/                # Libraries and dependencies
│   ├── scripts/                # Deployment and setup scripts
│   ├── docs/                   # Technical documentation
│   └── package.json
│
├── simulation/          # Bank server and wallet client
│   ├── src/
│   │   ├── server.ts           # Bank authorization server
│   │   └── client.ts           # Wallet client
│   ├── test-*.ts               # Comprehensive test suites
│   └── package.json
│
└── README.md                   # This file
```

## The Demo

### 1. Contract Deployment
- Deploys BasicDeposit contract with UUPS proxy
- Registers bank as authorized sponsor
- Mints initial tokens to demo wallets
- Configures authorization URI

### 2. Bank Authorization Service
- Receives registration requests from wallets
- Creates cryptographically signed transfer authorizations
- Manages user nonces for replay protection
- Provides API for authorization requests

### 3. Sample Wallet
- Registers with bank service
- Requests authorization for transfers
- Executes on-chain transfers with authorizations
- Checks balances and account status

### 4. Regulatory Features
- Bank can approve transfers ahead of time, in line with modern regulatory requirements
- Prevents replay attacks for authorization
- Bank can freeze/seize funds
