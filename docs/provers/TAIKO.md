# Taiko Provers

Taiko is a Based Rollup (type-1 ZK-EVM) that settles to Ethereum. It uses the `SignalService` contract on both L1 and L2 to store cross-chain state commitments (block hashes) via checkpoints.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Ethereum (L1)                                  │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                      SignalService (L1)                            │  │
│  │  mapping(uint48 blockNumber => Checkpoint) checkpoints            │  │
│  │                                                                    │  │
│  │  struct Checkpoint {                                              │  │
│  │      uint48 blockNumber;                                          │  │
│  │      bytes32 blockHash;                                           │  │
│  │      bytes32 stateRoot;                                           │  │
│  │  }                                                                │  │
│  │                                                                    │  │
│  │  • Stores Taiko L2 block hashes after ZK proof verification       │  │
│  │  • Indexed by L2 block number                                     │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ L2 block hash
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           Taiko (L2)                                     │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                      SignalService (L2)                            │  │
│  │  mapping(uint48 blockNumber => Checkpoint) checkpoints            │  │
│  │                                                                    │  │
│  │  • Stores L1 block hashes synced from L1                          │  │
│  │  • Same checkpoint structure as L1                                │  │
│  │  • Indexed by L1 block number                                     │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                   Standard MPT State                               │  │
│  │  • Taiko is EVM-equivalent (type-1 ZK-EVM)                        │  │
│  │  • Standard eth_getProof works                                    │  │
│  │  • Ethereum-identical block structure                             │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## Checkpoint Structure

Both L1 and L2 SignalService contracts use the same checkpoint structure:

```solidity
interface ICheckpointStore {
    struct Checkpoint {
        uint48 blockNumber;    // Block number this checkpoint refers to
        bytes32 blockHash;     // Block hash of that block
        bytes32 stateRoot;     // State root (may not always be populated)
    }

    function getCheckpoint(uint48 _blockNumber) 
        external view returns (Checkpoint memory);
}
```

## ChildToParentProver

**Direction**: Taiko (L2) → Ethereum (L1)

This prover verifies Ethereum state from Taiko by reading L1 block hashes stored in the L2 SignalService.

### Configuration

```solidity
contract ChildToParentProver is IStateProver {
    /// @dev L2 SignalService address
    address public immutable signalService;
    
    /// @dev Storage slot for checkpoints mapping
    uint256 public immutable checkpointsSlot;
    
    /// @dev Taiko L2 chain ID
    uint256 public immutable homeChainId;
}
```

### Functions

#### `getTargetStateCommitment`

**Called on**: Taiko L2 (home chain)  
**Returns**: Ethereum block hash

```solidity
function getTargetStateCommitment(bytes calldata input) 
    external view returns (bytes32 targetStateCommitment)
{
    uint48 l1BlockNumber = abi.decode(input, (uint48));
    
    Checkpoint memory checkpoint = 
        ICheckpointStore(signalService).getCheckpoint(l1BlockNumber);
    
    targetStateCommitment = checkpoint.blockHash;
    
    if (targetStateCommitment == bytes32(0)) {
        revert TargetBlockHashNotFound();
    }
}
```

**Input encoding**: `abi.encode(uint48 l1BlockNumber)`

#### `verifyTargetStateCommitment`

**Called on**: Remote chains (not Taiko L2)  
**Returns**: Ethereum block hash (proven from Taiko L2 state)

```solidity
function verifyTargetStateCommitment(bytes32 homeBlockHash, bytes calldata input)
    external view returns (bytes32 targetStateCommitment)
{
    (
        bytes memory rlpBlockHeader,
        uint48 l1BlockNumber,
        bytes memory accountProof,
        bytes memory storageProof
    ) = abi.decode(input, (bytes, uint48, bytes, bytes));

    // Calculate slot for checkpoints[l1BlockNumber]
    // The blockHash is stored at the base slot of the struct
    uint256 slot = SlotDerivation.deriveMapping(
        bytes32(checkpointsSlot), 
        l1BlockNumber
    );

    targetStateCommitment = ProverUtils.getSlotFromBlockHeader(
        homeBlockHash, rlpBlockHeader, signalService, slot, accountProof, storageProof
    );

    if (targetStateCommitment == bytes32(0)) {
        revert TargetBlockHashNotFound();
    }
}
```

**Input encoding**:
```solidity
abi.encode(
    bytes rlpBlockHeader,     // RLP-encoded Taiko L2 block header
    uint48 l1BlockNumber,     // L1 block number to retrieve
    bytes accountProof,       // MPT proof for SignalService
    bytes storageProof        // MPT proof for checkpoints[l1BlockNumber]
)
```

#### `verifyStorageSlot`

Standard MPT verification against Ethereum block hash.

**Input encoding**:
```solidity
abi.encode(
    bytes rlpBlockHeader,   // RLP-encoded Ethereum block header
    address account,        // Contract address on Ethereum
    uint256 slot,          // Storage slot
    bytes accountProof,    // MPT account proof
    bytes storageProof     // MPT storage proof
)
```

## ParentToChildProver

**Direction**: Ethereum (L1) → Taiko (L2)

This prover verifies Taiko L2 state from Ethereum by reading L2 block hashes from the L1 SignalService.

### Configuration

```solidity
contract ParentToChildProver is IStateProver {
    /// @dev L1 SignalService address
    address public immutable signalService;
    
    /// @dev Storage slot for checkpoints mapping
    uint256 public immutable checkpointsSlot;
    
    /// @dev Ethereum L1 chain ID
    uint256 public immutable homeChainId;
}
```

### Functions

#### `getTargetStateCommitment`

