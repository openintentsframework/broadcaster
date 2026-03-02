#!/usr/bin/env bash

HOME_CHAIN_ID=$ARBITRUM_SEPOLIA_CHAIN_ID \
TARGET_CHAIN_ID=$ETHEREUM_SEPOLIA_CHAIN_ID \
forge script scripts/deployment/provers/DeployArbitrumChildToParent.s.sol \
    --rpc-url "$ARBITRUM_SEPOLIA_RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast

HOME_CHAIN_ID=$LINEA_SEPOLIA_CHAIN_ID \
TARGET_CHAIN_ID=$ETHEREUM_SEPOLIA_CHAIN_ID \
forge script scripts/deployment/provers/DeployLineaChildToParent.s.sol \
    --rpc-url "$LINEA_SEPOLIA_RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast

HOME_CHAIN_ID=$SCROLL_SEPOLIA_CHAIN_ID \
TARGET_CHAIN_ID=$ETHEREUM_SEPOLIA_CHAIN_ID \
forge script scripts/deployment/provers/DeployScrollChildToParent.s.sol \
    --rpc-url "$SCROLL_SEPOLIA_RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast

HOME_CHAIN_ID=$OPTIMISM_SEPOLIA_CHAIN_ID \
TARGET_CHAIN_ID=$ETHEREUM_SEPOLIA_CHAIN_ID \
forge script scripts/deployment/provers/DeployOptimismChildToParent.s.sol \
    --rpc-url "$OPTIMISM_SEPOLIA_RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast