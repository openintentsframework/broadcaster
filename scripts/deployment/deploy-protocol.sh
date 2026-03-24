#!/usr/bin/env bash

VERIFY_FLAGS=""
if [ "$CHAIN_TYPE" = "zksync" ]; then
  unset ETHERSCAN_API_KEY
  unset VERIFIER
else
  VERIFY_FLAGS="--verify --verifier $VERIFIER --etherscan-api-key $ETHERSCAN_API_KEY"
fi

CHAIN_TYPE=$CHAIN_TYPE forge script scripts/deployment/DeployProtocol.s.sol \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_PRIVATE_KEY" \
  --broadcast \
  $VERIFY_FLAGS
  