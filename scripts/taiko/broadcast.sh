#!/usr/bin/env bash
# Broadcast messages on Taiko chains
# Usage: ./scripts/taiko/broadcast.sh [l1|l2|both]

set -e

# Load environment variables
source .env

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# RPC URLs
L1_RPC="https://l1rpc.internal.taiko.xyz"
L2_RPC="https://rpc.internal.taiko.xyz"

broadcast_l1() {
    echo -e "${BLUE}Broadcasting message on L1 (Taiko Parent Chain)...${NC}"
    forge script scripts/taiko/broadcast-l1.s.sol:BroadcastL1Message \
        --rpc-url "$L1_RPC" \
        --private-key "$TAIKO_USER_PK" \
        --broadcast
    echo -e "${GREEN}✓ L1 broadcast complete${NC}"
}

broadcast_l2() {
    echo -e "${BLUE}Broadcasting message on L2 (Taiko Child Chain)...${NC}"
    forge script scripts/taiko/broadcast-l2.s.sol:BroadcastL2Message \
        --rpc-url "$L2_RPC" \
        --private-key "$TAIKO_USER_PK" \
        --broadcast
    echo -e "${GREEN}✓ L2 broadcast complete${NC}"
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

