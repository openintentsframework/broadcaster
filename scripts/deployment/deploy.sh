#!/usr/bin/env bash

set -a
source .env
set +a


# ========================================================================================
# Deploy Broadcaster and Receiver contracts
# ========================================================================================

echo "Deploying Broadcaster and Receiver contracts on Ethereum..."
CHAIN_TYPE="ethereum" \
RPC_URL="$ETHEREUM_RPC_URL" \
bash scripts/deployment/deploy-protocol.sh

echo "Deploying Broadcaster and Receiver contracts on Arbitrum..."
CHAIN_TYPE="arbitrum" \
RPC_URL="$ARBITRUM_RPC_URL" \
bash scripts/deployment/deploy-protocol.sh

echo "Deploying Broadcaster and Receiver contracts on Linea..."
CHAIN_TYPE="linea" \
RPC_URL="$LINEA_RPC_URL" \
bash scripts/deployment/deploy-protocol.sh

echo "Deploying Broadcaster and Receiver contracts on Scroll..."
CHAIN_TYPE="scroll" \
RPC_URL="$SCROLL_RPC_URL" \
bash scripts/deployment/deploy-protocol.sh

echo "Deploying Broadcaster and Receiver contracts on Optimism..."
CHAIN_TYPE="optimism" \
RPC_URL="$OPTIMISM_RPC_URL" \
bash scripts/deployment/deploy-protocol.sh

echo "Deploying Broadcaster and Receiver contracts on Base..."
CHAIN_TYPE="base" \
RPC_URL="$BASE_RPC_URL" \
bash scripts/deployment/deploy-protocol.sh

echo "Deploying Broadcaster and Receiver contracts on Unichain..."
CHAIN_TYPE="unichain" \
RPC_URL="$UNICHAIN_RPC_URL" \
bash scripts/deployment/deploy-protocol.sh

echo "Deploying Broadcaster and Receiver contracts on World Chain..."
CHAIN_TYPE="worldchain" \
RPC_URL="$WORLD_RPC_URL" \
bash scripts/deployment/deploy-protocol.sh

echo "Deploying Broadcaster and Receiver contracts on ZkSync..."
CHAIN_TYPE="zksync" \
RPC_URL="$ZKSYNC_RPC_URL" \
bash scripts/deployment/deploy-protocol.sh


# ========================================================================================
# Deploy ParentToChildProver contracts
# ========================================================================================

# Ethereum
echo "Deploying ParentToChildProver contracts on Ethereum..."
CHAIN_TYPE="ethereum" \
RPC_URL="$ETHEREUM_RPC_URL" bash scripts/deployment/provers/deploy-parent-provers.sh

# Arbitrum
echo "Deploying ParentToChildProver contracts on Arbitrum..."
CHAIN_TYPE="arbitrum" \
RPC_URL="$ARBITRUM_RPC_URL" bash scripts/deployment/provers/deploy-parent-provers.sh

# Linea
echo "Deploying ParentToChildProver contracts on Linea..."
CHAIN_TYPE="linea" \
RPC_URL="$LINEA_RPC_URL" bash scripts/deployment/provers/deploy-parent-provers.sh

# Scroll
echo "Deploying ParentToChildProver contracts on Scroll..."
CHAIN_TYPE="scroll" \
RPC_URL="$SCROLL_RPC_URL" bash scripts/deployment/provers/deploy-parent-provers.sh

# Optimism
echo "Deploying ParentToChildProver contracts on Optimism..."
CHAIN_TYPE="optimism" \
RPC_URL="$OPTIMISM_RPC_URL" bash scripts/deployment/provers/deploy-parent-provers.sh

# Base
echo "Deploying ParentToChildProver contracts on Base..."
CHAIN_TYPE="base" \
RPC_URL="$BASE_RPC_URL" bash scripts/deployment/provers/deploy-parent-provers.sh

# Unichain
echo "Deploying ParentToChildProver contracts on Unichain..."
CHAIN_TYPE="unichain" \
RPC_URL="$UNICHAIN_RPC_URL" bash scripts/deployment/provers/deploy-parent-provers.sh

# World Chain
echo "Deploying ParentToChildProver contracts on World Chain..."
CHAIN_TYPE="worldchain" \
RPC_URL="$WORLD_RPC_URL" bash scripts/deployment/provers/deploy-parent-provers.sh

