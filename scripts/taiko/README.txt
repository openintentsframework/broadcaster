========================================
TAIKO BROADCASTER E2E GUIDE
========================================

Complete guide for deploying, broadcasting, and verifying messages
across Taiko L1 (Ethereum) and L2 (Taiko Child Chain).

========================================
QUICK START
========================================

1. Setup environment:
   cp .env.taiko.example .env
   # Edit .env with your keys

2. Deploy all contracts:
   ./scripts/taiko/deploy.sh

3. Broadcast and generate proof (ONE COMMAND):
   ./scripts/taiko/broadcast-and-prove.sh l2

4. Run test to verify:
   forge test --mt test_verifyBroadcastMessage_from_TaikoL2 -vv

========================================
SETUP
========================================

Required environment variables in .env:

# Deployer credentials (for contract deployment)
TAIKO_DEPLOYER_PK=0x...
TAIKO_DEPLOYER_ADDRESS=0x...

# User credentials (for broadcasting messages)
TAIKO_USER_PK=0x...

# RPC endpoints
TAIKO_PARENT_RPC_URL=https://l1rpc.internal.taiko.xyz
TAIKO_CHILD_RPC_URL=https://rpc.internal.taiko.xyz

# For tests
ETHEREUM_RPC_URL=https://l1rpc.internal.taiko.xyz
ARBITRUM_RPC_URL=https://arb1.arbitrum.io/rpc
OPTIMISM_RPC_URL=https://mainnet.optimism.io

After deployment, contract addresses are auto-saved to:
scripts/taiko/addresses.sh

========================================
DEPLOYMENT
========================================

./scripts/taiko/deploy.sh          # Deploy only if not already deployed
./scripts/taiko/deploy.sh --force  # Force re-deployment

Deploys and verifies all contracts on L1 and L2:
- Broadcaster, Receiver, BlockHashProverPointer
- ParentToChildProver (L1) - reads L2 state from L1
- ChildToParentProver (L2) - reads L1 state from L2

Smart deployment features:
1. Checks if contracts already deployed at saved addresses
2. Verifies contracts have code using cast code
3. Skips deployment if already exists
4. Use --force to redeploy everything

Addresses saved to: scripts/taiko/addresses.sh

========================================
BROADCASTING MESSAGES
========================================

./scripts/taiko/broadcast.sh [l1|l2|both]

Examples:
  ./scripts/taiko/broadcast.sh l1    # Broadcast on L1 only
  ./scripts/taiko/broadcast.sh l2    # Broadcast on L2 only
  ./scripts/taiko/broadcast.sh       # Broadcast on both chains

Messages are auto-generated as:
  keccak256(abi.encodePacked("Message", block.timestamp, msg.sender))

This ensures each broadcast creates a unique message.

========================================
E2E FLOW 1: L2 → L1
========================================
Verify a Taiko L2 message from Ethereum L1

Concept: Broadcast message on L2, verify it from L1 using ParentToChildProver

EASY WAY (recommended):
  ./scripts/taiko/broadcast-and-prove.sh l2
  forge test --mt test_verifyBroadcastMessage_from_TaikoL2 -vv

MANUAL Steps:

1. Broadcast on L2:
   ./scripts/taiko/broadcast.sh l2
   # Note the tx hash from output

2. Get storage slot:
   ./scripts/taiko/get-slot.sh <tx_hash> l2
   # This outputs the command to generate proof

3. Generate proof (copy command from step 2):
   cd scripts/storage-proof-generator
   node dist/index.cjs --rpc https://rpc.internal.taiko.xyz \
     --account $L2_BROADCASTER --slot <SLOT> --block <BLOCK> \
     --output ../../test/payloads/taiko/taikoProofL2.json
   cd ../..

4. Run test:
   forge test --mt test_verifyBroadcastMessage_from_TaikoL2 -vv

Expected result: Test passes, message verified from L1

========================================
E2E FLOW 2: L1 → L2
========================================
Verify an Ethereum L1 message from Taiko L2

Concept: Broadcast message on L1, verify it from L2 using ChildToParentProver

