# 🚀 Deposit Token Demo Quick Start

## Deployed Contracts
- **Proxy Address**: `0x0165878A594ca255338adfa4d48449f69242Eb8F`
- **Bank Address**: `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`
- **Wallet 1**: `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` (1000 tokens)
- **Wallet 2**: `0x90F79bf6EB2c4f870365E785982E1f101E93b906` (1000 tokens)

## Quick Commands

### Start Local Blockchain (if needed)
```bash
npx hardhat node
```

### Start Bank Server
```bash
cd ../simulation
npm run server
```

### Test Wallet Client
```bash
cd ../simulation
npm run client info
npm run client status
npm run client transfer 0x90F79bf6EB2c4f870365E785982E1f101E93b906 5.0
```

### Run Tests
```bash
cd ../simulation
npm run test:all
```

### Run Complete Demo
```bash
cd ../simulation
npm run demo
```

## Contract Interactions

### Check Balance
```bash
npx hardhat console --network localhost
> const token = await ethers.getContractAt("BasicDeposit", "0x0165878A594ca255338adfa4d48449f69242Eb8F")
> await token.balanceOf("0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC")
```

### Mint More Tokens
```bash
npx hardhat run scripts/initialize.ts --network localhost
```

## Troubleshooting

1. **Bank server not responding**: Make sure it's running on port 3000
2. **Contract not found**: Verify the RPC URL is correct (http://localhost:8545)
3. **Insufficient balance**: Use the initialize script to mint more tokens
4. **Authorization failed**: Check that the bank address matches in both .env files

## Generated Files
- `.env` - Environment configuration
- `../simulation/.env` - Simulation environment
- `QUICKSTART.md` - This guide

Happy testing! 🎉
