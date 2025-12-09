#!/usr/bin/env bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# SignalService addresses
L1_SIGNAL_SERVICE="0x53789e39E3310737E8C8cED483032AAc25B39ded"
L2_SIGNAL_SERVICE="0x1670010000000000000000000000000000000005"

L1_RPC="https://l1rpc.internal.taiko.xyz"
L2_RPC="https://rpc.internal.taiko.xyz"

# CheckpointSaved event signature
CHECKPOINT_SAVED_SIG=$(cast keccak "CheckpointSaved(uint48,bytes32,bytes32)")

print_step() {
    echo -e "\n${BLUE}==>${NC} ${GREEN}$1${NC}"
}

print_info() {
    echo -e "${YELLOW}$1${NC}"
}

usage() {
    echo "Usage: $0 <block_number> <direction>"
    echo ""
    echo "  block_number  - The block number to wait for checkpoint"
    echo "  direction     - 'l2-to-l1' or 'l1-to-l2'"
    echo ""
    echo "Examples:"
    echo "  $0 10875 l2-to-l1   # Wait for L2 block 10875 to be checkpointed on L1"
    echo "  $0 67914 l1-to-l2   # Wait for L1 block 67914 to be checkpointed on L2"
    exit 1
}

if [ -z "$1" ] || [ -z "$2" ]; then
    usage
fi

BLOCK_NUMBER=$1
DIRECTION=$2

case "$DIRECTION" in
    l2-to-l1)
        SIGNAL_SERVICE=$L1_SIGNAL_SERVICE
        RPC=$L1_RPC
        print_step "Waiting for L2 block $BLOCK_NUMBER to be checkpointed on L1..."
        print_info "Watching L1 SignalService: $SIGNAL_SERVICE"
        ;;
    l1-to-l2)
        SIGNAL_SERVICE=$L2_SIGNAL_SERVICE
        RPC=$L2_RPC
        print_step "Waiting for L1 block $BLOCK_NUMBER to be checkpointed on L2..."
        print_info "Watching L2 SignalService: $SIGNAL_SERVICE"
        ;;
    *)
        echo "Error: direction must be 'l2-to-l1' or 'l1-to-l2'"
        usage
        ;;
esac

echo ""
echo "Event signature: $CHECKPOINT_SAVED_SIG"
echo ""

# Try to get the checkpoint directly first
print_step "Checking if checkpoint already exists..."

# Call getCheckpoint(uint48) - selector is 0xd8646ff5
SELECTOR="0xd8646ff5"
BLOCK_HEX=$(printf "%064x" $BLOCK_NUMBER)

RESULT=$(cast call $SIGNAL_SERVICE "${SELECTOR}${BLOCK_HEX}" --rpc-url $RPC 2>/dev/null || echo "error")

if [ "$RESULT" != "error" ] && [ "$RESULT" != "0x" ]; then
    # Decode the result (blockNumber, blockHash, stateRoot)
    # Skip first 64 chars (0x + offset), then get blockNumber (64 chars), blockHash (64), stateRoot (64)
    CHECKPOINT_BLOCK=$(echo $RESULT | cut -c3-66)
    CHECKPOINT_HASH=$(echo $RESULT | cut -c67-130)
    CHECKPOINT_STATE=$(echo $RESULT | cut -c131-194)

    if [ "$CHECKPOINT_HASH" != "0000000000000000000000000000000000000000000000000000000000000000" ]; then
        echo -e "${GREEN}Checkpoint already exists!${NC}"
        echo ""
        echo "Block Number: $BLOCK_NUMBER"
        echo "Block Hash:   0x$CHECKPOINT_HASH"
        echo "State Root:   0x$CHECKPOINT_STATE"
        exit 0
    fi
fi

print_info "Checkpoint not found yet. Polling for new checkpoints..."
echo ""

# Poll for checkpoint
MAX_ATTEMPTS=120  # 10 minutes at 5 second intervals
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))

    # Check for recent CheckpointSaved events
    LATEST_BLOCK=$(cast block-number --rpc-url $RPC)
    FROM_BLOCK=$((LATEST_BLOCK - 100))
    if [ $FROM_BLOCK -lt 0 ]; then
        FROM_BLOCK=0
    fi

    # Get logs for CheckpointSaved event
    LOGS=$(cast logs --from-block $FROM_BLOCK --to-block latest \
        --address $SIGNAL_SERVICE \
        $CHECKPOINT_SAVED_SIG \
        --rpc-url $RPC --json 2>/dev/null || echo "[]")

    # Check if our block number is in the logs
    # The blockNumber is indexed (topic[1])
    BLOCK_HEX_PADDED=$(printf "0x%064x" $BLOCK_NUMBER)

    FOUND=$(echo "$LOGS" | jq -r --arg bn "$BLOCK_HEX_PADDED" '.[] | select(.topics[1] == $bn)')

    if [ -n "$FOUND" ]; then
        BLOCK_HASH=$(echo "$FOUND" | jq -r '.data' | cut -c3-66)
        STATE_ROOT=$(echo "$FOUND" | jq -r '.data' | cut -c67-130)

        echo -e "${GREEN}Checkpoint found!${NC}"
        echo ""
        echo "Block Number: $BLOCK_NUMBER"
        echo "Block Hash:   0x$BLOCK_HASH"
        echo "State Root:   0x$STATE_ROOT"
        echo ""
        echo "Transaction:  $(echo "$FOUND" | jq -r '.transactionHash')"
        exit 0
    fi

    printf "\rWaiting... attempt $ATTEMPT/$MAX_ATTEMPTS (checking every 5s)"
    sleep 5
done

echo ""
echo -e "${RED}Timeout: Checkpoint not found after $MAX_ATTEMPTS attempts${NC}"
echo ""
echo "The checkpoint for block $BLOCK_NUMBER may not be created yet."
echo "Possible reasons:"
echo "  - L2 proposals not finalized yet (for L2→L1)"
echo "  - No anchor transaction yet (for L1→L2)"
echo "  - Rate limiting (minCheckpointDelay)"
exit 1