EASY WAY (recommended):
  ./scripts/taiko/broadcast-and-prove.sh l1
  forge test --mt test_verifyBroadcastMessage_from_Ethereum -vv

MANUAL Steps:

1. Broadcast on L1:
   ./scripts/taiko/broadcast.sh l1
   # Note the tx hash from output

2. Get storage slot:
   ./scripts/taiko/get-slot.sh <tx_hash> l1
   # This outputs the command to generate proof

3. Generate proof (copy command from step 2):
   cd scripts/storage-proof-generator
   node dist/index.cjs --rpc https://l1rpc.internal.taiko.xyz \
     --account $L1_BROADCASTER --slot <SLOT> --block <BLOCK> \
     --output ../../test/payloads/taiko/taikoProofL1.json
   cd ../..

4. Extract message and publisher:
   ./scripts/taiko/extract-message-from-tx.sh <tx_hash> l1
   # Copy the message and publisher values

5. Update test:
   Edit test/Receiver.Taiko.t.sol line ~208-209
   Replace with values from step 4

6. Run test:
   forge test --mt test_verifyBroadcastMessage_from_Ethereum -vv

Expected result: Test passes, message verified from L2

========================================
AUTOMATED WORKFLOWS
========================================

./scripts/taiko/broadcast-and-prove.sh [l1|l2|both]
  ⭐ RECOMMENDED: One-command workflow for broadcast + proof generation

  Automatically:
  1. Broadcasts message on specified chain(s)
  2. Extracts TX hash from forge output
  3. Gets storage slot, message, publisher, block number
  4. Generates storage proof
  5. Saves proof to test/payloads/taiko/

  Examples:
    ./scripts/taiko/broadcast-and-prove.sh l2    # L2 only
    ./scripts/taiko/broadcast-and-prove.sh l1    # L1 only
    ./scripts/taiko/broadcast-and-prove.sh both  # Both chains
    ./scripts/taiko/broadcast-and-prove.sh       # Same as 'both'

  Output files:
    - L1: test/payloads/taiko/taikoProofL1.json
    - L2: test/payloads/taiko/taikoProofL2.json

./scripts/taiko/workflow-l1-to-l2.sh
  Automated L1 proof generation workflow
  Interactive prompts guide you through the process

./scripts/taiko/e2e-test.sh
  Full E2E test with interactive prompts
  Tests both L2→L1 and L1→L2 flows

========================================
VERIFY REAL MESSAGE (NO MOCKS)
========================================

./scripts/taiko/verify-message.sh

Verifies message on real L1 chain using deployed contracts.
Uses actual SignalService (no mocks).

Requirements:
- Contracts must be deployed
- SignalService must have the L2 checkpoint
- Proof must be generated

Note: Will fail if SignalService doesn't have the checkpoint yet.
In tests we mock this with vm.store().

========================================
HELPER SCRIPTS
========================================

./scripts/taiko/broadcast-and-prove.sh [l1|l2|both]
  One-command broadcast + proof generation (see AUTOMATED WORKFLOWS)

./scripts/taiko/get-slot.sh <tx_hash> [l1|l2] [debug]
  Get storage slot and proof generation command from broadcast tx
  
  Examples:
    ./scripts/taiko/get-slot.sh 0x123... l2
    ./scripts/taiko/get-slot.sh 0x123... l1 debug

  Output: Shows message, publisher, block, slot, and ready-to-run
          node command for proof generation

./scripts/taiko/extract-message-from-tx.sh <tx_hash> [l1|l2]
  Extract message and publisher from broadcast tx
  Use this to update test files with correct values

  Example:
    ./scripts/taiko/extract-message-from-tx.sh 0x123... l2

./scripts/taiko/generate-proof-l1.sh
  Interactive script to generate L1 proof
  Prompts for tx hash and generates proof automatically

========================================
TESTING
========================================

Run all Taiko tests:
  forge test --match-contract ReceiverTaikoTest -vv

Run specific tests:
  forge test --mt test_verifyBroadcastMessage_from_TaikoL2 -vv
  forge test --mt test_verifyBroadcastMessage_from_Ethereum -vv

Tests are located in: test/Receiver.Taiko.t.sol

