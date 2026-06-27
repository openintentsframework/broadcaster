#!/usr/bin/env bash
if [ "$VERIFIER" = "etherscan" ]; then
  VERIFY_FLAGS="--verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY"
else
  VERIFY_FLAGS="--verify --verifier-url $VERIFIER_URL"
fi

HOME_CHAIN_ID=$ARBITRUM_CHAIN_ID \
TARGET_CHAIN_ID=$ETHEREUM_CHAIN_ID \
forge script scripts/deployment/provers/DeployArbitrumChildToParent.s.sol \
    --rpc-url "$ARBITRUM_RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast \
    $VERIFY_FLAGS

HOME_CHAIN_ID=$LINEA_CHAIN_ID \
TARGET_CHAIN_ID=$ETHEREUM_CHAIN_ID \
forge script scripts/deployment/provers/DeployLineaChildToParent.s.sol \
    --rpc-url "$LINEA_RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast \
    $VERIFY_FLAGS

HOME_CHAIN_ID=$SCROLL_CHAIN_ID \
TARGET_CHAIN_ID=$ETHEREUM_CHAIN_ID \
forge script scripts/deployment/provers/DeployScrollChildToParent.s.sol \
    --rpc-url "$SCROLL_RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast \
    $VERIFY_FLAGS

HOME_CHAIN_ID=$OPTIMISM_CHAIN_ID \
TARGET_CHAIN_ID=$ETHEREUM_CHAIN_ID \
forge script scripts/deployment/provers/DeployOptimismChildToParent.s.sol \
    --rpc-url "$OPTIMISM_RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast \
    $VERIFY_FLAGS

HOME_CHAIN_ID=$BASE_CHAIN_ID \
TARGET_CHAIN_ID=$ETHEREUM_CHAIN_ID \
forge script scripts/deployment/provers/DeployOptimismChildToParent.s.sol \
    --rpc-url "$BASE_RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast \
    $VERIFY_FLAGS

HOME_CHAIN_ID=$UNICHAIN_CHAIN_ID \
TARGET_CHAIN_ID=$ETHEREUM_CHAIN_ID \
forge script scripts/deployment/provers/DeployOptimismChildToParent.s.sol \
    --rpc-url "$UNICHAIN_RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast \
    $VERIFY_FLAGS

HOME_CHAIN_ID=$WORLD_CHAIN_ID \
TARGET_CHAIN_ID=$ETHEREUM_CHAIN_ID \
forge script scripts/deployment/provers/DeployOptimismChildToParent.s.sol \
    --rpc-url "$WORLD_RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast \
    $VERIFY_FLAGS

HOME_CHAIN_ID=$ZKSYNC_CHAIN_ID \
TARGET_CHAIN_ID=$ETHEREUM_CHAIN_ID \
forge script scripts/deployment/provers/DeployZkSyncChildToParent.s.sol \
    --rpc-url "$ZKSYNC_RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --broadcast \
    $VERIFY_FLAGS