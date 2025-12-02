#!/usr/bin/env bash
set -e

# Change to project root
cd "$(dirname "$0")/../../.."

# Suppress foundry config warnings globally
export FOUNDRY_CONFIG="foundry.toml"

source scripts/taiko/e2e/common.sh

print_header "TAIKO E2E TEST"

echo "This script performs a complete end-to-end test:"
echo "  1. Broadcast a message on source chain"
echo "  2. Wait for checkpoint on destination chain"
echo "  3. Generate storage proof (at checkpointed block)"
echo "  4. Verify the message on destination chain"
echo ""

DIRECTION=${1:-l1-to-l2}

case "$DIRECTION" in
    l1-to-l2)
        print_header "L1 → L2 E2E TEST"
        echo "Flow: Broadcast on L1 → Wait for L2 checkpoint → Verify on L2"
        echo ""

        SOURCE_RPC=$L1_RPC
        SOURCE_CHAIN_ID=$L1_CHAIN_ID
        SOURCE_BROADCASTER=$L1_BROADCASTER
        DEST_RPC=$L2_RPC
        DEST_SIGNAL_SERVICE=$L2_SIGNAL_SERVICE
        BROADCAST_SCRIPT="scripts/taiko/broadcast-l1.s.sol:BroadcastL1Message"
        PROOF_OUTPUT="test/payloads/taiko/taikoProofL1.json"
        INFO_OUTPUT="test/payloads/taiko/taikoProofL1-info.json"
        TEST_NAME="test_verifyBroadcastMessage_from_Ethereum"
        ;;

    l2-to-l1)
        print_header "L2 → L1 E2E TEST"
        echo "Flow: Broadcast on L2 → Wait for L1 checkpoint → Verify on L1"
        echo ""

        SOURCE_RPC=$L2_RPC
        SOURCE_CHAIN_ID=$L2_CHAIN_ID
        SOURCE_BROADCASTER=$L2_BROADCASTER
        DEST_RPC=$L1_RPC
        DEST_SIGNAL_SERVICE=$L1_SIGNAL_SERVICE
        BROADCAST_SCRIPT="scripts/taiko/broadcast-l2.s.sol:BroadcastL2Message"
        PROOF_OUTPUT="test/payloads/taiko/taikoProofL2.json"
        INFO_OUTPUT="test/payloads/taiko/taikoProofL2-info.json"
        TEST_NAME="test_verifyBroadcastMessage_from_TaikoL2"
        ;;

    *)
        echo "Usage: $0 [l1-to-l2|l2-to-l1]"
        echo ""
        echo "  l1-to-l2  - Broadcast on L1, verify on L2 (default)"
        echo "  l2-to-l1  - Broadcast on L2, verify on L1"
        exit 1
        ;;
esac

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: BROADCAST MESSAGE
# ═══════════════════════════════════════════════════════════════════════════════

print_step "Step 1: Broadcasting message..."

FORGE_OUTPUT=$(forge script "$BROADCAST_SCRIPT" \
    --rpc-url "$SOURCE_RPC" \
    --private-key "$TAIKO_USER_PK" \
    --broadcast -vv 2>&1) || {
    print_error "Forge script failed"
    echo "$FORGE_OUTPUT"
    exit 1
}

echo "$FORGE_OUTPUT"

# Extract TX hash from broadcast file
SCRIPT_FILE=$(echo "$BROADCAST_SCRIPT" | sed 's|scripts/taiko/||' | sed 's|:.*||')
BROADCAST_FILE="broadcast/${SCRIPT_FILE}/${SOURCE_CHAIN_ID}/run-latest.json"

if [ ! -f "$BROADCAST_FILE" ]; then
    print_error "Broadcast file not found: $BROADCAST_FILE"
    exit 1
fi

TX_HASH=$(jq -r '.transactions[0].hash' "$BROADCAST_FILE")
print_success "Transaction hash: $TX_HASH"

# Wait for indexing
sleep 3

