#!/usr/bin/env bash
set -e

# Change to project root
cd "$(dirname "$0")/../../.."

source scripts/taiko/e2e/common.sh

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <block_number> <direction>"
    echo ""
    echo "  block_number  - The block number to wait for"
    echo "  direction     - 'l1-to-l2' or 'l2-to-l1'"
    echo ""
    echo "Examples:"
    echo "  $0 67914 l1-to-l2   # Wait for L1 block 67914 to be checkpointed on L2"
    echo "  $0 10875 l2-to-l1   # Wait for L2 block 10875 to be checkpointed on L1"
    exit 1
fi

BLOCK_NUMBER=$1
DIRECTION=$2

case "$DIRECTION" in
    l1-to-l2)
        SIGNAL_SERVICE=$L2_SIGNAL_SERVICE
        RPC=$L2_RPC
        print_header "Waiting for L1 block $BLOCK_NUMBER on L2"
        print_info "Checking L2 SignalService: $SIGNAL_SERVICE"
        ;;
    l2-to-l1)
        SIGNAL_SERVICE=$L1_SIGNAL_SERVICE
        RPC=$L1_RPC
        print_header "Waiting for L2 block $BLOCK_NUMBER on L1"
        print_info "Checking L1 SignalService: $SIGNAL_SERVICE"
        ;;
    *)
        print_error "Direction must be 'l1-to-l2' or 'l2-to-l1'"
        exit 1
        ;;
esac

echo ""

# Check if checkpoint already exists
print_step "Checking if checkpoint already exists..."

if check_checkpoint "$SIGNAL_SERVICE" "$RPC" "$BLOCK_NUMBER"; then
    print_success "Checkpoint already exists for block $BLOCK_NUMBER!"

    # Get checkpoint details
    SELECTOR="0xd8646ff5"
    BLOCK_HEX=$(printf "%064x" $BLOCK_NUMBER)
    RESULT=$(cast call $SIGNAL_SERVICE "${SELECTOR}${BLOCK_HEX}" --rpc-url $RPC)

    CHECKPOINT_HASH="0x$(echo $RESULT | cut -c67-130)"
    CHECKPOINT_STATE="0x$(echo $RESULT | cut -c131-194)"

    echo ""
    echo "Checkpoint details:"
    echo "  Block Number: $BLOCK_NUMBER"
    echo "  Block Hash:   $CHECKPOINT_HASH"
    echo "  State Root:   $CHECKPOINT_STATE"
    exit 0
fi

print_info "Checkpoint not found. Waiting..."
echo ""

# If L1→L2, also search for nearby checkpointed blocks
if [ "$DIRECTION" = "l1-to-l2" ]; then
    echo "Searching for nearby checkpointed blocks..."
    NEARBY=$(find_checkpointed_block "$SIGNAL_SERVICE" "$RPC" "$BLOCK_NUMBER" 20) && {
        print_success "Found checkpoint at block $NEARBY (>= $BLOCK_NUMBER)"
        echo ""
        echo "You can generate your proof at block $NEARBY instead."
        echo ""
        read -p "Continue waiting for exact block $BLOCK_NUMBER? [y/N] " CONTINUE
        if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
            exit 0
        fi
    }
fi

# Wait for checkpoint
print_step "Polling for checkpoint (max 10 minutes)..."
echo ""

if wait_for_checkpoint "$SIGNAL_SERVICE" "$RPC" "$BLOCK_NUMBER" 120; then
    echo ""
    print_success "Checkpoint found for block $BLOCK_NUMBER!"

    # Get checkpoint details
    SELECTOR="0xd8646ff5"
    BLOCK_HEX=$(printf "%064x" $BLOCK_NUMBER)
    RESULT=$(cast call $SIGNAL_SERVICE "${SELECTOR}${BLOCK_HEX}" --rpc-url $RPC)

    CHECKPOINT_HASH="0x$(echo $RESULT | cut -c67-130)"
    CHECKPOINT_STATE="0x$(echo $RESULT | cut -c131-194)"

    echo ""
    echo "Checkpoint details:"
    echo "  Block Number: $BLOCK_NUMBER"
    echo "  Block Hash:   $CHECKPOINT_HASH"
    echo "  State Root:   $CHECKPOINT_STATE"
else
    echo ""
    print_error "Timeout: Checkpoint not found after 10 minutes"
    echo ""
    echo "Possible reasons:"
    if [ "$DIRECTION" = "l2-to-l1" ]; then
        echo "  - L2 proposals not finalized yet"
        echo "  - Rate limiting (minCheckpointDelay)"
    else
        echo "  - No anchor transaction yet"
        echo "  - L1 block not included in any anchor"
    fi
    exit 1
fi
