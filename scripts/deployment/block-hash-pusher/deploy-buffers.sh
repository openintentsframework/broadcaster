#!/usr/bin/env bash

CHAIN_TYPE=$CHAIN_TYPE \
PARENT_CHAIN=$PARENT_CHAIN \
CHILD_CHAIN=$CHILD_CHAIN \
MESSENGER=$MESSENGER \
forge script scripts/deployment/block-hash-pusher/DeployBuffers.s.sol \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_PRIVATE_KEY" \
  --broadcast
  