# Get receipt
RECEIPT=$(cast receipt "$TX_HASH" --rpc-url "$SOURCE_RPC" --json)
BLOCK_HEX=$(echo "$RECEIPT" | jq -r '.blockNumber')
BROADCAST_BLOCK=$((BLOCK_HEX))

print_success "Message broadcast in block: $BROADCAST_BLOCK"

# Extract message info
extract_message_info "$RECEIPT"

echo ""
echo "  Message:      $RESULT_MESSAGE"
echo "  Publisher:    $RESULT_PUBLISHER"
echo "  Storage Slot: $RESULT_SLOT"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: WAIT FOR CHECKPOINT
# ═══════════════════════════════════════════════════════════════════════════════

print_step "Step 2: Waiting for checkpoint on destination chain..."

# First check if broadcast block is already checkpointed
set +e
check_checkpoint "$DEST_SIGNAL_SERVICE" "$DEST_RPC" "$BROADCAST_BLOCK"
CHECK_RESULT=$?
set -e

if [ $CHECK_RESULT -eq 0 ]; then
    print_success "Block $BROADCAST_BLOCK is already checkpointed!"
    PROOF_BLOCK=$BROADCAST_BLOCK
else
    print_info "Block $BROADCAST_BLOCK is not checkpointed yet"
    echo ""

    # Search for nearest checkpointed block >= BROADCAST_BLOCK
    echo "Searching for checkpoint >= $BROADCAST_BLOCK in recent events..."

    # Disable exit on error for this call since it may return 1 if not found
    set +e
    PROOF_BLOCK=$(find_checkpointed_block "$DEST_SIGNAL_SERVICE" "$DEST_RPC" "$BROADCAST_BLOCK")
    FIND_RESULT=$?
    set -e

    if [ $FIND_RESULT -eq 0 ] && [ -n "$PROOF_BLOCK" ]; then
        print_success "Found checkpoint at block $PROOF_BLOCK"
    else
        echo ""
        print_info "No checkpoint found yet. Waiting (polling every 10s, max 5 min)..."
        echo ""

        if wait_for_checkpoint "$DEST_SIGNAL_SERVICE" "$DEST_RPC" "$BROADCAST_BLOCK" 30; then
            PROOF_BLOCK=$FOUND_CHECKPOINT_BLOCK
            echo ""
            print_success "Found checkpoint at block $PROOF_BLOCK"
        else
            print_error "No checkpoint found after 5 minutes"
            echo ""
            echo "Try running: ./scripts/taiko/e2e/wait-for-checkpoint.sh $BROADCAST_BLOCK $DIRECTION"
            exit 1
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: GENERATE PROOF
# ═══════════════════════════════════════════════════════════════════════════════

print_step "Step 3: Generating storage proof at block $PROOF_BLOCK..."

if [ "$PROOF_BLOCK" != "$BROADCAST_BLOCK" ]; then
    print_info "Note: Broadcast was at block $BROADCAST_BLOCK, proof at checkpointed block $PROOF_BLOCK"
fi

generate_proof "$SOURCE_RPC" "$SOURCE_BROADCASTER" "$RESULT_SLOT" "$PROOF_BLOCK" "$PROOF_OUTPUT"

# Save info JSON
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

print_success "Proof saved to: $PROOF_OUTPUT"
print_success "Info saved to: $INFO_OUTPUT"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: VERIFY MESSAGE
# ═══════════════════════════════════════════════════════════════════════════════

print_step "Step 4: Verifying message with forge test..."

echo ""
echo "Running: forge test --mt $TEST_NAME -vv"
echo ""

forge test --mt "$TEST_NAME" -vv

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

print_header "E2E TEST COMPLETE"

echo -e "${GREEN}Summary:${NC}"
echo "  Direction:      $DIRECTION"
echo "  TX Hash:        $TX_HASH"
echo "  Broadcast Block: $BROADCAST_BLOCK"
echo "  Proof Block:    $PROOF_BLOCK"
echo "  Message:        $RESULT_MESSAGE"
echo "  Publisher:      $RESULT_PUBLISHER"
echo ""
echo -e "${GREEN}All steps completed successfully!${NC}"
echo ""