Test payloads:
- test/payloads/taiko/taikoProofL2.json (L2 proof)
- test/payloads/taiko/taikoProofL1.json (L1 proof)

========================================
ARCHITECTURE
========================================

L1 (Ethereum/Taiko Parent - Chain ID: 32382)
├── Broadcaster (stores messages)
├── Receiver (verifies remote messages)
├── BlockHashProverPointer
├── ParentToChildProver (reads L2 blocks via SignalService)
└── SignalService (0x53789e39E3310737E8C8cED483032AAc25B39ded)
    └── Stores L2 block checkpoints

L2 (Taiko Child Chain - Chain ID: 167001)
├── Broadcaster (stores messages)
├── Receiver (verifies remote messages)
├── BlockHashProverPointer
├── ChildToParentProver (reads L1 blocks via SignalService)
└── SignalService (0x1670010000000000000000000000000000000005)
    └── Stores L1 block checkpoints

========================================
HOW IT WORKS
========================================

Message Verification Flow (L2 → L1):
1. Message broadcast on L2 → stored in Broadcaster storage
2. L2 block gets checkpointed in L1 SignalService
3. Generate storage proof of message in L2
4. L1 Receiver calls ParentToChildProver
5. ParentToChildProver reads L2 block hash from L1 SignalService
6. Verifies storage proof against L2 block hash
7. Message verified! ✅

Message Verification Flow (L1 → L2):
1. Message broadcast on L1 → stored in Broadcaster storage
2. L1 block gets checkpointed in L2 SignalService
3. Generate storage proof of message in L1
4. L2 Receiver calls ChildToParentProver
5. ChildToParentProver reads L1 block hash from L2 SignalService
6. Verifies storage proof against L1 block hash
7. Message verified! ✅

Storage Slot Calculation:
  slot = keccak256(abi.encode(message, publisher))

Message Generation:
  message = keccak256(abi.encodePacked("Message", timestamp, sender))

========================================
DEPLOYED CONTRACTS
========================================

L1 (Taiko Parent Chain - 32382):
- Broadcaster: $L1_BROADCASTER
- Receiver: $L1_RECEIVER
- BlockHashProverPointer: $L1_POINTER
- ParentToChildProver: $L1_PARENT_TO_CHILD_PROVER
- ProverPointer: $L1_PROVER_POINTER

L2 (Taiko Child Chain - 167001):
- Broadcaster: $L2_BROADCASTER
- Receiver: $L2_RECEIVER
- BlockHashProverPointer: $L2_POINTER
- ChildToParentProver: $L2_CHILD_TO_PARENT_PROVER
- ProverPointer: $L2_PROVER_POINTER

(Addresses populated in scripts/taiko/addresses.sh after deployment)

========================================
TROUBLESHOOTING
========================================

Block hash mismatch in proof generation:
- Fixed by using debug_getRawHeader RPC method
- storage-proof-generator automatically uses it for Taiko
- Taiko has additional EIP-7685 fields

Cast commands crash:
- Known Foundry issue on Taiko RPC
- Use curl-based alternatives provided in scripts
- Scripts use curl when cast fails

SignalService checkpoint not found:
- In tests: Mocked with vm.store()
- In real verification: Requires actual checkpoint
- Wait for Taiko to checkpoint the block

Message verification fails:
- Ensure message and publisher match broadcast tx
- Use extract-message-from-tx.sh to get exact values
- Verify storage slot calculation

Contracts already deployed:
- Script auto-detects and skips
- Use --force to redeploy
- Check scripts/taiko/addresses.sh for current addresses

========================================
IMPORTANT NOTES
========================================

- Each broadcast generates unique message using timestamp + sender
- Storage slot = keccak256(abi.encode(message, publisher))
- Tests mock SignalService checkpoints (not available on testnet)
- Real verification requires SignalService to have checkpoint
- storage-proof-generator uses debug_getRawHeader for Taiko
- ParentToChildProver deployed on L1, reads L2
- ChildToParentProver deployed on L2, reads L1
- Both use getTargetBlockHash in tests (direct SignalService read)
- Production would use verifyTargetBlockHash (with proofs)

