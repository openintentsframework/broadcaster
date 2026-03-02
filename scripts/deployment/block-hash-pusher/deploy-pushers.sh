#!/usr/bin/env bash

LINEA_ROLLUP=$LINEA_ROLLUP \
L1_SCROLL_MESSENGER=$L1_SCROLL_MESSENGER \
ZKSYNC_DIAMOND=$ZKSYNC_DIAMOND \
OP_L1_CROSS_DOMAIN_MESSENGER_PROXY=$OP_L1_CROSS_DOMAIN_MESSENGER_PROXY \
forge script scripts/deployment/block-hash-pusher/DeployPushers.s.sol \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_PRIVATE_KEY" \
  --broadcast
  