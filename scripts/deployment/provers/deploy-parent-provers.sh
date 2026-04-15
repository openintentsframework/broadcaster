#!/usr/bin/env bash

if [ "$VERIFIER" = "etherscan" ]; then
  VERIFY_FLAGS="--verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY"
else
  VERIFY_FLAGS="--verify --verifier-url $VERIFIER_URL"
fi

OUTBOX=$ARBITRUM_OUTBOX \
ROOTS_SLOT=$ARBITRUM_ROOTS_SLOT \
HOME_CHAIN_ID=$ETHEREUM_CHAIN_ID \
TARGET_CHAIN_ID=$ARBITRUM_CHAIN_ID \
forge script scripts/deployment/provers/DeployArbitrumParentToChild.s.sol \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast \
    $VERIFY_FLAGS


ROLLUP=$LINEA_ROLLUP \
STATE_ROOT_HASHES_SLOT=$LINEA_STATE_ROOT_HASHES_SLOT \
HOME_CHAIN_ID=$ETHEREUM_CHAIN_ID \
TARGET_CHAIN_ID=$LINEA_CHAIN_ID \
forge script scripts/deployment/provers/DeployLineaParentToChild.s.sol \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast \
    $VERIFY_FLAGS


SCROLL_CHAIN=$SCROLL_CHAIN \
FINALIZED_STATE_ROOTS_SLOT=$SCROLL_FINALIZED_STATE_ROOT_SLOT \
HOME_CHAIN_ID=$ETHEREUM_CHAIN_ID \
TARGET_CHAIN_ID=$SCROLL_CHAIN_ID \
forge script scripts/deployment/provers/DeployScrollParentToChild.s.sol \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast \
    $VERIFY_FLAGS


ANCHOR_STATE_REGISTRY=$OPTIMISM_ANCHOR_STATE_REGISTRY \
ANCHOR_GAME_SLOT=$OPTIMISM_ANCHOR_GAME_SLOT \
HOME_CHAIN_ID=$ETHEREUM_CHAIN_ID \
TARGET_CHAIN_ID=$OPTIMISM_CHAIN_ID \
forge script scripts/deployment/provers/DeployOptimismParentToChild.s.sol \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast \
    $VERIFY_FLAGS

ANCHOR_STATE_REGISTRY=$BASE_ANCHOR_STATE_REGISTRY \
ANCHOR_GAME_SLOT=$BASE_ANCHOR_GAME_SLOT \
HOME_CHAIN_ID=$ETHEREUM_CHAIN_ID \
TARGET_CHAIN_ID=$BASE_CHAIN_ID \
forge script scripts/deployment/provers/DeployOptimismParentToChild.s.sol \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast \
    $VERIFY_FLAGS

GATEWAY_ZK_CHAIN=$ZKSYNC_GATEWAY_ZK_CHAIN \
L2_LOGS_ROOT_HASH_SLOT=$ZKSYNC_L2_LOGS_ROOT_HASH_SLOT \
CHILD_CHAIN_ID=$ZKSYNC_CHAIN_ID \
GATEWAY_CHAIN_ID=$ZKSYNC_GATEWAY_CHAIN_ID \
HOME_CHAIN_ID=$ETHEREUM_CHAIN_ID \
TARGET_CHAIN_ID=$ZKSYNC_CHAIN_ID \
forge script scripts/deployment/provers/DeployZkSyncParentToChild.s.sol \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast \
    $VERIFY_FLAGS