# ZkSync
echo "Deploying ParentToChildProver contracts on ZkSync..."
CHAIN_TYPE="zksync" \
RPC_URL="$ZKSYNC_RPC_URL" bash scripts/deployment/provers/deploy-parent-provers.sh


# ========================================================================================
# Deploy Pushers contracts
# ========================================================================================

# Ethereum
echo "Deploying Pushers contracts on Ethereum..."

RPC_URL="$ETHEREUM_RPC_URL" bash scripts/deployment/block-hash-pusher/deploy-pushers.sh

# ========================================================================================
# Deploy Buffers contracts
# ========================================================================================

# Ethereum

# Linea
echo "Deploying Buffer contract for Linea..."
CHAIN_TYPE="linea" \
PARENT_CHAIN_ID="$ETHEREUM_CHAIN_ID" \
CHILD_CHAIN_ID="$LINEA_CHAIN_ID" \
MESSENGER="$LINEA_L2_MESSAGE_SERVICE" \
RPC_URL="$LINEA_RPC_URL" bash scripts/deployment/block-hash-pusher/deploy-buffers.sh

# Scroll
echo "Deploying Buffer contract for Scroll..."
CHAIN_TYPE="scroll" \
PARENT_CHAIN_ID="$ETHEREUM_CHAIN_ID" \
CHILD_CHAIN_ID="$SCROLL_CHAIN_ID" \
MESSENGER="$L2_SCROLL_MESSENGER" \
RPC_URL="$SCROLL_RPC_URL" bash scripts/deployment/block-hash-pusher/deploy-buffers.sh

# ZkSync
echo "Deploying Buffer contract for ZkSync..."
CHAIN_TYPE="zksync" \
PARENT_CHAIN_ID="$ETHEREUM_CHAIN_ID" \
CHILD_CHAIN_ID="$ZKSYNC_CHAIN_ID" \
MESSENGER=0x0000000000000000000000000000000000000000 \
RPC_URL="$ZKSYNC_RPC_URL" bash scripts/deployment/block-hash-pusher/deploy-buffers.sh

# Optimism
echo "Deploying Buffer contract for Optimism..."
CHAIN_TYPE="optimism" \
PARENT_CHAIN_ID="$ETHEREUM_CHAIN_ID" \
CHILD_CHAIN_ID="$OPTIMISM_CHAIN_ID" \
MESSENGER="$OPTIMISM_L2_CROSS_DOMAIN_MESSENGER" \
RPC_URL="$OPTIMISM_RPC_URL" bash scripts/deployment/block-hash-pusher/deploy-buffers.sh

# Base
echo "Deploying Buffer contract for Base..."
CHAIN_TYPE="base" \
PARENT_CHAIN_ID="$ETHEREUM_CHAIN_ID" \
CHILD_CHAIN_ID="$BASE_CHAIN_ID" \
MESSENGER="$BASE_L2_CROSS_DOMAIN_MESSENGER" \
RPC_URL="$BASE_RPC_URL" bash scripts/deployment/block-hash-pusher/deploy-buffers.sh

# Unichain
echo "Deploying Buffer contract for Unichain..."
CHAIN_TYPE="unichain" \
PARENT_CHAIN_ID="$ETHEREUM_CHAIN_ID" \
CHILD_CHAIN_ID="$UNICHAIN_CHAIN_ID" \
MESSENGER="$UNICHAIN_L2_CROSS_DOMAIN_MESSENGER" \
RPC_URL="$UNICHAIN_RPC_URL" bash scripts/deployment/block-hash-pusher/deploy-buffers.sh

# World Chain
echo "Deploying Buffer contract for World Chain..."
CHAIN_TYPE="worldchain" \
PARENT_CHAIN_ID="$ETHEREUM_CHAIN_ID" \
CHILD_CHAIN_ID="$WORLD_CHAIN_ID" \
MESSENGER="$WORLD_L2_CROSS_DOMAIN_MESSENGER" \
RPC_URL="$WORLD_RPC_URL" bash scripts/deployment/block-hash-pusher/deploy-buffers.sh

# ========================================================================================
# Deploy ChildToParentProver contracts
# ========================================================================================

# Ethereum
echo "Deploying ChildToParentProver contracts ..."
bash scripts/deployment/provers/deploy-child-provers.sh