**Called on**: Ethereum L1 (home chain)  
**Returns**: Taiko L2 block hash

```solidity
function getTargetStateCommitment(bytes calldata input) 
    external view returns (bytes32 targetStateCommitment)
{
    uint48 l2BlockNumber = abi.decode(input, (uint48));
    
    Checkpoint memory checkpoint = 
        ICheckpointStore(signalService).getCheckpoint(l2BlockNumber);
    
    targetStateCommitment = checkpoint.blockHash;
    
    if (targetStateCommitment == bytes32(0)) {
        revert TargetBlockHashNotFound();
    }
}
```

**Input encoding**: `abi.encode(uint48 l2BlockNumber)`

#### `verifyTargetStateCommitment`

**Called on**: Remote chains (not Ethereum L1)  
**Returns**: Taiko L2 block hash

```solidity
function verifyTargetStateCommitment(bytes32 homeBlockHash, bytes calldata input)
    external view returns (bytes32 targetStateCommitment)
{
    (
        bytes memory rlpBlockHeader,
        uint48 l2BlockNumber,
        bytes memory accountProof,
        bytes memory storageProof
    ) = abi.decode(input, (bytes, uint48, bytes, bytes));

    uint256 slot = SlotDerivation.deriveMapping(
        bytes32(checkpointsSlot), 
        l2BlockNumber
    );

    targetStateCommitment = ProverUtils.getSlotFromBlockHeader(
        homeBlockHash, rlpBlockHeader, signalService, slot, accountProof, storageProof
    );

    if (targetStateCommitment == bytes32(0)) {
        revert TargetBlockHashNotFound();
    }
}
```

**Input encoding**:
```solidity
abi.encode(
    bytes rlpBlockHeader,   // RLP-encoded Ethereum block header
    uint48 l2BlockNumber,   // Taiko L2 block number
    bytes accountProof,     // MPT proof for L1 SignalService
    bytes storageProof      // MPT proof for checkpoints[l2BlockNumber]
)
```

#### `verifyStorageSlot`

Standard MPT verification against Taiko L2 block hash.

**Input encoding**:
```solidity
abi.encode(
    bytes rlpBlockHeader,   // RLP-encoded Taiko L2 block header
    address account,        // Contract address on Taiko L2
    uint256 slot,          // Storage slot
    bytes accountProof,    // MPT account proof
    bytes storageProof     // MPT storage proof
)
```

## Symmetric Design

Taiko's prover design is notably symmetric - both directions use nearly identical logic:

| Aspect | ChildToParentProver | ParentToChildProver |
|--------|-------------------|-------------------|
| Home Chain | Taiko L2 | Ethereum L1 |
| Target Chain | Ethereum L1 | Taiko L2 |
| SignalService | L2 contract | L1 contract |
| Checkpoints Key | L1 block number | L2 block number |
| Input Type | `uint48` | `uint48` |

This symmetry comes from Taiko's design where both chains maintain checkpoints of each other's state.

## Usage Example: Verifying Taiko Message from Ethereum

```solidity
// On Ethereum, verify a message broadcast on Taiko L2

// 1. Route: Ethereum → Taiko
address[] memory route = new address[](1);
route[0] = taikoParentToChildPointer;

// 2. Input: L2 block number
bytes[] memory scpInputs = new bytes[](1);
scpInputs[0] = abi.encode(uint48(l2BlockNumber));

// 3. Storage proof for Broadcaster on Taiko
bytes memory broadcasterProof = abi.encode(
    rlpTaikoBlockHeader,   // Taiko L2 block header
    broadcasterAddress,    // Broadcaster contract
    messageSlot,           // keccak256(message, publisher)
    accountProof,          // MPT account proof
    storageProof          // MPT storage proof
);

// 4. Verify
IReceiver.RemoteReadArgs memory args = IReceiver.RemoteReadArgs({
    route: route,
    scpInputs: scpInputs,
    proof: broadcasterProof
});

(bytes32 broadcasterId, uint256 timestamp) = receiver.verifyBroadcastMessage(
    args,
    message,
    publisher
);
```

## Storage Slot Calculation

The SignalService checkpoints mapping uses standard Solidity slot derivation:

```solidity
// For checkpoints[blockNumber]:
uint256 slot = uint256(keccak256(abi.encode(blockNumber, checkpointsSlot)));

// The Checkpoint struct at that slot:
// slot + 0: blockNumber (packed with other small values)
// slot + 0: blockHash (first bytes32 of struct)
// slot + 1: stateRoot

// For the prover, we only need the blockHash at the base slot
```

## Key Considerations

### Block Number Types

Taiko uses `uint48` for block numbers to save gas:
- Max value: 281,474,976,710,655
- Sufficient for billions of years of blocks
- Ensure proper type casting when generating proofs

### Based Rollup Benefits

As a based rollup, Taiko:
- Inherits Ethereum's security guarantees
- Has faster finality through ZK proofs
- Uses standard Ethereum state structure (type-1 ZK-EVM)

### SignalService Addresses

The SignalService addresses are deployment-specific. Common patterns:
- L1: Deployed to a deterministic address via CREATE2
- L2: Pre-deployed at a known system address

Check the Taiko documentation or deployment artifacts for current addresses.

### Checkpoint Availability

Checkpoints are populated:
- L1 → L2: When L1 blocks are synced to L2
- L2 → L1: After ZK proof verification on L1

There may be a delay between block production and checkpoint availability.

## Related Documentation

- [../PROVERS.md](../PROVERS.md) - General prover architecture
- [../RECEIVER.md](../RECEIVER.md) - How routes and verification work
- [Taiko Documentation](https://docs.taiko.xyz/)
