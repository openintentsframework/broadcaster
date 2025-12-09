# Taiko E2E Scripts

Complete end-to-end testing scripts for cross-chain message verification on Taiko.

## Quick Start

```bash
# Run FULL E2E test with on-chain verification (L1 → L2)
./scripts/taiko/e2e/run.sh l1-to-l2

# Run FULL E2E test with on-chain verification (L2 → L1)
./scripts/taiko/e2e/run.sh l2-to-l1

# Run partial E2E test with mocked forge tests
./scripts/taiko/e2e/run-partial.sh l1-to-l2
```

## Scripts

| Script | Description |
|--------|-------------|
| `run.sh` | **Full E2E script** - Broadcasts, waits for checkpoint, generates proof, calls **actual Receiver contract** on-chain |
| `run-partial.sh` | **Partial E2E script** - Same flow but uses **mocked forge tests** instead of on-chain contracts |
| `generate-proof.sh` | Generate proof for an existing transaction |
| `wait-for-checkpoint.sh` | Wait for a specific block to be checkpointed |
| `common.sh` | Shared functions and variables |

## What `run.sh` Does (Full E2E)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  ./scripts/taiko/e2e/run.sh l1-to-l2                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Step 1: BROADCAST                                                          │
│  ─────────────────                                                          │
│  → Runs forge script to broadcast message on L1                             │
│  → Extracts TX hash, block number, message, slot                            │
│                                                                             │
│  Step 2: WAIT FOR CHECKPOINT                                                │
│  ───────────────────────────                                                │
│  → Checks if broadcast block is checkpointed on L2                          │
│  → If not, searches for nearest checkpointed block                          │
│  → If none found, waits for checkpoint (polls every 10s)                    │
│                                                                             │
│  Step 3: GENERATE PROOF                                                     │
│  ──────────────────────                                                     │
│  → Generates storage proof at the CHECKPOINTED block                        │
│  → Saves proof.json and info.json                                           │
│                                                                             │
│  Step 4: VERIFY ON-CHAIN                                                    │
│  ───────────────────────                                                    │
│  → Calls the ACTUAL deployed Receiver contract on destination chain         │
│  → Uses verify-on-chain.s.sol forge script                                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## What `run-partial.sh` Does (Partial E2E with Mocks)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  ./scripts/taiko/e2e/run-partial.sh l1-to-l2                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Steps 1-3: Same as run.sh (Broadcast, Wait, Generate Proof)                │
│                                                                             │
│  Step 4: VERIFY WITH MOCKED TESTS                                           │
│  ────────────────────────────────                                           │
│  → Runs forge unit tests that use vm.store() to mock checkpoints            │
│  → Does NOT call actual on-chain contracts                                  │
│  → Useful for testing proof generation without deployed contracts           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Usage Examples

### Full E2E Test (On-Chain Verification)

```bash
# L1 → L2 (broadcast on L1, verify on L2 Receiver contract)
./scripts/taiko/e2e/run.sh l1-to-l2

# L2 → L1 (broadcast on L2, verify on L1 Receiver contract)
./scripts/taiko/e2e/run.sh l2-to-l1
```

### Partial E2E Test (Mocked Verification)

```bash
# L1 → L2 (broadcast on L1, verify with mocked forge tests)
./scripts/taiko/e2e/run-partial.sh l1-to-l2

# L2 → L1 (broadcast on L2, verify with mocked forge tests)
./scripts/taiko/e2e/run-partial.sh l2-to-l1
```

### Generate Proof for Existing Transaction

```bash
./scripts/taiko/e2e/generate-proof.sh
# Follow the prompts to enter TX hash and direction
```

### Wait for Checkpoint

```bash
# Wait for L1 block 67914 to be checkpointed on L2
./scripts/taiko/e2e/wait-for-checkpoint.sh 67914 l1-to-l2

# Wait for L2 block 10875 to be checkpointed on L1
./scripts/taiko/e2e/wait-for-checkpoint.sh 10875 l2-to-l1
```

## Output Files

| File | Description |
|------|-------------|
| `test/payloads/taiko/taikoProofL1.json` | Storage proof for L1 message |
| `test/payloads/taiko/taikoProofL1-info.json` | L1 message metadata |
| `test/payloads/taiko/taikoProofL2.json` | Storage proof for L2 message |
| `test/payloads/taiko/taikoProofL2-info.json` | L2 message metadata |

## Key Insight: Checkpointed Block vs Broadcast Block

For **L1 → L2**, the broadcast block may not be checkpointed immediately. The script automatically finds the nearest checkpointed block >= broadcast block and generates the proof at that block.

```
L1 Blocks:    100      101      102      103      104      105
               │                                            │
               ▼                                            ▼
          BROADCAST                                    CHECKPOINT
          (your message)                               (on L2)
               │                                            │
               └────────── Message exists at both ──────────┘
                                    │
                                    ▼
                         Proof generated at 105
```

## Prerequisites

- `.env` file with `TAIKO_USER_PK` set
- Broadcasters deployed (see `scripts/taiko/deploy.sh`)
- `scripts/storage-proof-generator` built (`npm run build`)
