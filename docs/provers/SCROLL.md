# Scroll Provers

Scroll is a ZK Rollup that settles to Ethereum. Unlike other rollups that store block hashes, Scroll stores **state roots directly** in its L1 contract, which simplifies the verification process.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Ethereum (L1)                                  │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                         ScrollChain                                │  │
│  │  mapping(uint256 batchIndex => bytes32 stateRoot)                 │  │
│  │              finalizedStateRoots                                   │  │
│  │                                                                    │  │
│  │  • Stores Scroll L2 state roots (not block hashes!)               │  │
│  │  • Indexed by batch number, not block number                      │  │
│  │  • Updated after ZK proof verification                            │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ L2 state root (directly!)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           Scroll (L2)                                    │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                     Block Hash Buffer                              │  │
│  │  mapping(uint256 blockNumber => bytes32 blockHash)                │  │
│  │                                                                    │  │
│  │  • Stores L1 block hashes pushed via the bridge                   │  │
│  │  • Uses standard MPT proofs                                       │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                   Standard MPT State                               │  │
│  │  • Scroll uses Ethereum-compatible state trie                     │  │
│  │  • Proofs via eth_getProof                                        │  │
│  │  • Keccak256 hashing                                              │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## Key Difference: State Roots, Not Block Hashes

**Critical distinction**: Scroll stores state roots directly, not block hashes. This means:

1. `getTargetStateCommitment` returns a **state root** (not a block hash)
2. `verifyStorageSlot` can verify **directly against the state root** (no block header needed)
3. Storage proofs are simpler than other chains

```
Other Rollups:
  blockHash → blockHeader → stateRoot → accountProof → storageProof

Scroll:
  stateRoot → accountProof → storageProof
  (Skip the block hash and header steps!)
```

## ChildToParentProver

**Direction**: Scroll (L2) → Ethereum (L1)

This prover reads L1 block hashes from a block hash buffer contract on Scroll.

### Configuration

```solidity
contract ChildToParentProver is IStateProver {
    /// @dev Block hash buffer address (deployment-specific)
    address public immutable blockHashBuffer;
    
    /// @dev Storage slot for parentChainBlockHash mapping
    uint256 public constant blockHashMappingSlot = 1;
    
    /// @dev Scroll chain ID
    uint256 public immutable homeChainId;
}
```

### Functions

#### `getTargetStateCommitment`

**Called on**: Scroll (home chain)  
**Returns**: Ethereum block hash

```solidity
function getTargetStateCommitment(bytes calldata input) 
    external view returns (bytes32 targetStateCommitment)
{
    uint256 targetBlockNumber = abi.decode(input, (uint256));
    targetStateCommitment = IBuffer(blockHashBuffer).parentChainBlockHash(targetBlockNumber);
}
```

**Input encoding**: `abi.encode(uint256 targetBlockNumber)`

#### `verifyTargetStateCommitment`

**Called on**: Remote chains (not Scroll)  
**Returns**: Ethereum block hash

```solidity
function verifyTargetStateCommitment(bytes32 homeStateCommitment, bytes calldata input)
    external view returns (bytes32 targetStateCommitment)
{
    (
        bytes memory rlpBlockHeader,
        uint256 targetBlockNumber,
        bytes memory accountProof,
        bytes memory storageProof
    ) = abi.decode(input, (bytes, uint256, bytes, bytes));

    uint256 slot = SlotDerivation.deriveMapping(
        bytes32(blockHashMappingSlot), 
        targetBlockNumber
    );

    targetStateCommitment = ProverUtils.getSlotFromBlockHeader(
        homeStateCommitment, rlpBlockHeader, blockHashBuffer, slot, accountProof, storageProof
    );
}
```

**Input encoding**:
```solidity
abi.encode(
    bytes rlpBlockHeader,      // RLP-encoded Scroll block header
    uint256 targetBlockNumber, // L1 block number
    bytes accountProof,        // MPT proof for buffer contract
    bytes storageProof         // MPT proof for storage slot
)
```

#### `verifyStorageSlot`

Standard MPT verification against Ethereum block hash.

## ParentToChildProver

**Direction**: Ethereum (L1) → Scroll (L2)

This prover verifies Scroll L2 state from Ethereum by reading state roots from the ScrollChain contract.

### Configuration

```solidity
contract ParentToChildProver is IStateProver {
    /// @dev ScrollChain address on Ethereum
    address public immutable scrollChain;
    
    /// @dev Storage slot for finalizedStateRoots mapping
    uint256 public immutable finalizedStateRootsSlot;
    
    /// @dev Ethereum chain ID
    uint256 public immutable homeChainId;
}
```

**Common values**:
- Scroll Mainnet ScrollChain: `0xa13BAF47339d63B743e7Da8741db5456DAc1E556`
- Scroll Sepolia ScrollChain: `0x2D567EcE699Eabe5afCd141eDB7A4f2D0D6ce8a0`
- `finalizedStateRootsSlot`: Varies by deployment (check contract storage layout)

### Functions

#### `getTargetStateCommitment`

**Called on**: Ethereum (home chain)  
**Returns**: Scroll state root (NOT block hash)

