# ZkSync Provers

ZkSync ERA is a ZK Rollup with a unique architecture that differs significantly from other rollups. Instead of storing state roots or block hashes directly, ZkSync uses an **L2 logs system** for cross-chain communication. This requires a custom broadcaster (`ZkSyncBroadcaster`) and specialized prover logic.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Ethereum (L1) / Gateway                        │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                         ZkChain Contract                           │  │
│  │  mapping(uint256 batchNumber => bytes32 l2LogsRootHash)           │  │
│  │                                                                    │  │
│  │  • Stores L2 logs Merkle root for each batch                      │  │
│  │  • L2→L1 messages are included in these logs                      │  │
│  │  • Updated after ZK proof verification                            │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ L2 logs root hash
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         ZkSync ERA (L2)                                  │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                    Block Hash Buffer                               │  │
│  │  mapping(uint256 blockNumber => bytes32 blockHash)                │  │
│  │                                                                    │  │
│  │  • Stores L1 block hashes                                         │  │
│  │  • Used by ChildToParentProver                                    │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                     L1Messenger System Contract                    │  │
│  │  Address: 0x0000000000000000000000000000000000008008               │  │
│  │                                                                    │  │
│  │  • Receives L2→L1 messages                                        │  │
│  │  • Messages included in batch L2 logs                             │  │
│  │  • ZkSyncBroadcaster sends messages here                          │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                      ZkSyncBroadcaster                             │  │
│  │  • Stores timestamp in storage (like standard Broadcaster)        │  │
│  │  • ALSO sends L2→L1 message with (slot, timestamp)                │  │
│  │  • Messages provable via L2 logs Merkle proof                     │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## Why ZkSync is Different

### No Direct Storage Proofs

ZkSync doesn't expose storage in a standard MPT format that can be proven externally. Instead:

1. **L2→L1 Communication**: Messages are sent via the L1Messenger system contract
2. **Batched Logs**: Messages are batched and committed as a Merkle tree
3. **L2 Logs Root**: Each batch has an `l2LogsRootHash` that commits to all messages

### ZkSyncBroadcaster

The standard `Broadcaster` stores timestamps in storage, but ZkSync can't prove storage slots to L1. The `ZkSyncBroadcaster` solves this by:

1. Storing the timestamp in storage (for local queries)
2. Sending an L2→L1 message containing `(slot, timestamp)`
3. The message can be proven via the L2 logs Merkle tree

## ChildToParentProver

**Direction**: ZkSync (L2) → Ethereum (L1)

This prover reads L1 block hashes from a block hash buffer on ZkSync.

### Configuration

```solidity
contract ChildToParentProver is IStateProver {
    /// @dev Block hash buffer address (deployment-specific)
    address public immutable blockHashBuffer;
    
    /// @dev Storage slot for parentChainBlockHash mapping
    uint256 public constant blockHashMappingSlot = 1;
    
    /// @dev ZkSync chain ID
    uint256 public immutable homeChainId;
}
```

### Functions

#### `getTargetStateCommitment`

**Called on**: ZkSync (home chain)  
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

**Called on**: Remote chains (not ZkSync)  
**Returns**: Ethereum block hash

Standard MPT proof verification against ZkSync block hash.

**Input encoding**:
```solidity
abi.encode(
    bytes rlpBlockHeader,      // RLP-encoded ZkSync block header
    uint256 targetBlockNumber, // L1 block number
    bytes accountProof,        // MPT proof for buffer contract
    bytes storageProof         // MPT proof for storage slot
)
```

#### `verifyStorageSlot`

Standard MPT verification.

## ParentToChildProver

**Direction**: Ethereum/Gateway (L1) → ZkSync (L2)

This prover verifies ZkSync L2 state by proving message inclusion in the L2 logs Merkle tree.

### Configuration

```solidity
contract ParentToChildProver is IStateProver {
    /// @dev ZkChain contract on the gateway/L1
    IZkChain public immutable gatewayZkChain;
    
    /// @dev Storage slot for l2LogsRootHash mapping
    uint256 public immutable l2LogsRootHashSlot;
    
    /// @dev Child chain ID (ZkSync L2)
    uint256 public immutable childChainId;
    
    /// @dev Gateway chain ID (settlement layer)
    uint256 public immutable gatewayChainId;
    
    /// @dev Home chain ID (where prover is deployed)
    uint256 public immutable homeChainId;
}
```

