#!/usr/bin/env bash
set -e

source .env
source scripts/taiko/addresses.sh

L1_RPC="https://l1rpc.internal.taiko.xyz"

echo "Verifying message from Taiko L2 on Ethereum L1..."
echo ""

forge script scripts/taiko/verify-message.s.sol:VerifyMessage \
    --rpc-url "$L1_RPC" \
    -vv

echo ""
echo "Message verified successfully!"

