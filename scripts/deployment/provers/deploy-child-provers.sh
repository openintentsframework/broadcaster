#!/usr/bin/env bash

HOME_CHAIN_ID=$ARBITRUM_CHAIN_ID \
TARGET_CHAIN_ID=$ETHEREUM_CHAIN_ID \
forge script scripts/deployment/provers/DeployArbitrumChildToParent.s.sol \
    --rpc-url "$ARBITRUM_RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast \
    --verify \
    --verifier $VERIFIER \
    --etherscan-api-key $ETHERSCAN_API_KEY

HOME_CHAIN_ID=$LINEA_CHAIN_ID \
TARGET_CHAIN_ID=$ETHEREUM_CHAIN_ID \
forge script scripts/deployment/provers/DeployLineaChildToParent.s.sol \
    --rpc-url "$LINEA_RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast \
    --verify \
    --verifier $VERIFIER \
    --etherscan-api-key $ETHERSCAN_API_KEY

HOME_CHAIN_ID=$SCROLL_CHAIN_ID \
TARGET_CHAIN_ID=$ETHEREUM_CHAIN_ID \
forge script scripts/deployment/provers/DeployScrollChildToParent.s.sol \
    --rpc-url "$SCROLL_RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast \
    --verify \
    --verifier $VERIFIER \
    --etherscan-api-key $ETHERSCAN_API_KEY

HOME_CHAIN_ID=$OPTIMISM_CHAIN_ID \
TARGET_CHAIN_ID=$ETHEREUM_CHAIN_ID \
forge script scripts/deployment/provers/DeployOptimismChildToParent.s.sol \
    --rpc-url "$OPTIMISM_RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast \
    --verify \
    --verifier $VERIFIER \
    --etherscan-api-key $ETHERSCAN_API_KEY

HOME_CHAIN_ID=$ZKSYNC_CHAIN_ID \
TARGET_CHAIN_ID=$ETHEREUM_CHAIN_ID \
forge script scripts/deployment/provers/DeployZkSyncChildToParent.s.sol \
    --rpc-url "$ZKSYNC_RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast \
    --verify \
    --verifier $VERIFIER \
    --etherscan-api-key $ETHERSCAN_API_KEY