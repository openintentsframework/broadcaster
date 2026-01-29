# StateProvers, Pointers, and Copies

This document explains the architecture of StateProvers, how they work with StateProverPointers for upgradeability, and the mechanism of StateProverCopies for cross-chain verification.

## Overview

The verification system consists of three components:

| Component | Role | Location |
|-----------|------|----------|
| **StateProver** | Contains chain-specific verification logic | Deployed on home chain |
| **StateProverPointer** | Upgradeable reference to a StateProver | Deployed on home chain |
| **StateProverCopy** | Exact bytecode copy of a StateProver | Deployed on any chain |

## StateProver

A StateProver implements chain-specific logic to:
1. Retrieve or verify state commitments between two chains
2. Verify storage proofs against those state commitments

Each prover is **unidirectional**, fixed to a specific `(home chain, target chain)` pair.

### Interface

```solidity
interface IStateProver {
    /// @notice Get state commitment when called on the home chain.
    /// @dev MUST revert if not on home chain.
    function getTargetStateCommitment(bytes calldata input)
        external view returns (bytes32 targetStateCommitment);

    /// @notice Verify state commitment from a remote chain.
    /// @dev MUST revert if called on home chain.
    function verifyTargetStateCommitment(bytes32 homeStateCommitment, bytes calldata input)
        external view returns (bytes32 targetStateCommitment);

    /// @notice Verify a storage slot given a target state commitment.
    function verifyStorageSlot(bytes32 targetStateCommitment, bytes calldata input)
        external view returns (address account, uint256 slot, bytes32 value);

    /// @notice Version number for upgrade ordering.
    function version() external pure returns (uint256);
}
```

### Operating Modes

StateProvers have two operating modes based on the calling chain:

| Mode | Function | Behavior |
|------|----------|----------|
| **Home chain** | `getTargetStateCommitment()` | Directly reads target chain's state commitment from local storage |
| **Remote chain** | `verifyTargetStateCommitment()` | Verifies a proof to derive target chain's state commitment |

```solidity
// Home chain check pattern used in all provers
function getTargetStateCommitment(bytes calldata input) external view returns (bytes32) {
    if (block.chainid != homeChainId) {
        revert CallNotOnHomeChain();
    }
    // Direct storage read...
}

function verifyTargetStateCommitment(bytes32 homeStateCommitment, bytes calldata input)
    external view returns (bytes32)
{
    if (block.chainid == homeChainId) {
        revert CallOnHomeChain();
    }
    // Proof verification...
}
```

### Prover Types

Each chain needs two provers:

1. **ChildToParentProver**: Proves parent chain state from child chain
   - Home: Child chain (L2)
   - Target: Parent chain (L1)
   
2. **ParentToChildProver**: Proves child chain state from parent chain
   - Home: Parent chain (L1)
   - Target: Child chain (L2)

### Purity Requirements

To ensure consistent behavior across chains, provers must be **pure** (with one exception):

- `verifyTargetStateCommitment()`, `verifyStorageSlot()`, and `version()` MUST NOT access storage
- Exception: MAY read `address(this).code` (for bytecode introspection)
- `getTargetStateCommitment()` may make external calls (only runs on home chain)

## StateProverPointer

Rollup storage layouts may change over time, requiring prover updates. StateProverPointers provide **upgradeable indirection**:

```
Route Address → StateProverPointer → StateProver
   (fixed)          (fixed)         (upgradeable)
```

### Interface

```solidity
interface IStateProverPointer {
    /// @notice Returns the code hash of the current StateProver.
    function implementationCodeHash() external view returns (bytes32);

    /// @notice Returns the address of the current StateProver.
    function implementationAddress() external view returns (address);
}
```

### Storage Slot

The pointer stores the implementation's code hash in a well-known slot:

```solidity
bytes32 constant STATE_PROVER_POINTER_SLOT = 
    bytes32(uint256(keccak256("eip7888.pointer.slot")) - 1);
```

This deterministic slot enables verification of the pointer's state from remote chains.

### Implementation

