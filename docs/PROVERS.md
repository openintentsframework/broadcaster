# StateProvers Reference

This document details the chain-specific `StateProver` implementations available in this repository. Each prover handles the unique way its rollup commits state to parent chains.

## Overview

Each rollup requires **two provers** for bidirectional communication:

| Prover Type | Direction | Home Chain | Target Chain |
|-------------|-----------|------------|--------------|
| **ChildToParentProver** | L2 → L1 | Child (L2) | Parent (L1) |
| **ParentToChildProver** | L1 → L2 | Parent (L1) | Child (L2) |

---

## Arbitrum

### ChildToParentProver

**Location:** `src/contracts/provers/arbitrum/ChildToParentProver.sol`

Proves Ethereum (L1) block hashes from Arbitrum (L2).

**Mechanism:**
- Uses the `ArbSys` precompile at `0x0000000000000000000000000000000000000064`
- Accesses the `l2ToL1Block()` function which returns L1 block numbers
- Uses a `Buffer` contract that stores historical L1 block hashes

**Key addresses:**
- `ArbSys`: `0x0000000000000000000000000000000000000064`
- `Buffer`: `0x0000000048C4Ed10cF14A02B9E0AbDDA5227b071`

**Input format for `getTargetStateCommitment`:**
```solidity
abi.encode(uint256 targetBlockNumber)
```

**Input format for `verifyTargetStateCommitment`:**
```solidity
abi.encode(
    bytes rlpBlockHeader,
    uint256 targetBlockNumber,
    bytes accountProof,
    bytes storageProof
)
```

### ParentToChildProver

**Location:** `src/contracts/provers/arbitrum/ParentToChildProver.sol`

Proves Arbitrum (L2) block hashes from Ethereum (L1).

**Mechanism:**
- Uses the `Outbox` contract on L1 which stores Arbitrum's `sendRoot`
- The `sendRoot` maps to confirmed L2 block hashes via `SendRootUpdated` events
- Proves storage in the Outbox's `roots` mapping

**Key components:**
- `outbox`: Arbitrum's Outbox contract address (chain-specific)
- `rootsSlot`: Storage slot for the roots mapping

**Input format for `getTargetStateCommitment`:**
```solidity
abi.encode(bytes32 sendRoot)
```

**Input format for `verifyTargetStateCommitment`:**
```solidity
abi.encode(
    bytes rlpBlockHeader,
    bytes32 sendRoot,
    bytes accountProof,
    bytes storageProof
)
```

---

## Optimism

### ChildToParentProver

**Location:** `src/contracts/provers/optimism/ChildToParentProver.sol`

Proves Ethereum (L1) block hashes from OP Stack chains.

**Mechanism:**
- Uses the `L1Block` predeploy at `0x4200000000000000000000000000000000000015`
- The predeploy stores the **latest** L1 block hash only (not historical)
- Proofs must be generated just-in-time as they become stale when L1Block updates (~5 minutes)

**Key addresses:**
- `L1Block`: `0x4200000000000000000000000000000000000015`
- `l1BlockHashSlot`: `2`

**Important operational note:**
Pre-generated proofs become stale when L1Block updates. Failed calls may need to be retried with fresh proofs.

**Input format for `getTargetStateCommitment`:**
```solidity
// bytes argument is ignored - returns latest L1 block hash
```

**Input format for `verifyTargetStateCommitment`:**
```solidity
abi.encode(
    bytes rlpBlockHeader,
    bytes accountProof,
    bytes storageProof
)
```

### ParentToChildProver

**Location:** `src/contracts/provers/optimism/ParentToChildProver.sol`

Proves OP Stack (L2) block hashes from Ethereum (L1).

**Mechanism:**
- Uses the `L2OutputOracle` on L1 which stores L2 output proposals
- Output proposals contain state roots that commit to L2 state
- Requires finding the latest finalized output proposal

---

## Linea

### ChildToParentProver

**Location:** `src/contracts/provers/linea/ChildToParentProver.sol`

Proves Ethereum (L1) block hashes from Linea (L2).

**Mechanism:**
- Uses Linea's `L1MessageService` which stores L1 block hashes
- Linea uses a sparse Merkle tree (different from standard MPT)

**Libraries used:**
- `SparseMerkleProof.sol`: Linea's sparse Merkle proof verification
- `Mimc.sol`: MiMC hash function used in Linea's state tree

### ParentToChildProver

**Location:** `src/contracts/provers/linea/ParentToChildProver.sol`

Proves Linea (L2) block hashes from Ethereum (L1).

**Mechanism:**
- Uses the `LineaRollup` contract on L1
- Proves state roots from finalized Linea batches

---

## Scroll

### ChildToParentProver

**Location:** `src/contracts/provers/scroll/ChildToParentProver.sol`

