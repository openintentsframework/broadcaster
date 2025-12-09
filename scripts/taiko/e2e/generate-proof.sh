#!/usr/bin/env bash
set -e

# Change to project root
cd "$(dirname "$0")/../../.."

source scripts/taiko/e2e/common.sh

print_header "STORAGE PROOF GENERATOR"

echo "This script generates a storage proof for a broadcast message."
echo "It automatically finds the correct checkpointed block."
echo ""

# Get parameters
read -p "Enter TX hash: " TX_HASH
echo ""
echo "Direction:"
echo "  1. l1-to-l2 (L1 broadcast → verify on L2)"
echo "  2. l2-to-l1 (L2 broadcast → verify on L1)"
read -p "Select direction [1/2]: " DIR_CHOICE

case "$DIR_CHOICE" in
    1|l1-to-l2)
        DIRECTION="l1-to-l2"
        SOURCE_RPC=$L1_RPC
        SOURCE_BROADCASTER=$L1_BROADCASTER
        DEST_SIGNAL_SERVICE=$L2_SIGNAL_SERVICE
        DEST_RPC=$L2_RPC
        PROOF_OUTPUT="test/payloads/taiko/taikoProofL1.json"
        INFO_OUTPUT="test/payloads/taiko/taikoProofL1-info.json"
        ;;
    2|l2-to-l1)
        DIRECTION="l2-to-l1"
        SOURCE_RPC=$L2_RPC
        SOURCE_BROADCASTER=$L2_BROADCASTER
        DEST_SIGNAL_SERVICE=$L1_SIGNAL_SERVICE
        DEST_RPC=$L1_RPC
        PROOF_OUTPUT="test/payloads/taiko/taikoProofL2.json"
        INFO_OUTPUT="test/payloads/taiko/taikoProofL2-info.json"
        ;;
    *)
        print_error "Invalid choice"
        exit 1
        ;;
esac

# Get receipt
print_step "Fetching transaction receipt..."

RECEIPT=$(cast receipt "$TX_HASH" --rpc-url "$SOURCE_RPC" --json) || {
    print_error "Failed to fetch receipt for $TX_HASH"
    exit 1
}

BLOCK_HEX=$(echo "$RECEIPT" | jq -r '.blockNumber')
BROADCAST_BLOCK=$((BLOCK_HEX))

# Extract message info
extract_message_info "$RECEIPT"

echo ""
echo "Transaction Info:"
echo "  Broadcaster:     $SOURCE_BROADCASTER"
echo "  Message:         $RESULT_MESSAGE"
echo "  Publisher:       $RESULT_PUBLISHER"
echo "  Broadcast Block: $BROADCAST_BLOCK"
echo "  Storage Slot:    $RESULT_SLOT"

# Find checkpointed block
print_step "Finding checkpointed block..."

if check_checkpoint "$DEST_SIGNAL_SERVICE" "$DEST_RPC" "$BROADCAST_BLOCK"; then
    print_success "Block $BROADCAST_BLOCK is checkpointed"
    PROOF_BLOCK=$BROADCAST_BLOCK
else
    print_info "Block $BROADCAST_BLOCK is not checkpointed"
    echo "Searching for nearest checkpointed block..."

    PROOF_BLOCK=$(find_checkpointed_block "$DEST_SIGNAL_SERVICE" "$DEST_RPC" "$BROADCAST_BLOCK" 100) || {
        print_error "No checkpointed block found within 100 blocks"
        echo ""
        echo "Options:"
        echo "  1. Wait for checkpoint: ./scripts/taiko/e2e/wait-for-checkpoint.sh $BROADCAST_BLOCK $DIRECTION"
        echo "  2. Run full E2E: ./scripts/taiko/e2e/run.sh $DIRECTION"
        exit 1
    }

    print_success "Found checkpoint at block $PROOF_BLOCK"
fi

# Generate proof
print_step "Generating proof at block $PROOF_BLOCK..."

if [ "$PROOF_BLOCK" != "$BROADCAST_BLOCK" ]; then
    print_info "Note: Using checkpointed block $PROOF_BLOCK (broadcast was at $BROADCAST_BLOCK)"
fi

generate_proof "$SOURCE_RPC" "$SOURCE_BROADCASTER" "$RESULT_SLOT" "$PROOF_BLOCK" "$PROOF_OUTPUT"

# Save info
cat > "$INFO_OUTPUT" << EOF
{
  "message": "$RESULT_MESSAGE",
  "publisher": "$RESULT_PUBLISHER",
  "broadcaster": "$SOURCE_BROADCASTER",
  "broadcastBlock": $BROADCAST_BLOCK,
  "proofBlock": $PROOF_BLOCK,
  "slot": "$RESULT_SLOT",
  "txHash": "$TX_HASH",
  "direction": "$DIRECTION"
}
EOF

print_header "PROOF GENERATED"

echo "Files saved:"
echo "  - $PROOF_OUTPUT"
echo "  - $INFO_OUTPUT"
echo ""
echo "To verify, run:"
if [ "$DIRECTION" = "l1-to-l2" ]; then
    echo "  forge test --mt test_verifyBroadcastMessage_from_Ethereum -vv"
else
    echo "  forge test --mt test_verifyBroadcastMessage_from_TaikoL2 -vv"
fi
echo ""
