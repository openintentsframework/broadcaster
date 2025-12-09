#!/usr/bin/env bash
set -e

echo "=== WORKFLOW: Verify L1 message from L2 ==="
echo ""
echo "Step 1: Broadcast message on L1"
./scripts/taiko/broadcast.sh l1 | tee /tmp/broadcast_l1.log

TX_HASH=$(grep "transactionHash" /tmp/broadcast_l1.log | grep -o "0x[a-fA-F0-9]\{64\}" | head -1)

if [ -z "$TX_HASH" ]; then
    echo ""
    echo "Could not find tx hash in output"
    echo "Please run manually: ./scripts/taiko/broadcast.sh l1"
    echo "Then get the tx hash and continue with:"
    echo "./scripts/taiko/generate-proof-l1.sh"
    exit 1
fi

echo ""
echo "Step 2: Extract message and generate proof"
echo "TX Hash: $TX_HASH"

source .env
source scripts/taiko/addresses.sh

RPC="https://l1rpc.internal.taiko.xyz"
BROADCASTER=$L1_BROADCASTER

RECEIPT=$(curl -s -X POST $RPC -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getTransactionReceipt\",\"params\":[\"$TX_HASH\"],\"id\":1}" | jq '.result')

BLOCK_HEX=$(echo "$RECEIPT" | jq -r '.blockNumber')
BLOCK=$((BLOCK_HEX))

EVENT_SIG="0x688e36054d0a5be251e818ab668c80af8b698aaa86d47f4422ef0f58333b22b2"

MESSAGE=$(echo "$RECEIPT" | jq -r ".logs[] | select(.topics[0] == \"$EVENT_SIG\") | .topics[1]")
PUBLISHER_RAW=$(echo "$RECEIPT" | jq -r ".logs[] | select(.topics[0] == \"$EVENT_SIG\") | .topics[2]")
PUBLISHER="0x${PUBLISHER_RAW:26}"

echo "Message:   $MESSAGE"
echo "Publisher: $PUBLISHER"
echo "Block:     $BLOCK"

ENCODED=$(cast abi-encode 'f(bytes32,address)' "$MESSAGE" "$PUBLISHER")
SLOT=$(cast keccak "$ENCODED")

echo "Slot:      $SLOT"
echo ""

echo "Step 3: Generate storage proof"
cd scripts/storage-proof-generator
node dist/index.cjs --rpc $RPC --account $BROADCASTER --slot $SLOT --block $BLOCK --output ../../test/payloads/taiko/taikoProofL1.json
cd ../..

echo ""
echo "=== Proof generated: test/payloads/taiko/taikoProofL1.json ==="
echo ""
echo "Step 4: Update test with message and publisher"
echo "Edit test/Receiver.Taiko.t.sol line ~208-209:"
echo "bytes32 message = $MESSAGE;"
echo "address publisher = $PUBLISHER;"
echo ""
echo "Step 5: Run test"
echo "forge test --mt test_verifyBroadcastMessage_from_Ethereum -vv"




