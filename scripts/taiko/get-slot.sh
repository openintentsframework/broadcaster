#!/usr/bin/env bash
set -e

if [ -z "$1" ]; then
    echo "Usage: ./scripts/taiko/get-slot.sh <tx_hash> [l1|l2]"
    exit 1
fi

TX_HASH=$1
CHAIN=${2:-l2}
DEBUG=${3:-false}

if [ "$CHAIN" = "l1" ]; then
    RPC="https://l1rpc.internal.taiko.xyz"
    source .env
    source scripts/taiko/addresses.sh
    BROADCASTER=$L1_BROADCASTER
else
    RPC="https://rpc.internal.taiko.xyz"
    source .env
    source scripts/taiko/addresses.sh
    BROADCASTER=$L2_BROADCASTER
fi

echo "Fetching tx: $TX_HASH"
echo ""

RECEIPT=$(cast receipt $TX_HASH --rpc-url $RPC --json)

if [ "$DEBUG" = "debug" ]; then
    echo "=== DEBUG: Full Receipt ==="
    echo "$RECEIPT" | jq '.'
    echo ""
fi

BLOCK_HEX=$(echo "$RECEIPT" | jq -r '.blockNumber')
BLOCK=$((BLOCK_HEX))

EVENT_SIG=$(cast keccak 'MessageBroadcast(bytes32,address)')

if [ "$DEBUG" = "debug" ]; then
    echo "=== DEBUG: Event Signature ==="
    echo "Expected: $EVENT_SIG"
    echo ""
    echo "=== DEBUG: Log Topics ==="
    echo "$RECEIPT" | jq -r '.logs[].topics[0]'
    echo ""
fi

LOG=$(echo "$RECEIPT" | jq --arg sig "$EVENT_SIG" '.logs[] | select(.topics[0] == $sig)')

if [ -z "$LOG" ]; then
    echo "Error: MessageBroadcast event not found"
    echo ""
    echo "Expected event signature: $EVENT_SIG"
    echo "Found logs with topics:"
    echo "$RECEIPT" | jq -r '.logs[] | .topics[0]' | sort -u
    echo ""
    echo "Re-run with 'debug' as 3rd argument to see full receipt:"
    echo "./scripts/taiko/get-slot.sh $TX_HASH $CHAIN debug"
    exit 1
fi

MESSAGE=$(echo "$LOG" | jq -r '.topics[1]')
PUBLISHER_RAW=$(echo "$LOG" | jq -r '.topics[2]')
PUBLISHER="0x${PUBLISHER_RAW:26}"

if [ "$DEBUG" = "debug" ]; then
    echo "=== DEBUG: Extracted Values ==="
    echo "MESSAGE RAW: $MESSAGE"
    echo "PUBLISHER RAW: $PUBLISHER_RAW"
    echo "PUBLISHER: $PUBLISHER"
    echo ""
fi

echo "Broadcaster:  $BROADCASTER"
echo "Message:      $MESSAGE"
echo "Publisher:    $PUBLISHER"
echo "Block:        $BLOCK"
echo ""

ENCODED=$(cast abi-encode 'f(bytes32,address)' "$MESSAGE" "$PUBLISHER")
SLOT=$(cast keccak "$ENCODED")

echo "Storage Slot: $SLOT"
echo ""
echo "Command:"
echo "node dist/index.cjs --rpc $RPC --account $BROADCASTER --slot $SLOT --block $BLOCK --output proof.json"

