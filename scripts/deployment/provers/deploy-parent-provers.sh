#!/usr/bin/env bash

OUTBOX=$ARBITRUM_SEPOLIA_OUTBOX \
ROOTS_SLOT=$ARBITRUM_SEPOLIA_ROOTS_SLOT \
HOME_CHAIN_ID=$ETHEREUM_SEPOLIA_CHAIN_ID \
TARGET_CHAIN_ID=$ARBITRUM_SEPOLIA_CHAIN_ID \
forge script scripts/deployment/provers/DeployArbitrumParentToChild.s.sol \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast


ROLLUP=$LINEA_SEPOLIA_ROLLUP \
STATE_ROOT_HASHES_SLOT=$LINEA_SEPOLIA_STATE_ROOT_HASHES_SLOT \
HOME_CHAIN_ID=$ETHEREUM_SEPOLIA_CHAIN_ID \
TARGET_CHAIN_ID=$LINEA_SEPOLIA_CHAIN_ID \
forge script scripts/deployment/provers/DeployLineaParentToChild.s.sol \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast


SCROLL_CHAIN=$SCROLL_CHAIN_SEPOLIA \
FINALIZED_STATE_ROOTS_SLOT=$SCROLL_SEPOLIA_FINALIZED_STATE_ROOT_SLOT \
HOME_CHAIN_ID=$ETHEREUM_SEPOLIA_CHAIN_ID \
TARGET_CHAIN_ID=$SCROLL_SEPOLIA_CHAIN_ID \
forge script scripts/deployment/provers/DeployScrollParentToChild.s.sol \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast


ANCHOR_STATE_REGISTRY=$OPTIMISM_SEPOLIA_ANCHOR_STATE_REGISTRY \
HOME_CHAIN_ID=$ETHEREUM_SEPOLIA_CHAIN_ID \
TARGET_CHAIN_ID=$OPTIMISM_SEPOLIA_CHAIN_ID \
forge script scripts/deployment/provers/DeployOptimismParentToChild.s.sol \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast










