#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
NETWORK="localhost"
RPC_URL="http://localhost:8545"
PRIVATE_KEY=""
VERIFY=""

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -n, --network NETWORK     Target network (localhost, sepolia, mainnet)"
    echo "  -r, --rpc-url URL         Custom RPC URL"
    echo "  -k, --private-key KEY     Private key for deployment"
    echo "  -v, --verify              Verify contracts on Etherscan"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Deploy to local network"
    echo "  $0 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
    echo ""
    echo "  # Deploy to Sepolia"
    echo "  $0 --network sepolia --private-key YOUR_PRIVATE_KEY --verify"
    echo ""
    echo "  # Deploy with custom RPC"
    echo "  $0 --rpc-url https://your-node.com --private-key YOUR_PRIVATE_KEY"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--network)
            NETWORK="$2"
            shift 2
            ;;
        -r|--rpc-url)
            RPC_URL="$2"
            shift 2
            ;;
        -k|--private-key)
            PRIVATE_KEY="$2"
            shift 2
            ;;
        -v|--verify)
            VERIFY="--verify"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option $1"
            usage
            exit 1
            ;;
    esac
done

# Set RPC URL based on network if not provided
if [[ "$NETWORK" != "localhost" && -z "$RPC_URL" ]]; then
    case $NETWORK in
        sepolia)
            RPC_URL="https://sepolia.infura.io/v3/$INFURA_KEY"
            ;;
        mainnet)
            RPC_URL="https://mainnet.infura.io/v3/$INFURA_KEY"
            ;;
        *)
            echo -e "${RED}Error: Unknown network $NETWORK${NC}"
            echo "Supported networks: localhost, sepolia, mainnet"
            exit 1
            ;;
    esac
fi

# Validate required parameters
if [[ -z "$PRIVATE_KEY" ]]; then
    echo -e "${RED}Error: Private key is required${NC}"
    echo "Use --private-key option or set PRIVATE_KEY environment variable"
    exit 1
fi

# Check if we're in the right directory
if [[ ! -f "foundry.toml" ]]; then
    echo -e "${RED}Error: Must be run from the project root directory${NC}"
    exit 1
fi

echo -e "${BLUE}=== Modular ERC-7579 Deposit Token Deployment ===${NC}"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo "  Network: $NETWORK"
echo "  RPC URL: $RPC_URL"
echo "  Verify: ${VERIFY:-false}"
echo ""

# Check if forge is available
if ! command -v forge &> /dev/null; then
    echo -e "${RED}Error: Foundry (forge) is not installed${NC}"
    echo "Please install Foundry: https://book.getfoundry.sh/getting-started/installation"
    exit 1
fi

# Check if the deployment script exists
DEPLOY_SCRIPT="script/DeployModularERC7579.s.sol"
if [[ ! -f "$DEPLOY_SCRIPT" ]]; then
    echo -e "${RED}Error: Deployment script not found: $DEPLOY_SCRIPT${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 1: Building contracts...${NC}"
if ! forge build --skip tests; then
    echo -e "${RED}Error: Contract compilation failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Contracts compiled successfully${NC}"
echo ""

echo -e "${YELLOW}Step 2: Running deployment script...${NC}"
echo ""

# Prepare the forge script command
FORGE_CMD="forge script $DEPLOY_SCRIPT --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast"

# Add verification if requested
if [[ -n "$VERIFY" ]]; then
    if [[ -z "$ETHERSCAN_API_KEY" ]]; then
        echo -e "${YELLOW}Warning: ETHERSCAN_API_KEY not set, skipping verification${NC}"
    else
        FORGE_CMD="$FORGE_CMD --verify --etherscan-api-key $ETHERSCAN_API_KEY"
    fi
fi

# Execute the deployment
export PRIVATE_KEY="$PRIVATE_KEY"
if eval $FORGE_CMD; then
    echo ""
    echo -e "${GREEN}=== Deployment Successful! ===${NC}"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Save the contract addresses from the output above"
    echo "2. Set up environment variables for your application:"
    echo "   - MODULAR_DEPOSIT_TOKEN_ADDRESS"
    echo "   - REGULATORY_VALIDATOR_ADDRESS"
    echo "   - COMPLIANCE_HOOK_ADDRESS"
    echo "   - TREASURY_EXECUTOR_ADDRESS"
    echo ""
    echo "3. Configure module parameters:"
    echo "   - Set compliance rules for accounts"
    echo "   - Configure treasury operation limits"
    echo "   - Set up monitoring and alerting"
    echo ""
    echo "4. Test the deployment:"
    echo "   - Register test accounts"
    echo "   - Perform test transactions"
    echo "   - Verify module interactions"
    echo ""
    echo -e "${BLUE}Documentation: docs/MODULAR_DEPOSIT_TOKEN_GUIDE.md${NC}"
    echo ""
else
    echo ""
    echo -e "${RED}=== Deployment Failed! ===${NC}"
    echo ""
    echo "Common issues:"
    echo "1. Insufficient funds for gas fees"
    echo "2. Network connectivity issues"
    echo "3. Invalid private key"
    echo "4. Contract compilation errors"
    echo ""
    echo "Check the error messages above for specific details."
    exit 1
fi