```solidity
function getTargetStateCommitment(bytes calldata input) 
    external view returns (bytes32 targetStateCommitment)
{
    uint256 batchIndex = abi.decode(input, (uint256));
    targetStateCommitment = IScrollChain(scrollChain).finalizedStateRoots(batchIndex);
    
    if (targetStateCommitment == bytes32(0)) {
        revert StateRootNotFound();
    }
}
```

**Input encoding**: `abi.encode(uint256 batchIndex)`

**Note**: Uses `batchIndex`, not block number.

#### `verifyTargetStateCommitment`

**Called on**: Remote chains (not Ethereum)  
**Returns**: Scroll state root

```solidity
function verifyTargetStateCommitment(bytes32 homeStateCommitment, bytes calldata input)
    external view returns (bytes32 targetStateCommitment)
{
    (
        bytes memory rlpBlockHeader,
        uint256 batchIndex,
        bytes memory accountProof,
        bytes memory storageProof
    ) = abi.decode(input, (bytes, uint256, bytes, bytes));

    uint256 slot = SlotDerivation.deriveMapping(
        bytes32(finalizedStateRootsSlot), 
        batchIndex
    );

    targetStateCommitment = ProverUtils.getSlotFromBlockHeader(
        homeStateCommitment, rlpBlockHeader, scrollChain, slot, accountProof, storageProof
    );

    if (targetStateCommitment == bytes32(0)) {
        revert StateRootNotFound();
    }
}
```

**Input encoding**:
```solidity
abi.encode(
    bytes rlpBlockHeader,   // RLP-encoded Ethereum block header
    uint256 batchIndex,     // Scroll batch index
    bytes accountProof,     // MPT proof for ScrollChain
    bytes storageProof      // MPT proof for finalizedStateRoots[batchIndex]
)
```

#### `verifyStorageSlot`

**Key difference**: Verifies directly against state root (no block header needed).

```solidity
function verifyStorageSlot(bytes32 targetStateCommitment, bytes calldata input)
    external pure returns (address account, uint256 slot, bytes32 value)
{
    bytes memory accountProof;
    bytes memory storageProof;
    (account, slot, accountProof, storageProof) = 
        abi.decode(input, (address, uint256, bytes, bytes));

    // Verify directly against state root - no block header!
    value = ProverUtils.getStorageSlotFromStateRoot(
        targetStateCommitment,  // This IS the state root
        accountProof,
        storageProof,
        account,
        slot
    );
}
```

**Input encoding** (simpler than other chains):
```solidity
abi.encode(
    address account,        // Contract address on Scroll
    uint256 slot,          // Storage slot
    bytes accountProof,    // MPT account proof
    bytes storageProof     // MPT storage proof
)
```

**Note**: No `rlpBlockHeader` needed because `targetStateCommitment` is already the state root!

## Usage Example: Verifying Scroll Message from Ethereum

```solidity
// On Ethereum, verify a message broadcast on Scroll

// 1. Route: Ethereum → Scroll
address[] memory route = new address[](1);
route[0] = scrollParentToChildPointer;

// 2. Input: Batch index (not block number)
bytes[] memory scpInputs = new bytes[](1);
scpInputs[0] = abi.encode(batchIndex);

// 3. Storage proof (simpler - no block header!)
bytes memory broadcasterProof = abi.encode(
    broadcasterAddress,    // Contract on Scroll
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

## Batch Index vs Block Number

Scroll organizes state commitments by **batch** rather than individual blocks:

```
Batch 1: Blocks 1-100
Batch 2: Blocks 101-250
Batch 3: Blocks 251-400
...
```

When generating proofs:
1. Find the block number of the transaction
2. Look up which batch contains that block
3. Use the batch index in the prover inputs
4. Generate proofs against the state root at the end of that batch

### Finding Batch Index

```javascript
// Use Scroll RPC or explorer to find batch for block
const batchIndex = await scrollProvider.send('scroll_getBatchIndexByBlockNumber', [blockNumber]);
```

## Generating Proofs

### Standard eth_getProof

Since Scroll uses standard MPT, use regular `eth_getProof`:

```javascript
const proof = await scrollProvider.send('eth_getProof', [
    contractAddress,
    [storageSlot],
    blockNumber  // Block within the batch
]);

// For verifyStorageSlot, encode without block header:
const encodedProof = ethers.utils.defaultAbiCoder.encode(
    ['address', 'uint256', 'bytes', 'bytes'],
    [
        contractAddress,
        storageSlot,
        encodeProof(proof.accountProof),
        encodeProof(proof.storageProof[0].proof)
    ]
);
```

## Key Considerations

### State Root Simplification

The direct state root approach offers:
- **Simpler proofs**: No block header verification needed
- **Smaller proof size**: One fewer proof component
- **Faster verification**: Skip keccak256(blockHeader) check

### Batch Indexing

Unlike block-indexed systems:
- State roots are committed per batch, not per block
- Multiple blocks share the same committed state root
- Proof must be generated against the batch's final state

### Finality

Scroll's ZK proofs provide:
- Faster finality than optimistic rollups
- State root available once ZK proof is verified on L1
- No challenge period

## Related Documentation

- [../PROVERS.md](../PROVERS.md) - General prover architecture
- [../RECEIVER.md](../RECEIVER.md) - How routes and verification work
- [Scroll Documentation](https://docs.scroll.io/)
