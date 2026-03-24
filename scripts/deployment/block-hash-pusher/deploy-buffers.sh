#!/usr/bin/env bash

VERIFY_FLAGS=""
if [ "$CHAIN_TYPE" != "zksync" ]; then
  VERIFY_FLAGS="--verify --verifier $VERIFIER --etherscan-api-key $ETHERSCAN_API_KEY"
fi

forge script scripts/deployment/block-hash-pusher/DeployBuffers.s.sol \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_PRIVATE_KEY" \
  --broadcast \
  $VERIFY_FLAGS
  