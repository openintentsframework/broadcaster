# Linea Provers

Linea is a ZK Rollup that settles to Ethereum. Unlike most rollups that use Merkle-Patricia Tries (MPT), Linea uses **Sparse Merkle Trees (SMT)** with **MiMC hashing** for its state structure. This requires special handling in the provers.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Ethereum (L1)                                  │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                         LineaRollup                                │  │
│  │  mapping(uint256 blockNumber => bytes32 stateRootHash)            │  │
│  │                                                                    │  │
│  │  • Stores Linea L2 state roots (SMT roots, not block hashes)      │  │
│  │  • Updated after ZK proof verification                            │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ L2 SMT state root
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                            Linea (L2)                                    │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                     Block Hash Buffer                              │  │
│  │  mapping(uint256 blockNumber => bytes32 blockHash)                │  │
│  │                                                                    │  │
│  │  • Stores L1 block hashes pushed via the bridge                   │  │
│  │  • Uses standard MPT proofs for L1 state                          │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                   Sparse Merkle Tree State                         │  │
│  │  • 42-level binary tree with MiMC hashing                         │  │
│  │  • Proofs via linea_getProof RPC method                           │  │
│  │  • Different from eth_getProof format                             │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## Understanding Linea's SMT

### Key Differences from MPT

| Aspect | MPT (Ethereum) | SMT (Linea) |
|--------|---------------|-------------|
| Structure | Patricia Trie | Binary Merkle Tree |
| Hash Function | Keccak256 | MiMC |
| Proof Format | Variable-length nodes | Fixed 42 levels |
| Proof RPC | `eth_getProof` | `linea_getProof` |
| Key Derivation | Keccak256 | MiMC |

### Proof Components

Linea proofs from `linea_getProof` include:

```
Account Proof:
├── leafIndex: Position in the tree
├── proof.proofRelatedNodes: 42 sibling hashes
└── proof.value: 192-byte account data

Storage Proof:
├── leafIndex: Position in storage tree
├── proof.proofRelatedNodes: 42 sibling hashes
└── value: Storage slot value
```

### Account Data Structure (192 bytes)

```solidity
struct Account {
    uint256 nonce;
    uint256 balance;
    bytes32 storageRoot;  // SMT root of account's storage
    bytes32 mimcCodeHash; // MiMC hash of code
    bytes32 keccakCodeHash;
    uint64 codeSize;
}
```

## ChildToParentProver

**Direction**: Linea (L2) → Ethereum (L1)

This prover reads L1 block hashes from a block hash buffer contract on Linea. It uses **standard MPT proofs** because it's proving against Linea's internal buffer storage.

### Configuration

```solidity
contract ChildToParentProver is IStateProver {
    /// @dev Block hash buffer address (deployment-specific)
    address public immutable blockHashBuffer;
    
    /// @dev Storage slot for parentChainBlockHash mapping
    uint256 public constant blockHashMappingSlot = 1;
    
    /// @dev Linea chain ID
    uint256 public immutable homeChainId;
}
```

### Functions

#### `getTargetStateCommitment`

**Called on**: Linea (home chain)  
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

**Called on**: Remote chains (not Linea)  
**Returns**: Ethereum block hash (proven from Linea state)

Uses standard MPT proofs against the buffer contract.

**Input encoding**:
```solidity
abi.encode(
    bytes rlpBlockHeader,      // RLP-encoded Linea block header
    uint256 targetBlockNumber, // L1 block number
    bytes accountProof,        // MPT proof for buffer contract
    bytes storageProof         // MPT proof for storage slot
)
```

#### `verifyStorageSlot`

Standard MPT verification against Ethereum state.

## ParentToChildProver

**Direction**: Ethereum (L1) → Linea (L2)

This prover verifies Linea L2 state from Ethereum. The critical difference is that `verifyStorageSlot` uses **SMT proofs with MiMC hashing**.

### Configuration

```solidity
contract ParentToChildProver is IStateProver {
    /// @dev LineaRollup address on Ethereum
    address public immutable lineaRollup;
    
    /// @dev Storage slot for stateRootHashes mapping
    uint256 public immutable stateRootHashesSlot;
    
    /// @dev Ethereum chain ID
    uint256 public immutable homeChainId;
}
```

