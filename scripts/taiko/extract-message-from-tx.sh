#!/usr/bin/env bash
set -e

if [ -z "$1" ]; then
    echo "Usage: ./scripts/taiko/extract-message-from-tx.sh <tx_hash> [l1|l2]"
    exit 1
fi

TX_HASH=$1
CHAIN=${2:-l2}

if [ "$CHAIN" = "l1" ]; then
    RPC="https://l1rpc.internal.taiko.xyz"
else
    RPC="https://rpc.internal.taiko.xyz"
fi

echo "Extracting message and publisher from tx: $TX_HASH"
echo ""

RECEIPT=$(cast receipt $TX_HASH --rpc-url $RPC --json)
EVENT_SIG=$(cast keccak 'MessageBroadcast(bytes32,address)')

LOG=$(echo "$RECEIPT" | jq --arg sig "$EVENT_SIG" '.logs[] | select(.topics[0] == $sig)')

if [ -z "$LOG" ]; then
    echo "Error: MessageBroadcast event not found"
    exit 1
fi

MESSAGE=$(echo "$LOG" | jq -r '.topics[1]')
PUBLISHER_RAW=$(echo "$LOG" | jq -r '.topics[2]')
PUBLISHER="0x${PUBLISHER_RAW:26}"

echo "Message:   $MESSAGE"
echo "Publisher: $PUBLISHER"
echo ""
echo "For test, use:"
echo "bytes32 message = $MESSAGE;"
echo "address publisher = $PUBLISHER;"




