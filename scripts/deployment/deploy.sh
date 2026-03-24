#!/usr/bin/env bash

set -a
source .env
set +a


# ========================================================================================
# Deploy Broadcaster and Receiver contracts
# ========================================================================================
chmod +x scripts/deployment/deploy-protocol.sh

echo "Deploying Broadcaster and Receiver contracts on Ethereum..."
CHAIN_TYPE="ethereum" \
RPC_URL="$ETHEREUM_RPC_URL" \
./scripts/deployment/deploy-protocol.sh

echo "Deploying Broadcaster and Receiver contracts on Arbitrum..."
CHAIN_TYPE="arbitrum" \
RPC_URL="$ARBITRUM_RPC_URL" \
./scripts/deployment/deploy-protocol.sh

echo "Deploying Broadcaster and Receiver contracts on Linea..."
CHAIN_TYPE="linea" \
RPC_URL="$LINEA_RPC_URL" \
./scripts/deployment/deploy-protocol.sh

echo "Deploying Broadcaster and Receiver contracts on Scroll..."
CHAIN_TYPE="scroll" \
RPC_URL="$SCROLL_RPC_URL" \
./scripts/deployment/deploy-protocol.sh

echo "Deploying Broadcaster and Receiver contracts on Optimism..."
CHAIN_TYPE="optimism" \
RPC_URL="$OPTIMISM_RPC_URL" \
./scripts/deployment/deploy-protocol.sh

echo "Deploying Broadcaster and Receiver contracts on ZkSync..."
CHAIN_TYPE="zksync" \
RPC_URL="$ZKSYNC_RPC_URL" \
./scripts/deployment/deploy-protocol.sh


# ========================================================================================
# Deploy ParentToChildProver contracts
# ========================================================================================
chmod +x scripts/deployment/provers/deploy-parent-provers.sh

# Ethereum
echo "Deploying ParentToChildProver contracts on Ethereum..."
RPC_URL="$ETHEREUM_RPC_URL" ./scripts/deployment/provers/deploy-parent-provers.sh

# Arbitrum
echo "Deploying ParentToChildProver contracts on Arbitrum..."
RPC_URL="$ARBITRUM_RPC_URL" ./scripts/deployment/provers/deploy-parent-provers.sh

# Linea
echo "Deploying ParentToChildProver contracts on Linea..."
RPC_URL="$LINEA_RPC_URL" ./scripts/deployment/provers/deploy-parent-provers.sh

# Scroll
echo "Deploying ParentToChildProver contracts on Scroll..."
RPC_URL="$SCROLL_RPC_URL" ./scripts/deployment/provers/deploy-parent-provers.sh

# Optimism
echo "Deploying ParentToChildProver contracts on Optimism..."
RPC_URL="$OPTIMISM_RPC_URL" ./scripts/deployment/provers/deploy-parent-provers.sh

# ZkSync
echo "Deploying ParentToChildProver contracts on ZkSync..."
RPC_URL="$ZKSYNC_RPC_URL" ./scripts/deployment/provers/deploy-parent-provers.sh


# ========================================================================================
# Deploy Pushers contracts
# ========================================================================================

# Ethereum
echo "Deploying Pushers contracts on Ethereum..."

RPC_URL="$ETHEREUM_RPC_URL" ./scripts/deployment/block-hash-pusher/deploy-pushers.sh

# ========================================================================================
# Deploy Buffers contracts
# ========================================================================================
chmod +x scripts/deployment/block-hash-pusher/deploy-buffers.sh

# Ethereum

# Linea
echo "Deploying Buffer contract for Linea..."
CHAIN_TYPE="linea" \
PARENT_CHAIN_ID="$ETHEREUM_CHAIN_ID" \
CHILD_CHAIN_ID="$LINEA_CHAIN_ID" \
MESSENGER="$LINEA_L2_MESSAGE_SERVICE" \
RPC_URL="$LINEA_RPC_URL" ./scripts/deployment/block-hash-pusher/deploy-buffers.sh

# Scroll
echo "Deploying Buffer contract for Scroll..."
CHAIN_TYPE="scroll" \
PARENT_CHAIN_ID="$ETHEREUM_CHAIN_ID" \
CHILD_CHAIN_ID="$SCROLL_CHAIN_ID" \
MESSENGER="$L2_SCROLL_MESSENGER" \
RPC_URL="$SCROLL_RPC_URL" ./scripts/deployment/block-hash-pusher/deploy-buffers.sh

# ZkSync
echo "Deploying Buffer contract for ZkSync..."
CHAIN_TYPE="zksync" \
PARENT_CHAIN_ID="$ETHEREUM_CHAIN_ID" \
CHILD_CHAIN_ID="$ZKSYNC_CHAIN_ID" \
MESSENGER=0x0000000000000000000000000000000000000000 \
RPC_URL="$ZKSYNC_RPC_URL" ./scripts/deployment/block-hash-pusher/deploy-buffers.sh

# Optimism
echo "Deploying Buffer contract for Optimism..."
CHAIN_TYPE="optimism" \
PARENT_CHAIN_ID="$ETHEREUM_CHAIN_ID" \
CHILD_CHAIN_ID="$OPTIMISM_CHAIN_ID" \
MESSENGER="$OPTIMISM_L2_CROSS_DOMAIN_MESSENGER" \
RPC_URL="$OPTIMISM_RPC_URL" ./scripts/deployment/block-hash-pusher/deploy-buffers.sh

# ========================================================================================
# Deploy ChildToParentProver contracts
# ========================================================================================
chmod +x scripts/deployment/provers/deploy-child-provers.sh

# Ethereum
echo "Deploying ChildToParentProver contracts ..."
./scripts/deployment/provers/deploy-child-provers.sh