### Functions

#### `getTargetStateCommitment`

**Called on**: Ethereum (home chain)  
**Returns**: Linea SMT state root

```solidity
function getTargetStateCommitment(bytes calldata input) 
    external view returns (bytes32 targetStateCommitment)
{
    uint256 l2BlockNumber = abi.decode(input, (uint256));
    targetStateCommitment = ZkEvmV2(lineaRollup).stateRootHashes(l2BlockNumber);
    
    if (targetStateCommitment == bytes32(0)) {
        revert TargetStateRootNotFound();
    }
}
```

**Input encoding**: `abi.encode(uint256 l2BlockNumber)`

**Important**: The returned value is an **SMT state root**, not a block hash.

#### `verifyTargetStateCommitment`

**Called on**: Remote chains (not Ethereum)  
**Returns**: Linea SMT state root

Uses MPT proofs to verify the LineaRollup storage on Ethereum.

**Input encoding**:
```solidity
abi.encode(
    bytes rlpBlockHeader,   // RLP-encoded Ethereum block header
    uint256 l2BlockNumber,  // Linea L2 block number
    bytes accountProof,     // MPT proof for LineaRollup
    bytes storageProof      // MPT proof for stateRootHashes[l2BlockNumber]
)
```

#### `verifyStorageSlot`

**Critical**: Uses Linea's SMT verification with MiMC hashing.

```solidity
function verifyStorageSlot(bytes32 targetStateCommitment, bytes calldata input)
    external pure returns (address account, uint256 slot, bytes32 value)
{
    (
        address account,
        uint256 slot,
        uint256 accountLeafIndex,
        bytes[] memory accountProof,
        bytes memory accountValue,
        uint256 storageLeafIndex,
        bytes[] memory storageProof,
        bytes32 claimedStorageValue
    ) = abi.decode(input, (address, uint256, uint256, bytes[], bytes, uint256, bytes[], bytes32));

    // Step 1: Verify account proof against L2 state root (SMT)
    bool accountValid = SparseMerkleProof.verifyProof(
        accountProof, accountLeafIndex, targetStateCommitment
    );
    if (!accountValid) revert InvalidAccountProof();

    // Step 2: Verify account address matches proof (MiMC hash check)
    SparseMerkleProof.Leaf memory accountLeaf = 
        SparseMerkleProof.getLeaf(accountProof[accountProof.length - 1]);
    bytes32 expectedAccountHKey = SparseMerkleProof.hashAccountKey(account);
    if (accountLeaf.hKey != expectedAccountHKey) revert AccountKeyMismatch();

    // Step 3: Verify account value matches proof
    bytes32 expectedAccountHValue = SparseMerkleProof.hashAccountValue(accountValue);
    if (accountLeaf.hValue != expectedAccountHValue) revert AccountValueMismatch();

    // Step 4: Extract storage root from account value
    SparseMerkleProof.Account memory accountData = 
        SparseMerkleProof.getAccount(accountValue);

    // Step 5: Verify storage proof against account's storage root
    bool storageValid = SparseMerkleProof.verifyProof(
        storageProof, storageLeafIndex, accountData.storageRoot
    );
    if (!storageValid) revert InvalidStorageProof();

    // Step 6: Verify storage slot matches proof
    SparseMerkleProof.Leaf memory storageLeaf = 
        SparseMerkleProof.getLeaf(storageProof[storageProof.length - 1]);
    bytes32 expectedStorageHKey = SparseMerkleProof.hashStorageKey(bytes32(slot));
    if (storageLeaf.hKey != expectedStorageHKey) revert StorageKeyMismatch();

    // Step 7: Verify storage value
    bytes32 expectedHValue = SparseMerkleProof.hashStorageValue(claimedStorageValue);
    if (storageLeaf.hValue != expectedHValue) revert StorageValueMismatch();

    value = claimedStorageValue;
}
```

**Input encoding**:
```solidity
abi.encode(
    address account,            // Contract address on Linea
    uint256 slot,              // Storage slot
    uint256 accountLeafIndex,  // From accountProof.leafIndex
    bytes[] accountProof,      // 42 sibling hashes
    bytes accountValue,        // 192-byte account data
    uint256 storageLeafIndex,  // From storageProofs[0].leafIndex
    bytes[] storageProof,      // 42 sibling hashes
    bytes32 claimedStorageValue // Storage value to verify
)
```