### L2 Log Structure

ZkSync L2 logs have a specific format:

```solidity
struct L2Log {
    uint8 l2ShardId;        // Always 0 for now
    bool isService;         // True for system messages
    uint16 txNumberInBatch; // Transaction index in batch
    address sender;         // L1Messenger address (0x8008)
    bytes32 key;            // Encoded message sender
    bytes32 value;          // Hash of message data
}
```

### L2 Message Structure

```solidity
struct L2Message {
    uint16 txNumberInBatch; // Transaction index
    address sender;         // Original L2 sender (Broadcaster)
    bytes data;             // Encoded (slot, timestamp)
}
```

### Proof Structure

```solidity
struct ZkSyncProof {
    uint256 batchNumber;    // Batch containing the message
    uint256 index;          // Leaf index in Merkle tree
    L2Message message;      // The message to prove
    bytes32[] proof;        // Merkle proof (with metadata)
}
```

### Functions

#### `getTargetStateCommitment`

**Called on**: Gateway/L1 (home chain)  
**Returns**: L2 logs root hash

```solidity
function getTargetStateCommitment(bytes calldata input) 
    external view returns (bytes32 targetStateCommitment)
{
    uint256 batchNumber = abi.decode(input, (uint256));
    targetStateCommitment = gatewayZkChain.l2LogsRootHash(batchNumber);
    
    if (targetStateCommitment == bytes32(0)) {
        revert L2LogsRootHashNotFound();
    }
}
```

**Input encoding**: `abi.encode(uint256 batchNumber)`

#### `verifyTargetStateCommitment`

**Called on**: Remote chains (not home chain)  
**Returns**: L2 logs root hash (proven from L1 state)

```solidity
function verifyTargetStateCommitment(bytes32 homeStateCommitment, bytes calldata input)
    external view returns (bytes32 targetStateCommitment)
{
    (
        bytes memory rlpBlockHeader,
        uint256 batchNumber,
        bytes memory accountProof,
        bytes memory storageProof
    ) = abi.decode(input, (bytes, uint256, bytes, bytes));

    uint256 slot = SlotDerivation.deriveMapping(
        bytes32(l2LogsRootHashSlot), 
        batchNumber
    );

    targetStateCommitment = ProverUtils.getSlotFromBlockHeader(
        homeStateCommitment, rlpBlockHeader, 
        address(gatewayZkChain), slot, 
        accountProof, storageProof
    );
}
```

**Input encoding**:
```solidity
abi.encode(
    bytes rlpBlockHeader,   // RLP-encoded L1 block header
    uint256 batchNumber,    // ZkSync batch number
    bytes accountProof,     // MPT proof for ZkChain contract
    bytes storageProof      // MPT proof for l2LogsRootHash[batchNumber]
)
```

#### `verifyStorageSlot`

**Key difference**: Uses L2 logs Merkle proof instead of storage proof.

```solidity
function verifyStorageSlot(bytes32 targetStateCommitment, bytes calldata input)
    external view returns (address account, uint256 slot, bytes32 value)
{
    (
        ZkSyncProof memory proof,
        address senderAccount,
        bytes32 message
    ) = abi.decode(input, (ZkSyncProof, address, bytes32));

    account = senderAccount;

    // Convert L2Message to L2Log format
    L2Log memory log = _l2MessageToLog(proof.message);

    // Hash the log
    bytes32 hashedLog = keccak256(abi.encodePacked(
        log.l2ShardId,
        log.isService,
        log.txNumberInBatch,
        log.sender,
        log.key,
        log.value
    ));

    // Verify Merkle proof
    if (!_proveL2LeafInclusion({
        _chainId: childChainId,
        _blockOrBatchNumber: proof.batchNumber,
        _leafProofMask: proof.index,
        _leaf: hashedLog,
        _proof: proof.proof,
        _targetBatchRoot: targetStateCommitment
    })) {
        revert BatchSettlementRootMismatch();
    }

    // Extract slot and timestamp from message data
    (bytes32 slotSent, bytes32 timestamp) = abi.decode(
        proof.message.data, 
        (bytes32, bytes32)
    );

    // Verify slot matches expected
    bytes32 expectedSlot = keccak256(abi.encode(message, account));
    if (slotSent != expectedSlot) {
        revert SlotMismatch();
    }

    slot = uint256(slotSent);
    value = timestamp;
}
```

