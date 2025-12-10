#!/usr/bin/env bash
# Common functions and variables for E2E scripts

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Load environment and configuration
source .env
source scripts/taiko/config.sh
source scripts/taiko/addresses.sh

# Output functions
print_header() {
    echo -e "\n${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}\n"
}

print_step() {
    echo -e "\n${BLUE}==>${NC} ${GREEN}$1${NC}"
}

print_info() {
    echo -e "${YELLOW}$1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ Error: $1${NC}"
}

# Check if a checkpoint exists for a given block
check_checkpoint() {
    local signal_service=$1
    local rpc=$2
    local block_number=$3

    local SELECTOR="0xd8646ff5"  # getCheckpoint(uint48)
    local BLOCK_HEX=$(printf "%064x" $block_number)

    local RESULT=$(cast call $signal_service "${SELECTOR}${BLOCK_HEX}" --rpc-url $rpc 2>/dev/null || echo "error")

    if [ "$RESULT" = "error" ] || [ "$RESULT" = "0x" ]; then
        return 1
    fi

    local CHECKPOINT_HASH=$(echo $RESULT | cut -c67-130)
    if [ "$CHECKPOINT_HASH" = "0000000000000000000000000000000000000000000000000000000000000000" ]; then
        return 1
    fi

    return 0
}

# Wait for a checkpoint to appear (any block >= target)
# Polls every 10 seconds (~1-2 L2 blocks), max 30 attempts (5 minutes)
wait_for_checkpoint() {
    local signal_service=$1
    local rpc=$2
    local block_number=$3
    local max_attempts=${4:-30}

    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        # Try to find any checkpoint >= block_number
        local found=$(find_checkpointed_block "$signal_service" "$rpc" "$block_number")
        if [ -n "$found" ]; then
            FOUND_CHECKPOINT_BLOCK=$found
            return 0
        fi

        attempt=$((attempt + 1))
        printf "\r  Waiting for checkpoint >= $block_number... attempt $attempt/$max_attempts (every 10s)"
        sleep 10
    done
    echo ""
    return 1
}

# Find the nearest checkpointed block >= given block
# Queries recent CheckpointSaved events (last ~50 L2 blocks, ~6 checkpoints)
find_checkpointed_block() {
    local signal_service=$1
    local rpc=$2
    local start_block=$3

    # Get current block on the destination chain (suppress warnings)
    local current_block=$(cast block-number --rpc-url "$rpc" 2>&1 | grep -E '^[0-9]+$')
    if [ -z "$current_block" ]; then
        return 1
    fi

    # Search last 50 blocks for CheckpointSaved events (~6 checkpoints worth)
    local from_block=$((current_block - 50))
    if [ $from_block -lt 0 ]; then
        from_block=0
    fi

    # Event: CheckpointSaved(uint48 indexed blockNumber, bytes32 blockHash, bytes32 stateRoot)
    local EVENT_SIG="0xf726c53cbb9e62552afc4a8f1bb1d01fa9272e526a7e3a69eba93b778b3f42a6"

    # Capture JSON output, filtering out any warning lines
    local LOGS=$(cast logs \
        --from-block $from_block \
        --to-block latest \
        --address "$signal_service" \
        "$EVENT_SIG" \
        --rpc-url "$rpc" \
        --json 2>&1 | grep -v "^Warning:" | grep -v "^This notation" | grep -v "^Please use")

    # Check if we got valid JSON
    if [ -z "$LOGS" ] || [ "$LOGS" = "[]" ] || ! echo "$LOGS" | jq . >/dev/null 2>&1; then
        return 1
    fi

    # Parse logs and find the smallest checkpointed block >= start_block
    local found_block=""
    for topic1 in $(echo "$LOGS" | jq -r '.[].topics[1]' 2>/dev/null); do
        local checkpoint_block=$(cast --to-dec "$topic1" 2>&1 | grep -E '^[0-9]+$')
        if [ -n "$checkpoint_block" ] && [ "$checkpoint_block" -ge "$start_block" ]; then
            if [ -z "$found_block" ] || [ "$checkpoint_block" -lt "$found_block" ]; then
                found_block=$checkpoint_block
            fi
        fi
    done

    if [ -n "$found_block" ]; then
        echo $found_block
        return 0
    fi

    return 1
}

# Extract message info from a transaction receipt
extract_message_info() {
    local receipt=$1

    EVENT_SIG=$(cast keccak 'MessageBroadcast(bytes32,address)')
    LOG=$(echo "$receipt" | jq --arg sig "$EVENT_SIG" '.logs[] | select(.topics[0] == $sig)')

    RESULT_MESSAGE=$(echo "$LOG" | jq -r '.topics[1]')
    PUBLISHER_RAW=$(echo "$LOG" | jq -r '.topics[2]')
    RESULT_PUBLISHER="0x${PUBLISHER_RAW:26}"

    ENCODED=$(cast abi-encode 'f(bytes32,address)' "$RESULT_MESSAGE" "$RESULT_PUBLISHER")
    RESULT_SLOT=$(cast keccak "$ENCODED")
}

# Generate storage proof using openintents-storage-proof-generator (npm package)
generate_proof() {
    local rpc=$1
    local account=$2
    local slot=$3
    local block=$4
    local output=$5

    storage-proof-generator \
        --rpc "$rpc" \
        --account "$account" \
        --slot "$slot" \
        --block "$block" \
        --output "$output"
}
