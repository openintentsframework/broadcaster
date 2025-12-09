#!/usr/bin/env bash
set -e

source .env
source scripts/taiko/addresses.sh

L1_RPC="https://l1rpc.internal.taiko.xyz"
L2_RPC="https://rpc.internal.taiko.xyz"

broadcast_l1() {
    forge script scripts/taiko/broadcast-l1.s.sol:BroadcastL1Message \
        --rpc-url "$L1_RPC" \
        --private-key "$TAIKO_USER_PK" \
        --broadcast -vv
}

broadcast_l2() {
    forge script scripts/taiko/broadcast-l2.s.sol:BroadcastL2Message \
        --rpc-url "$L2_RPC" \
        --private-key "$TAIKO_USER_PK" \
        --broadcast -vv
}

case "${1:-both}" in
    l1)
        broadcast_l1
        ;;
    l2)
        broadcast_l2
        ;;
    both)
        broadcast_l1
        echo ""
        broadcast_l2
        ;;
    *)
        echo "Usage: $0 [l1|l2|both]"
        exit 1
        ;;
esac

