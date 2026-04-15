# Broadcaster

The Broadcaster contract is a singleton deployed on each chain that enables publishing 32-byte messages on-chain. Messages are stored in deterministic storage slots, making them provable via storage proofs from other chains.

## Core Concepts

### Message Storage

When a message is broadcast, the contract stores `block.timestamp` in a storage slot computed as:

```solidity
slot = keccak256(abi.encode(message, publisher))
```

This design provides several guarantees:

1. **Deduplication**: Each `(message, publisher)` pair can only be broadcast once
2. **Timestamping**: The exact broadcast time is recorded and provable
3. **Deterministic slots**: Any verifier can compute the expected slot without calling the contract

### Publishers

Any address that calls `broadcastMessage()` is considered a "publisher". The publisher's address becomes part of the storage slot calculation, meaning:

- Different publishers can broadcast the same message
- A single publisher cannot broadcast the same message twice
- Applications requiring multiple broadcasts of the same logical message must implement nonces at the application layer

## Interface

```solidity
interface IBroadcaster {
    /// @notice Emitted when a message is broadcast.
    event MessageBroadcast(bytes32 indexed message, address indexed publisher);

    /// @notice Broadcasts a message. Callers are called "publishers".
    /// @dev    MUST revert if the publisher has already broadcast the message.
    ///         MUST emit MessageBroadcast.
    ///         MUST store block.timestamp in slot keccak(message, msg.sender).
    function broadcastMessage(bytes32 message) external;
}
```

## Standard Broadcaster

The standard `Broadcaster` contract implements the minimal ERC-7888 specification:

```solidity
contract Broadcaster is IBroadcaster {
    error MessageAlreadyBroadcasted();

    function broadcastMessage(bytes32 message) external {
        bytes32 slot = keccak256(abi.encode(message, msg.sender));

        if (StorageSlot.getUint256Slot(slot).value != 0) {
            revert MessageAlreadyBroadcasted();
        }

        StorageSlot.getUint256Slot(slot).value = block.timestamp;

        emit MessageBroadcast(message, msg.sender);
    }
}
```

### Helper Function

The contract also includes a view function to check if a message has been broadcast:

```solidity
function hasBroadcasted(bytes32 message, address publisher) external view returns (bool)
```

This is not required by the standard but provides useful visibility without requiring storage proofs.

## ZkSync Broadcaster

ZkSync ERA has a unique architecture where L2 state is proven to L1 via L2 logs rather than storage proofs. The `ZkSyncBroadcaster` extends the standard broadcaster by sending an L2→L1 message for each broadcast:

```solidity
contract ZkSyncBroadcaster is IBroadcaster {
    IL1Messenger private _l1Messenger;

    function broadcastMessage(bytes32 message) external {
        bytes32 slot = keccak256(abi.encode(message, msg.sender));

        if (StorageSlot.getUint256Slot(slot).value != 0) {
            revert MessageAlreadyBroadcasted();
        }

        StorageSlot.getUint256Slot(slot).value = block.timestamp;

        // Send to L1 via ZkSync's L1Messenger
        _l1Messenger.sendToL1(abi.encode(slot, uint256(block.timestamp)));

        emit MessageBroadcast(message, msg.sender);
    }
}
```

### L1Messenger Integration

The `IL1Messenger` interface wraps ZkSync's native L2→L1 messaging system:

```solidity
interface IL1Messenger {
    function sendToL1(bytes calldata _message) external returns (bytes32);
}
```

The message sent to L1 contains:
- `slot`: The storage slot where the timestamp is stored (`bytes32`)
- `timestamp`: The block timestamp when the message was broadcast (`uint256`)

This data is included in ZkSync batches and can be verified on L1 using the ZkSync `ParentToChildProver`.

### Why ZkSync Needs a Custom Broadcaster

Unlike other rollups where you can directly prove storage slots via Merkle-Patricia Trie proofs, ZkSync uses:

1. **Different state tree structure**: ZkSync doesn't expose storage in a standard MPT format
2. **L2 logs for cross-chain communication**: ZkSync's native L2→L1 messaging system is the canonical way to communicate state to L1
3. **Batch settlement**: Messages are grouped into batches and their inclusion is verified via Merkle proofs against the batch's L2 logs root hash

The `ZkSyncBroadcaster` ensures messages are accessible via ZkSync's native proving mechanism.

## Usage Example

### Broadcasting a Message

```solidity
// Prepare a 32-byte message
bytes32 message = keccak256(abi.encode(
    "transfer",
    recipient,
    amount,
    nonce
));

// Broadcast on the source chain
broadcaster.broadcastMessage(message);
```

### Verifying on Destination Chain

See [RECEIVER.md](./RECEIVER.md) for details on verifying broadcast messages from other chains.

## Storage Layout Verification

The deterministic storage layout enables verification without trusting the Broadcaster contract's logic. Given:
- A block hash (or state root) from the source chain
- A storage proof for the Broadcaster contract

Any verifier can:
1. Compute the expected slot: `keccak256(abi.encode(message, publisher))`
2. Verify the storage proof against the state root
3. Confirm the slot value (timestamp) is non-zero

This makes the Broadcaster's storage "self-describing" - you don't need to trust any specific contract implementation to verify a message was broadcast.

## Deployment Considerations

- The Broadcaster should be deployed as a singleton on each chain
- The contract address should be consistent across chains when possible (using CREATE2)
- For ZkSync chains, use `ZkSyncBroadcaster` instead of the standard `Broadcaster`
- The L1Messenger address on ZkSync ERA mainnet is a system contract

## Related Documentation

- [RECEIVER.md](./RECEIVER.md) - Verifying broadcast messages on destination chains
- [PROVERS.md](./PROVERS.md) - Understanding StateProvers and verification logic
- [provers/ZKSYNC.md](./provers/ZKSYNC.md) - ZkSync-specific prover implementation details