```solidity
contract StateProverPointer is IStateProverPointer, Ownable {
    address internal _implementationAddress;

    function setImplementationAddress(address _newImplementation) external onlyOwner {
        // Verify it's a valid StateProver
        uint256 newVersion = IStateProver(_newImplementation).version();
        
        // Ensure version increases
        if (_implementationAddress != address(0)) {
            uint256 oldVersion = IStateProver(_implementationAddress).version();
            if (newVersion <= oldVersion) {
                revert NonIncreasingVersion(newVersion, oldVersion);
            }
        }

        _implementationAddress = _newImplementation;
        
        // Store code hash in the well-known slot
        StorageSlot.getBytes32Slot(STATE_PROVER_POINTER_SLOT).value = 
            _newImplementation.codehash;
    }
}
```

### Upgrade Process

1. Deploy new StateProver with higher `version()` number
2. Owner calls `setImplementationAddress()` on the pointer
3. Pointer stores the new prover's code hash
4. Receivers update their local copies via `updateStateProverCopy()`

### Upgrade Constraints

- New StateProver MUST have same home and target chains
- New StateProver MUST have strictly higher version
- Existing routes continue to work (route addresses don't change)

### Pointer Ownership

The pointer owner has significant power (can DoS or enable message forgery). Recommended ownership:

| Target Chain Type | Recommended Owner |
|-------------------|-------------------|
| Parent chain (L1) | Home chain owner (L2 governance) |
| Child chain (L2) | Target chain owner (L2 governance) |

The general rule: whoever can modify the chain's state commitment storage should own the pointer.

## StateProverCopies

Receivers cannot call contracts on remote chains. To verify proofs, they maintain **local copies** of StateProvers with identical bytecode.

### Why Copies?

```
Chain A (Home)                    Chain B (Local/Receiver)
┌──────────────────┐              ┌──────────────────┐
│                  │              │                  │
│  StateProver     │              │  StateProverCopy │
│  (original)      │   ═══════    │  (same bytecode) │
│                  │              │                  │
│  codehash: 0x123 │              │  codehash: 0x123 │
└──────────────────┘              └──────────────────┘
```

Since the prover's verification functions are pure (deterministic), a copy with identical bytecode will produce identical results.

### Registration Flow

```solidity
function updateStateProverCopy(
    RemoteReadArgs calldata scpPointerReadArgs,
    IStateProver scpCopy
) external returns (bytes32 scpPointerId) {
    // 1. Verify the remote pointer's storage slot
    (scpPointerId, slot, scpCodeHash) = _readRemoteSlot(scpPointerReadArgs);

    // 2. Ensure we're reading the code hash slot
    if (slot != uint256(STATE_PROVER_POINTER_SLOT)) {
        revert WrongStateProverPointerSlot();
    }

    // 3. Verify local copy matches remote pointer's code hash
    if (address(scpCopy).codehash != scpCodeHash) {
        revert DifferentCodeHash();
    }

    // 4. Ensure version is increasing
    IStateProver oldCopy = _stateProverCopies[scpPointerId];
    if (address(oldCopy) != address(0) && oldCopy.version() >= scpCopy.version()) {
        revert NewerProverVersion();
    }

    // 5. Store the copy
    _stateProverCopies[scpPointerId] = scpCopy;
}
```

### Copy ID Calculation

Copies are stored keyed by their **pointer ID**, which is the accumulated hash of the route to the pointer:

```solidity
// Route: [PointerA, PointerB] → scpPointerId = accumulator([0, PointerA, PointerB])
bytes32 scpPointerId = keccak256(abi.encode(
    keccak256(abi.encode(bytes32(0), PointerA)),
    PointerB
));
```

This means the same prover accessed via different routes will have different IDs.

### Deploying Copies

To deploy a StateProverCopy:

1. Get the original prover's bytecode from the home chain
2. Deploy with identical bytecode on the local chain (using `CREATE2` or `vm.etch` in tests)
3. Call `receiver.updateStateProverCopy()` with the appropriate proof

```solidity
// In tests, using Foundry's vm.etch
function _deployProverCopy(address original) internal returns (address copy) {
    bytes memory bytecode = original.code;
    copy = makeAddr("proverCopy");
    vm.etch(copy, bytecode);
    // copy.codehash == original.codehash
}
```

## Verification Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Receiver (Local Chain)                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   route[0]                    route[1]                    route[n]       │
│      │                           │                           │          │
│      ▼                           ▼                           ▼          │
│  ┌────────┐                 ┌────────┐                 ┌────────┐       │
│  │Pointer │                 │ Copy   │                 │ Copy   │       │
│  │(local) │                 │(remote │                 │(remote │       │
│  └───┬────┘                 │pointer)│                 │pointer)│       │
│      │                      └───┬────┘                 └───┬────┘       │
│      │                          │                          │            │
│      ▼                          ▼                          ▼            │
│  ┌────────┐                 ┌────────┐                 ┌────────┐       │
│  │Prover  │ ──stateComm──► │Prover  │ ──stateComm──► │Prover  │       │
│  │(local) │                 │Copy    │                 │Copy    │       │
│  └───┬────┘                 └───┬────┘                 └───┬────┘       │
│      │                          │                          │            │
│      │    getTargetState        │   verifyTargetState      │  verify    │
│      │    Commitment()          │   Commitment()           │  Storage   │
│      │                          │                          │  Slot()    │
│      ▼                          ▼                          ▼            │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                     State Commitment Chain                        │  │
│  │  stateComm[0] → stateComm[1] → ... → stateComm[n] → storage slot │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## ProverUtils Library

The `ProverUtils` library provides common verification utilities:

### Block Header Verification

```solidity
function getSlotFromBlockHeader(
    bytes32 blockHash,
    bytes memory rlpBlockHeader,
    address account,
    uint256 slot,
    bytes memory rlpAccountProof,
    bytes memory rlpStorageProof
) internal pure returns (bytes32 value);
```

1. Verifies `keccak256(rlpBlockHeader) == blockHash`
2. Extracts state root from block header
3. Verifies account proof against state root
4. Verifies storage proof against account's storage root

### State Root Verification

```solidity
function getStorageSlotFromStateRoot(
    bytes32 stateRoot,
    bytes memory rlpAccountProof,
    bytes memory rlpStorageProof,
    address account,
    uint256 slot
) internal pure returns (bytes32 value);
```

For chains that store state roots directly (like Scroll), this skips the block header step.

### RLP Indices

```solidity
uint256 internal constant STATE_ROOT_INDEX = 3;   // In block header
uint256 internal constant CODE_HASH_INDEX = 3;    // In account data
uint256 internal constant STORAGE_ROOT_INDEX = 2; // In account data
```

## Security Considerations

### Code Hash Verification

The code hash matching requirement ensures:
- No malicious prover implementations
- Deterministic verification results
- Trust-minimized cross-chain proofs

### Version Monotonicity

Version numbers must strictly increase to prevent:
- Rollback to vulnerable versions
- Replay attacks with old provers
- Inconsistent state across chains

### Chain-Specific Risks

Different chains have different trust assumptions:

| Chain | State Commitment | Finality | Notes |
|-------|-----------------|----------|-------|
| Ethereum | Block hash | ~15 min | Strong finality |
| Arbitrum | Block hash via Outbox | ~1 week | Challenge period |
| Optimism | Block hash via L1Block | ~7 days | Challenge period (older) / instant with validity proofs |
| Scroll | State root | ~hours | ZK proven |
| ZkSync | L2 logs root | ~hours | ZK proven |
| Linea | SMT state root | ~hours | ZK proven, uses MiMC hashing |
| Taiko | Block hash via SignalService | ~hours | ZK proven |

## Related Documentation

- [RECEIVER.md](./RECEIVER.md) - How the Receiver uses provers
- Chain-specific implementations:
  - [provers/ARBITRUM.md](./provers/ARBITRUM.md)
  - [provers/OPTIMISM.md](./provers/OPTIMISM.md)
  - [provers/LINEA.md](./provers/LINEA.md)
  - [provers/SCROLL.md](./provers/SCROLL.md)
  - [provers/TAIKO.md](./provers/TAIKO.md)
  - [provers/ZKSYNC.md](./provers/ZKSYNC.md)
