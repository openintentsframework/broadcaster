#!/usr/bin/env bash

if [ "$VERIFIER" = "etherscan" ]; then
  VERIFY_FLAGS="--verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY"
else
  VERIFY_FLAGS="--verify --verifier-url $VERIFIER_URL"
fi

CHAIN_TYPE=$CHAIN_TYPE forge script scripts/deployment/DeployProtocol.s.sol \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_PRIVATE_KEY" \
  --broadcast \
  $VERIFY_FLAGS
  