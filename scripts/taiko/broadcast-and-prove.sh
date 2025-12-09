#!/usr/bin/env bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load environment
source .env
source scripts/taiko/addresses.sh

L1_RPC="https://l1rpc.internal.taiko.xyz"
L2_RPC="https://rpc.internal.taiko.xyz"
L1_CHAIN_ID="32382"
L2_CHAIN_ID="167001"

print_step() {
    echo -e "\n${BLUE}==>${NC} ${GREEN}$1${NC}"
}

print_info() {
    echo -e "${YELLOW}$1${NC}"
}

print_error() {
    echo -e "${RED}Error: $1${NC}"
    exit 1
}

# Function to extract TX hash from forge broadcast JSON
extract_tx_hash_from_broadcast() {
    local script_name=$1
    local chain_id=$2

    # Forge saves broadcasts to broadcast/<script>/<chainId>/run-latest.json
    local broadcast_file="broadcast/${script_name}/${chain_id}/run-latest.json"

    if [ ! -f "$broadcast_file" ]; then
        print_error "Broadcast file not found: $broadcast_file"
    fi

    # Extract the transaction hash from the broadcast JSON
    jq -r '.transactions[0].hash' "$broadcast_file"
}

# Function to get slot info from transaction
get_slot_info() {
    local tx_hash=$1
    local rpc=$2
    local broadcaster=$3

    # Get receipt (with retry logic for slow RPCs)
    local max_retries=3
    local retry=0
    RECEIPT=""

    while [ $retry -lt $max_retries ] && [ -z "$RECEIPT" ]; do
        RECEIPT=$(cast receipt "$tx_hash" --rpc-url "$rpc" --json 2>/dev/null) || true
        if [ -z "$RECEIPT" ]; then
            retry=$((retry + 1))
            if [ $retry -lt $max_retries ]; then
                print_info "Retrying receipt fetch ($retry/$max_retries)..."
                sleep 2
            fi
        fi
    done

    if [ -z "$RECEIPT" ]; then
        print_error "Failed to get receipt for $tx_hash after $max_retries attempts"
    fi

    BLOCK_HEX=$(echo "$RECEIPT" | jq -r '.blockNumber')
    BLOCK=$((BLOCK_HEX))

    EVENT_SIG=$(cast keccak 'MessageBroadcast(bytes32,address)')
    LOG=$(echo "$RECEIPT" | jq --arg sig "$EVENT_SIG" '.logs[] | select(.topics[0] == $sig)')

    if [ -z "$LOG" ]; then
        print_error "MessageBroadcast event not found in tx $tx_hash"
    fi

    MESSAGE=$(echo "$LOG" | jq -r '.topics[1]')
    PUBLISHER_RAW=$(echo "$LOG" | jq -r '.topics[2]')
    PUBLISHER="0x${PUBLISHER_RAW:26}"

    ENCODED=$(cast abi-encode 'f(bytes32,address)' "$MESSAGE" "$PUBLISHER")
    SLOT=$(cast keccak "$ENCODED")

    # Return values via global variables
    RESULT_BLOCK=$BLOCK
    RESULT_MESSAGE=$MESSAGE
    RESULT_PUBLISHER=$PUBLISHER
    RESULT_SLOT=$SLOT
}

# Function to broadcast on a chain
broadcast_on_chain() {
    local chain=$1
    local rpc=$2
    local script=$3
    local broadcaster=$4
    local output_file=$5
    local chain_id=$6

    print_step "Broadcasting message on $chain..."

    # Run forge and capture output
    FORGE_OUTPUT=$(forge script "$script" \
        --rpc-url "$rpc" \
        --private-key "$TAIKO_USER_PK" \
        --broadcast -vv 2>&1) || print_error "Forge script failed"

    echo "$FORGE_OUTPUT"

    # Extract script filename for broadcast path (e.g., "broadcast-l1.s.sol")
    local script_file=$(echo "$script" | sed 's|scripts/taiko/||' | sed 's|:.*||')

    # Extract TX hash from forge broadcast JSON file
    TX_HASH=$(extract_tx_hash_from_broadcast "$script_file" "$chain_id")

    if [ -z "$TX_HASH" ] || [ "$TX_HASH" = "null" ]; then
        print_error "Could not extract transaction hash from broadcast file"
    fi

    print_info "Transaction hash: $TX_HASH"

    # Wait a moment for the tx to be indexed
    print_step "Waiting for transaction to be indexed..."
    sleep 3

    # Get slot info
    print_step "Extracting storage slot from transaction..."
    get_slot_info "$TX_HASH" "$rpc" "$broadcaster"

    echo ""
    echo "  Broadcaster:  $broadcaster"
    echo "  Message:      $RESULT_MESSAGE"
    echo "  Publisher:    $RESULT_PUBLISHER"
    echo "  Block:        $RESULT_BLOCK"
    echo "  Storage Slot: $RESULT_SLOT"

    # Generate proof
    print_step "Generating storage proof..."

    cd scripts/storage-proof-generator
    node dist/index.cjs \
        --rpc "$rpc" \
        --account "$broadcaster" \
        --slot "$RESULT_SLOT" \
        --block "$RESULT_BLOCK" \
        --output "../../$output_file"
    cd ../..

    print_info "Proof saved to: $output_file"

    # Save message info to a separate JSON for tests to read
    local info_file="${output_file%.json}-info.json"
    cat > "$info_file" << EOF
{
  "message": "$RESULT_MESSAGE",
  "publisher": "$RESULT_PUBLISHER",
  "broadcaster": "$broadcaster",
  "block": $RESULT_BLOCK,
  "slot": "$RESULT_SLOT",
  "txHash": "$TX_HASH"
}
EOF
    print_info "Message info saved to: $info_file"

    # Return the tx hash for summary
    echo "$TX_HASH"
}

