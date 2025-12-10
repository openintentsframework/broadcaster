#!/usr/bin/env bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

source .env
source scripts/taiko/addresses.sh

L1_RPC="https://l1rpc.internal.taiko.xyz"
L2_RPC="https://rpc.internal.taiko.xyz"
L2_SIGNAL_SERVICE="0x1670010000000000000000000000000000000005"
BROADCASTER=$L1_BROADCASTER

echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  L1 → L2 PROOF GENERATOR${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""

# Get tx hash
read -p "Enter L1 tx hash: " TX_HASH

if [ -z "$TX_HASH" ]; then
    echo -e "${RED}No tx hash provided${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}==>${NC} ${GREEN}Fetching transaction receipt...${NC}"

RECEIPT=$(cast receipt $TX_HASH --rpc-url $L1_RPC --json)
BLOCK_HEX=$(echo "$RECEIPT" | jq -r '.blockNumber')
BROADCAST_BLOCK=$((BLOCK_HEX))

# Extract message info from event
EVENT_SIG=$(cast keccak 'MessageBroadcast(bytes32,address)')
LOG=$(echo "$RECEIPT" | jq --arg sig "$EVENT_SIG" '.logs[] | select(.topics[0] == $sig)')

MESSAGE=$(echo "$LOG" | jq -r '.topics[1]')
PUBLISHER_RAW=$(echo "$LOG" | jq -r '.topics[2]')
PUBLISHER="0x${PUBLISHER_RAW:26}"

# Calculate storage slot
ENCODED=$(cast abi-encode 'f(bytes32,address)' "$MESSAGE" "$PUBLISHER")
SLOT=$(cast keccak "$ENCODED")

echo ""
echo -e "${YELLOW}Transaction Info:${NC}"
echo "  Broadcaster:     $BROADCASTER"
echo "  Message:         $MESSAGE"
echo "  Publisher:       $PUBLISHER"
echo "  Broadcast Block: $BROADCAST_BLOCK"
echo "  Storage Slot:    $SLOT"
echo ""

# Check if broadcast block is checkpointed
echo -e "${BLUE}==>${NC} ${GREEN}Checking if block $BROADCAST_BLOCK is checkpointed on L2...${NC}"

SELECTOR="0xd8646ff5"  # getCheckpoint(uint48)
BLOCK_HEX_PADDED=$(printf "%064x" $BROADCAST_BLOCK)

RESULT=$(cast call $L2_SIGNAL_SERVICE "${SELECTOR}${BLOCK_HEX_PADDED}" --rpc-url $L2_RPC 2>/dev/null || echo "error")

if [ "$RESULT" = "error" ] || [ "$RESULT" = "0x" ]; then
    CHECKPOINT_EXISTS=false
else
    CHECKPOINT_HASH=$(echo $RESULT | cut -c67-130)
    if [ "$CHECKPOINT_HASH" = "0000000000000000000000000000000000000000000000000000000000000000" ]; then
        CHECKPOINT_EXISTS=false
    else
        CHECKPOINT_EXISTS=true
    fi
fi

if [ "$CHECKPOINT_EXISTS" = true ]; then
    echo -e "${GREEN}✓ Block $BROADCAST_BLOCK IS checkpointed on L2${NC}"
    PROOF_BLOCK=$BROADCAST_BLOCK
else
    echo -e "${YELLOW}✗ Block $BROADCAST_BLOCK is NOT checkpointed on L2${NC}"
    echo ""
    echo -e "${BLUE}==>${NC} ${GREEN}Searching for nearest checkpointed block...${NC}"

    # Search for a checkpointed block >= BROADCAST_BLOCK
    PROOF_BLOCK=""
    for i in $(seq 0 50); do
        CHECK_BLOCK=$((BROADCAST_BLOCK + i))
        BLOCK_HEX_PADDED=$(printf "%064x" $CHECK_BLOCK)
        RESULT=$(cast call $L2_SIGNAL_SERVICE "${SELECTOR}${BLOCK_HEX_PADDED}" --rpc-url $L2_RPC 2>/dev/null || echo "error")

        if [ "$RESULT" != "error" ] && [ "$RESULT" != "0x" ]; then
            CHECKPOINT_HASH=$(echo $RESULT | cut -c67-130)
            if [ "$CHECKPOINT_HASH" != "0000000000000000000000000000000000000000000000000000000000000000" ]; then
                PROOF_BLOCK=$CHECK_BLOCK
                echo -e "${GREEN}✓ Found checkpoint at block $CHECK_BLOCK${NC}"
                break
            fi
        fi
        printf "\r  Checking block $CHECK_BLOCK..."
    done

    echo ""

    if [ -z "$PROOF_BLOCK" ]; then
        echo -e "${RED}ERROR: No checkpoint found within 50 blocks of $BROADCAST_BLOCK${NC}"
        echo ""
        echo "Options:"
        echo "  1. Wait for more anchor transactions on L2"
        echo "  2. Listen for CheckpointSaved event on L2"
        echo "  3. Manually specify a checkpointed block with --block flag"
        echo ""
        echo "To check manually:"
        echo "  cast call $L2_SIGNAL_SERVICE 'getCheckpoint(uint48)' <BLOCK> --rpc-url $L2_RPC"
        exit 1
    fi
fi

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}IMPORTANT: Generating proof at block $PROOF_BLOCK${NC}"
if [ "$PROOF_BLOCK" != "$BROADCAST_BLOCK" ]; then
    echo -e "${YELLOW}(Broadcast was at $BROADCAST_BLOCK, but checkpoint is at $PROOF_BLOCK)${NC}"
fi
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${BLUE}==>${NC} ${GREEN}Generating storage proof...${NC}"
echo ""

cd scripts/storage-proof-generator
node dist/index.cjs \
    --rpc $L1_RPC \
    --account $BROADCASTER \
    --slot $SLOT \
    --block $PROOF_BLOCK \
    --output ../../test/payloads/taiko/taikoProofL1.json
cd ../..

# Save message info
cat > test/payloads/taiko/taikoProofL1-info.json << EOF
{
  "message": "$MESSAGE",
  "publisher": "$PUBLISHER",
  "broadcaster": "$BROADCASTER",
  "broadcastBlock": $BROADCAST_BLOCK,
  "proofBlock": $PROOF_BLOCK,
  "slot": "$SLOT",
  "txHash": "$TX_HASH",
  "note": "Proof generated at checkpointed block $PROOF_BLOCK (broadcast was at $BROADCAST_BLOCK)"
}
EOF

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  PROOF GENERATED SUCCESSFULLY${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Files saved:"
echo "  - test/payloads/taiko/taikoProofL1.json"
echo "  - test/payloads/taiko/taikoProofL1-info.json"
echo ""
echo "To verify on L2, run:"
echo "  forge test --mt test_verifyBroadcastMessage_from_Ethereum -vv"
echo ""
