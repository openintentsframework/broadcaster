#!/usr/bin/env bash

forge script scripts/deployment/block-hash-pusher/DeployPushers.s.sol \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_PRIVATE_KEY" \
  --broadcast \
  --verify \
  --verifier $VERIFIER \
  --etherscan-api-key $ETHERSCAN_API_KEY
  