Proves Ethereum (L1) block hashes from Scroll (L2).

**Mechanism:**
- Uses a `Buffer` contract that stores historical L1 block hashes
- Similar architecture to Arbitrum's ChildToParentProver

**Key addresses:**
- `Buffer`: Chain-specific buffer address

### ParentToChildProver

**Location:** `src/contracts/provers/scroll/ParentToChildProver.sol`

Proves Scroll (L2) block hashes from Ethereum (L1).

**Mechanism:**
- Uses the `ScrollChain` contract on L1
- Proves finalized batch state roots

---

## zkSync

### ChildToParentProver

**Location:** `src/contracts/provers/zksync/ChildToParentProver.sol`

Proves Ethereum (L1) block hashes from zkSync Era (L2).

**Mechanism:**
- Uses zkSync's system contracts for L1 block hash access
- Different storage/proof structure than EVM-equivalent chains

**Libraries used:**
- `Merkle.sol`: zkSync's Merkle proof verification
- `MessageHashing.sol`: zkSync-specific message hashing

### ParentToChildProver

**Location:** `src/contracts/provers/zksync/ParentToChildProver.sol`

Proves zkSync Era (L2) block hashes from Ethereum (L1).

**Mechanism:**
- Uses the zkSync Diamond Proxy on L1
- Proves state roots from finalized batches

---

## Taiko

### ChildToParentProver

**Location:** `src/contracts/provers/taiko/ChildToParentProver.sol`

Proves Ethereum (L1) block hashes from Taiko (L2).

### ParentToChildProver

**Location:** `src/contracts/provers/taiko/ParentToChildProver.sol`

Proves Taiko (L2) block hashes from Ethereum (L1).

---

## Common Storage Proof Input

All provers use a common format for `verifyStorageSlot`:

```solidity
abi.encode(
    bytes rlpBlockHeader,    // RLP-encoded block header
    address account,         // Target account address
    uint256 slot,            // Storage slot to prove
    bytes accountProof,      // Merkle proof for the account
    bytes storageProof       // Merkle proof for the storage slot
)
```

**Output:**
```solidity
returns (
    address account,   // The proven account address
    uint256 slot,      // The proven storage slot
    bytes32 value      // The value at the storage slot
)
```

---

## Implementing a New Prover

To add support for a new rollup:

1. **Create the directory structure:**
   ```
   src/contracts/provers/{chain-name}/
   ├── ChildToParentProver.sol
   └── ParentToChildProver.sol
   ```

2. **Implement `IStateProver` interface** for both directions

3. **Identify the state commitment source:**
   - For ChildToParentProver: Where does the L2 store L1 block hashes?
   - For ParentToChildProver: Where does L1 store finalized L2 state roots?

4. **Implement the three core functions:**
   - `getTargetStateCommitment()`: Direct state access on home chain
   - `verifyTargetStateCommitment()`: Proof verification on remote chain
   - `verifyStorageSlot()`: Standard MPT proof verification (usually reusable)

5. **Ensure code hash consistency:**
   - Use immutable values or compile-time constants
   - Avoid chain-specific storage reads in verification functions

6. **Add TypeScript helpers** in `src/ts/` for proof generation

---

## ProverUtils Library

**Location:** `src/contracts/libraries/ProverUtils.sol`

Shared utilities for all provers:

```solidity
library ProverUtils {
    /// @notice Verify block header hash and extract state root
    function getStateRoot(bytes32 blockHash, bytes memory rlpBlockHeader)
        internal pure returns (bytes32 stateRoot);

    /// @notice Verify account proof and get account data
    function getAccountData(
        bytes32 stateRoot,
        address account,
        bytes memory accountProof
    ) internal pure returns (bytes32 storageRoot, ...);

    /// @notice Verify storage proof and get slot value
    function getStorageValue(
        bytes32 storageRoot,
        uint256 slot,
        bytes memory storageProof
    ) internal pure returns (bytes32 value);

    /// @notice Combined helper: block hash → storage value
    function getSlotFromBlockHeader(
        bytes32 blockHash,
        bytes memory rlpBlockHeader,
        address account,
        uint256 slot,
        bytes memory accountProof,
        bytes memory storageProof
    ) internal pure returns (bytes32 value);
}
```

---

## Testing Provers

Each prover has corresponding tests in `test/provers/{chain-name}/`:

```bash
# Run all prover tests
forge test --match-path "test/provers/**"

# Run specific chain tests
forge test --match-path "test/provers/arbitrum/**"

# Run with fork testing (requires RPC URLs)
forge test --match-path "test/provers/**" --fork-url $ETHEREUM_RPC_URL
```

Test payloads are stored in `test/payloads/{chain-name}/` as JSON files containing pre-generated proofs for reproducible testing.
