#!/usr/bin/env bash

forge script scripts/deployment/DeployProtocol.s.sol \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_PRIVATE_KEY" \
  --broadcast
  