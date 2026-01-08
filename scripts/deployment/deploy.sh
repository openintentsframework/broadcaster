#!/usr/bin/env bash

set -a
source .env
set +a


# ========================================================================================
# Deploy Broadcaster and Receiver contracts
# ========================================================================================
chmod +x scripts/deployment/deploy-protocol.sh

echo "Deploying Broadcaster and Receiver contracts on Ethereum Sepolia..."
CHAIN_TYPE="ethereum" \
RPC_URL="$ETHEREUM_SEPOLIA_RPC_URL" \
./scripts/deployment/deploy-protocol.sh

echo "Deploying Broadcaster and Receiver contracts on Arbitrum Sepolia..."
CHAIN_TYPE="arbitrum" \
RPC_URL="$ARBITRUM_SEPOLIA_RPC_URL" \
./scripts/deployment/deploy-protocol.sh

echo "Deploying Broadcaster and Receiver contracts on Linea Sepolia..."
CHAIN_TYPE="linea" \
RPC_URL="$LINEA_SEPOLIA_RPC_URL" \
./scripts/deployment/deploy-protocol.sh

echo "Deploying Broadcaster and Receiver contracts on Scroll Sepolia..."
CHAIN_TYPE="scroll" \
RPC_URL="$SCROLL_SEPOLIA_RPC_URL" \
./scripts/deployment/deploy-protocol.sh

echo "Deploying Broadcaster and Receiver contracts on Optimism Sepolia..."
CHAIN_TYPE="optimism" \
RPC_URL="$OPTIMISM_SEPOLIA_RPC_URL" \
./scripts/deployment/deploy-protocol.sh

echo "Deploying Broadcaster and Receiver contracts on ZkSync Sepolia..."
CHAIN_TYPE="zksync" \
RPC_URL="$ZKSYNC_SEPOLIA_RPC_URL" \
./scripts/deployment/deploy-protocol.sh


# ========================================================================================
# Deploy ParentToChildProver contracts
# ========================================================================================
chmod +x scripts/deployment/provers/deploy-parent-provers.sh

# Ethereum Sepolia
echo "Deploying ParentToChildProver contracts on Ethereum Sepolia..."
RPC_URL="$ETHEREUM_SEPOLIA_RPC_URL" ./scripts/deployment/provers/deploy-parent-provers.sh

# Arbitrum Sepolia
echo "Deploying ParentToChildProver contracts on Arbitrum Sepolia..."
RPC_URL="$ARBITRUM_SEPOLIA_RPC_URL" ./scripts/deployment/provers/deploy-parent-provers.sh

# Linea Sepolia
echo "Deploying ParentToChildProver contracts on Linea Sepolia..."
RPC_URL="$LINEA_SEPOLIA_RPC_URL" ./scripts/deployment/provers/deploy-parent-provers.sh

# Scroll Sepolia
echo "Deploying ParentToChildProver contracts on Scroll Sepolia..."
RPC_URL="$SCROLL_SEPOLIA_RPC_URL" ./scripts/deployment/provers/deploy-parent-provers.sh

# Optimism Sepolia
echo "Deploying ParentToChildProver contracts on Optimism Sepolia..."
RPC_URL="$OPTIMISM_SEPOLIA_RPC_URL" ./scripts/deployment/provers/deploy-parent-provers.sh