**Input encoding**:
```solidity
abi.encode(
    ZkSyncProof proof,      // Merkle proof structure
    address senderAccount,  // Publisher address
    bytes32 message        // The broadcast message
)
```

### Merkle Proof Verification

ZkSync uses a custom Merkle tree structure with metadata:

```solidity
// Proof metadata (first element):
// - Byte 0: Version (0x01 for new format)
// - Byte 1: Log leaf proof length
// - Byte 2: Batch leaf proof length
// - Byte 3: Is final proof node

function _proveL2LeafInclusion(
    uint256 _chainId,
    uint256 _blockOrBatchNumber,
    uint256 _leafProofMask,
    bytes32 _leaf,
    bytes32[] memory _proof,
    bytes32 _targetBatchRoot
) internal view returns (bool);
```

The verification may be recursive for chains using the Gateway as a settlement layer.

## Message Conversion

The L2Message from the Broadcaster is converted to L2Log format:

```solidity
function _l2MessageToLog(L2Message memory _message) 
    internal pure returns (L2Log memory) 
{
    return L2Log({
        l2ShardId: 0,
        isService: true,
        txNumberInBatch: _message.txNumberInBatch,
        sender: 0x0000000000000000000000000000000000008008,  // L1Messenger
        key: bytes32(uint256(uint160(_message.sender))),
        value: keccak256(_message.data)
    });
}
```

## Usage Example: Verifying ZkSync Message from Ethereum

```solidity
// On Ethereum, verify a message broadcast on ZkSync

// 1. Route: Ethereum → ZkSync (single hop)
address[] memory route = new address[](1);
route[0] = zkSyncParentToChildPointer;

// 2. Input: Batch number
bytes[] memory scpInputs = new bytes[](1);
scpInputs[0] = abi.encode(batchNumber);

// 3. ZkSync proof structure
bytes32[] memory merkleProof = new bytes32[](36);
// ... populate with actual proof data

ZkSyncProof memory proof = ZkSyncProof({
    batchNumber: batchNumber,
    index: leafIndex,
    message: L2Message({
        txNumberInBatch: txNumber,
        sender: broadcasterAddress,
        data: abi.encode(messageSlot, timestamp)
    }),
    proof: merkleProof
});

bytes memory broadcasterProof = abi.encode(
    proof,
    publisherAddress,
    message
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

## Generating Proofs

### Getting the L2 Log Proof

Use the ZkSync API to get the Merkle proof:

```javascript
// Using ZkSync SDK
const receipt = await provider.getTransactionReceipt(txHash);

// Get the L2→L1 log proof
const proof = await provider.getLogProof(txHash, logIndex);

// Structure the ZkSyncProof
const zkSyncProof = {
    batchNumber: receipt.l1BatchNumber,
    index: proof.id,
    message: {
        txNumberInBatch: receipt.l1BatchTxIndex,
        sender: broadcasterAddress,
        data: encodedData  // abi.encode(slot, timestamp)
    },
    proof: proof.proof
};
```

## Key Considerations

### ZkSyncBroadcaster Required

The standard `Broadcaster` won't work on ZkSync because storage proofs can't be verified. Always use `ZkSyncBroadcaster` which sends L2→L1 messages.

### Gateway Architecture

ZkSync ERA may use a Gateway chain as an intermediate settlement layer:
- L2 → Gateway → L1
- The prover handles this via recursive proof verification
- `gatewayChainId` identifies the settlement layer

### Batch Finality

Messages are only provable after:
1. The batch containing the message is committed
2. The ZK proof for that batch is verified
3. The `l2LogsRootHash` is written to the ZkChain contract

### Message Format

The `ZkSyncBroadcaster` sends: `abi.encode(slot, timestamp)`
- `slot`: `keccak256(abi.encode(message, publisher))`
- `timestamp`: `block.timestamp` when broadcast

This matches the storage layout of the standard Broadcaster, enabling consistent verification.

## Related Documentation

- [../BROADCASTER.md](../BROADCASTER.md) - ZkSyncBroadcaster details
- [../PROVERS.md](../PROVERS.md) - General prover architecture
- [../RECEIVER.md](../RECEIVER.md) - How routes and verification work
- [ZkSync Documentation](https://docs.zksync.io/)