## SparseMerkleProof Library

The `SparseMerkleProof` library handles Linea's SMT verification:

### Key Functions

```solidity
library SparseMerkleProof {
    // Verify a Merkle proof
    function verifyProof(
        bytes[] memory proof,
        uint256 leafIndex,
        bytes32 root
    ) internal pure returns (bool);

    // Extract leaf data from the last proof element
    function getLeaf(bytes memory leafData) 
        internal pure returns (Leaf memory);

    // Parse 192-byte account data
    function getAccount(bytes memory accountValue) 
        internal pure returns (Account memory);

    // Hash functions using MiMC
    function hashAccountKey(address account) internal pure returns (bytes32);
    function hashAccountValue(bytes memory value) internal pure returns (bytes32);
    function hashStorageKey(bytes32 key) internal pure returns (bytes32);
    function hashStorageValue(bytes32 value) internal pure returns (bytes32);
}
```

### MiMC Hashing

Linea uses MiMC (Minimal Multiplicative Complexity) hashing for ZK-friendliness:

```solidity
library Mimc {
    function hash(bytes memory data) internal pure returns (bytes32);
}
```

## Generating Proofs

### Using `linea_getProof`

```javascript
const proof = await provider.send('linea_getProof', [
    contractAddress,
    [storageSlot],
    blockNumber
]);

// Result structure:
{
    accountProof: {
        leafIndex: number,
        proof: {
            proofRelatedNodes: bytes32[42],
            value: bytes  // 192-byte account data
        }
    },
    storageProofs: [{
        leafIndex: number,
        proof: {
            proofRelatedNodes: bytes32[42],
            value: bytes32
        }
    }]
}
```

### Encoding for Contract

```javascript
const encodedProof = ethers.utils.defaultAbiCoder.encode(
    ['address', 'uint256', 'uint256', 'bytes[]', 'bytes', 'uint256', 'bytes[]', 'bytes32'],
    [
        contractAddress,
        storageSlot,
        proof.accountProof.leafIndex,
        proof.accountProof.proof.proofRelatedNodes,
        proof.accountProof.proof.value,
        proof.storageProofs[0].leafIndex,
        proof.storageProofs[0].proof.proofRelatedNodes,
        storageValue
    ]
);
```

## Usage Example: Verifying Linea Message from Ethereum

```solidity
// On Ethereum, verify a message broadcast on Linea

// 1. Route: Ethereum → Linea
address[] memory route = new address[](1);
route[0] = lineaParentToChildPointer;

// 2. Input: L2 block number
bytes[] memory scpInputs = new bytes[](1);
scpInputs[0] = abi.encode(l2BlockNumber);

// 3. SMT proof for Broadcaster storage on Linea
bytes memory broadcasterProof = abi.encode(
    broadcasterAddress,        // Contract on Linea
    messageSlot,               // keccak256(message, publisher)
    accountLeafIndex,          // From linea_getProof
    accountProofNodes,         // 42 sibling hashes
    accountValue,              // 192-byte account data
    storageLeafIndex,          // From linea_getProof
    storageProofNodes,         // 42 sibling hashes
    timestamp                  // Expected storage value
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

## Key Considerations

### State Root vs Block Hash

Linea stores **state roots** (SMT roots), not block hashes, on L1. The `targetStateCommitment` returned by the prover is an SMT state root used directly for storage verification.

### Proof Format Differences

- **Account proofs**: Always 42 elements (fixed tree depth)
- **Storage proofs**: Always 42 elements
- **Value verification**: Requires MiMC hash comparison, not direct value comparison

### ZK-Friendly Design

Linea's SMT and MiMC choices are optimized for ZK circuits:
- Fewer constraints than Keccak256
- Fixed tree structure enables efficient proving
- Trade-off: requires custom verification logic

## Related Documentation

- [../PROVERS.md](../PROVERS.md) - General prover architecture
- [../RECEIVER.md](../RECEIVER.md) - How routes and verification work
- [Linea Documentation](https://docs.linea.build/)
