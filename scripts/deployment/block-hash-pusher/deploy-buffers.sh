#!/usr/bin/env bash

CHAIN_TYPE=$CHAIN_TYPE \
PUSHER_CHAIN=$PUSHER_CHAIN \
BUFFER_CHAIN=$BUFFER_CHAIN \
MESSENGER=$MESSENGER \
forge script scripts/deployment/block-hash-pusher/DeployBuffers.s.sol \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_PRIVATE_KEY" \
  --broadcast
  