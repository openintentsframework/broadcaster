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

# ZkSync Sepolia
echo "Deploying ParentToChildProver contracts on ZkSync Sepolia..."
RPC_URL="$ZKSYNC_SEPOLIA_RPC_URL" ./scripts/deployment/provers/deploy-parent-provers.sh


# ========================================================================================
# Deploy Pushers contracts
# ========================================================================================
chmod +x scripts/deployment/block-hash-pusher/deploy-pushers.sh

# Ethereum Sepolia
echo "Deploying Pushers contracts on Ethereum Sepolia..."
LINEA_ROLLUP="$LINEA_SEPOLIA_ROLLUP" \
L1_SCROLL_MESSENGER="$SCROLL_SEPOLIA_L1_SCROLL_MESSENGER" \
ZKSYNC_DIAMOND="$ZKSYNC_SEPOLIA_DIAMOND" \
OP_L1_CROSS_DOMAIN_MESSENGER_PROXY="$OPTIMISM_SEPOLIA_L1_CROSS_DOMAIN_MESSENGER_PROXY" \
RPC_URL="$ETHEREUM_SEPOLIA_RPC_URL" ./scripts/deployment/block-hash-pusher/deploy-pushers.sh

# ========================================================================================
# Deploy Buffers contracts
# ========================================================================================
chmod +x scripts/deployment/block-hash-pusher/deploy-buffers.sh

# Ethereum Sepolia

# Linea Sepolia
echo "Deploying Buffer contract for Linea Sepolia..."
CHAIN_TYPE="linea" \
PARENT_CHAIN="ethereum-sepolia" \
CHILD_CHAIN="linea-sepolia" \
MESSENGER="$LINEA_SEPOLIA_L2_MESSAGE_SERVICE" \
RPC_URL="$LINEA_SEPOLIA_RPC_URL" ./scripts/deployment/block-hash-pusher/deploy-buffers.sh

# Scroll Sepolia
echo "Deploying Buffer contract for Scroll Sepolia..."
CHAIN_TYPE="scroll" \
PARENT_CHAIN="ethereum-sepolia" \
CHILD_CHAIN="scroll-sepolia" \
MESSENGER="$SCROLL_SEPOLIA_L2_SCROLL_MESSENGER" \
RPC_URL="$SCROLL_SEPOLIA_RPC_URL" ./scripts/deployment/block-hash-pusher/deploy-buffers.sh

# ZkSync Sepolia
echo "Deploying Buffer contract for ZkSync Sepolia..."
CHAIN_TYPE="zksync" \
PARENT_CHAIN="ethereum-sepolia" \
CHILD_CHAIN="zksync-sepolia" \
MESSENGER=0x0000000000000000000000000000000000000000 \
RPC_URL="$ZKSYNC_SEPOLIA_RPC_URL" ./scripts/deployment/block-hash-pusher/deploy-buffers.sh

# Optimism Sepolia
echo "Deploying Buffer contract for Optimism Sepolia..."
CHAIN_TYPE="optimism" \
PARENT_CHAIN="ethereum-sepolia" \
CHILD_CHAIN="optimism-sepolia" \
MESSENGER="$OPTIMISM_SEPOLIA_L2_CROSS_DOMAIN_MESSENGER" \
RPC_URL="$OPTIMISM_SEPOLIA_RPC_URL" ./scripts/deployment/block-hash-pusher/deploy-buffers.sh

# ========================================================================================
# Deploy ChildToParentProver contracts
# ========================================================================================
chmod +x scripts/deployment/provers/deploy-child-provers.sh

# Ethereum Sepolia
echo "Deploying ChildToParentProver contracts ..."
./scripts/deployment/provers/deploy-child-provers.sh