# Main execution
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}  Taiko Broadcast and Prove Script   ${NC}"
echo -e "${GREEN}======================================${NC}"

CHAIN=${1:-both}

case "$CHAIN" in
    l1)
        print_step "Starting L1 workflow..."
        L1_TX=$(broadcast_on_chain "L1" "$L1_RPC" \
            "scripts/taiko/broadcast-l1.s.sol:BroadcastL1Message" \
            "$L1_BROADCASTER" \
            "test/payloads/taiko/taikoProofL1.json" \
            "$L1_CHAIN_ID")

        echo ""
        echo -e "${GREEN}======================================${NC}"
        echo -e "${GREEN}  L1 Workflow Complete!              ${NC}"
        echo -e "${GREEN}======================================${NC}"
        echo ""
        echo "To verify the L1 message from L2, run:"
        echo -e "${YELLOW}  forge test --mt test_verifyBroadcastMessage_from_Ethereum -vv${NC}"
        ;;

    l2)
        print_step "Starting L2 workflow..."
        L2_TX=$(broadcast_on_chain "L2" "$L2_RPC" \
            "scripts/taiko/broadcast-l2.s.sol:BroadcastL2Message" \
            "$L2_BROADCASTER" \
            "test/payloads/taiko/taikoProofL2.json" \
            "$L2_CHAIN_ID")

        echo ""
        echo -e "${GREEN}======================================${NC}"
        echo -e "${GREEN}  L2 Workflow Complete!              ${NC}"
        echo -e "${GREEN}======================================${NC}"
        echo ""
        echo "To verify the L2 message from L1, run:"
        echo -e "${YELLOW}  forge test --mt test_verifyBroadcastMessage_from_TaikoL2 -vv${NC}"
        ;;

    both)
        print_step "Starting L1 workflow..."
        broadcast_on_chain "L1" "$L1_RPC" \
            "scripts/taiko/broadcast-l1.s.sol:BroadcastL1Message" \
            "$L1_BROADCASTER" \
            "test/payloads/taiko/taikoProofL1.json" \
            "$L1_CHAIN_ID"

        echo ""
        print_step "Starting L2 workflow..."
        broadcast_on_chain "L2" "$L2_RPC" \
            "scripts/taiko/broadcast-l2.s.sol:BroadcastL2Message" \
            "$L2_BROADCASTER" \
            "test/payloads/taiko/taikoProofL2.json" \
            "$L2_CHAIN_ID"

        echo ""
        echo -e "${GREEN}======================================${NC}"
        echo -e "${GREEN}  Both Workflows Complete!           ${NC}"
        echo -e "${GREEN}======================================${NC}"
        echo ""
        echo "To verify L2 message from L1, run:"
        echo -e "${YELLOW}  forge test --mt test_verifyBroadcastMessage_from_TaikoL2 -vv${NC}"
        echo ""
        echo "To verify L1 message from L2, run:"
        echo -e "${YELLOW}  forge test --mt test_verifyBroadcastMessage_from_Ethereum -vv${NC}"
        ;;

    *)
        echo "Usage: $0 [l1|l2|both]"
        echo ""
        echo "  l1   - Broadcast on L1 and generate proof"
        echo "  l2   - Broadcast on L2 and generate proof"
        echo "  both - Broadcast on both chains and generate proofs (default)"
        exit 1
        ;;
esac
