# Receiver

The Receiver contract is a singleton deployed on each chain that verifies broadcast messages from remote chains using cryptographic storage proofs. It orchestrates the verification process by following a **route** through a chain of StateProvers.

## Core Concepts

### Routes

A **route** is a path from the local chain to a remote chain, defined as an array of `StateProverPointer` addresses. Each pointer in the route lives on its home chain and references a StateProver that can verify the next chain's state commitment.

```
Local Chain → Chain A → Chain B → Remote Chain
    [PointerA, PointerB, PointerC]
```

**Route validity rules:**
- `route[0]`'s home chain must be the local chain
- `route[i]`'s target chain must equal `route[i+1]`'s home chain

### Remote Account Identifiers

Accounts on remote chains are uniquely identified by accumulating hashes of the route addresses plus the remote address:

```solidity
function accumulator(bytes32 acc, address addr) internal pure returns (bytes32) {
    return keccak256(abi.encode(acc, addr));
}

// Example: ID for Broadcaster at 0x3 via route [0xA, 0xB]
// id = accumulator(accumulator(accumulator(0, 0xA), 0xB), 0x3)
```

IDs are always **relative** to the local chain. The same account on a remote chain will have different IDs depending on the route taken.

### State Commitments

A **state commitment** is a `bytes32` hash that commits to a chain's state:
- **Block hash**: Most common, commits to the entire block header
- **State root**: The Merkle-Patricia Trie root of account states
- **Batch root**: Used by some rollups that commit batches instead of individual blocks

## Interface

```solidity
interface IReceiver {
    struct RemoteReadArgs {
        address[] route;      // StateProverPointer addresses along the route
        bytes[] scpInputs;    // Inputs for each StateProver
        bytes proof;          // Final storage proof for the message slot
    }

    function verifyBroadcastMessage(
        RemoteReadArgs calldata broadcasterReadArgs,
        bytes32 message,
        address publisher
    ) external view returns (bytes32 broadcasterId, uint256 timestamp);

    function updateStateProverCopy(
        RemoteReadArgs calldata scpPointerReadArgs,
        IStateProver scpCopy
    ) external returns (bytes32 scpPointerId);

    function stateProverCopy(bytes32 scpPointerId) 
        external view returns (IStateProver scpCopy);
}
```

## Verification Process

### Single-Hop Verification (L2 → L1 or L1 → L2)

For direct parent-child chain verification:

```
┌─────────────────┐                      ┌─────────────────┐
│   Local Chain   │                      │  Remote Chain   │
│                 │                      │                 │
│  ┌───────────┐  │                      │  ┌───────────┐  │
│  │ Receiver  │  │  ← storage proof ←   │  │Broadcaster│  │
│  └─────┬─────┘  │                      │  └───────────┘  │
│        │        │                      │                 │
│        ▼        │                      │                 │
│  ┌───────────┐  │                      │                 │
│  │  Pointer  │──┼──→ getTargetState ───┼────────────────►│
│  └─────┬─────┘  │                      │                 │
│        │        │                      │                 │
│        ▼        │                      │                 │
│  ┌───────────┐  │                      │                 │
│  │ Prover    │  │                      │                 │
│  └───────────┘  │                      │                 │
└─────────────────┘                      └─────────────────┘
```

1. Receiver calls `route[0]` pointer to get the prover address
2. Prover's `getTargetStateCommitment()` retrieves the remote chain's state commitment
3. Prover's `verifyStorageSlot()` verifies the storage proof and extracts the slot value

### Multi-Hop Verification (L2 → L2 via common ancestor)

For cross-L2 verification through a shared parent (e.g., Ethereum):

```
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   Local L2      │      │  Parent Chain   │      │   Remote L2     │
│   (Optimism)    │      │   (Ethereum)    │      │   (Arbitrum)    │
│                 │      │                 │      │                 │
│  ┌───────────┐  │      │  ┌───────────┐  │      │  ┌───────────┐  │
│  │ Receiver  │  │      │  │ Pointer   │◄─┼──────┼──│Broadcaster│  │
│  └─────┬─────┘  │      │  │ (Arb P2C) │  │      │  └───────────┘  │
│        │        │      │  └───────────┘  │      │                 │
│        ▼        │      │                 │      │                 │
│  ┌───────────┐  │      │                 │      │                 │
│  │ Pointer   │──┼──────┼────────────────►│      │                 │
│  │ (OP C2P)  │  │      │                 │      │                 │
│  └─────┬─────┘  │      │                 │      │                 │
│        │        │      │                 │      │                 │
│        ▼        │      │                 │      │                 │
│  ┌───────────┐  │      │                 │      │                 │
│  │Prover Copy│  │      │                 │      │                 │
│  │(Arb P2C)  │  │      │                 │      │                 │
│  └───────────┘  │      │                 │      │                 │
└─────────────────┘      └─────────────────┘      └─────────────────┘
```

Steps:
1. **Get parent state**: Local prover's `getTargetStateCommitment()` retrieves the parent chain's state commitment (e.g., Ethereum block hash)
2. **Verify remote state**: Prover copy's `verifyTargetStateCommitment()` proves the remote L2's state from the parent's state
3. **Verify storage**: Prover copy's `verifyStorageSlot()` verifies the Broadcaster's storage proof

## Internal Flow: `_readRemoteSlot`

The Receiver's core logic is in `_readRemoteSlot`:

```solidity
function _readRemoteSlot(RemoteReadArgs calldata readArgs)
    internal view
    returns (bytes32 remoteAccountId, uint256 slot, bytes32 slotValue)
{
    IStateProver prover;
    bytes32 stateCommitment;

    for (uint256 i = 0; i < readArgs.route.length; i++) {
        // Accumulate the remote account ID
        remoteAccountId = accumulator(remoteAccountId, readArgs.route[i]);

        if (i == 0) {
            // First hop: call getTargetStateCommitment on home chain
            prover = IStateProver(
                IStateProverPointer(readArgs.route[0]).implementationAddress()
            );
            stateCommitment = prover.getTargetStateCommitment(readArgs.scpInputs[0]);
        } else {
            // Subsequent hops: use prover copies with verifyTargetStateCommitment
            prover = _stateProverCopies[remoteAccountId];
            stateCommitment = prover.verifyTargetStateCommitment(
                stateCommitment, 
                readArgs.scpInputs[i]
            );
        }
    }

    // Final step: verify the storage slot
    address remoteAccount;
    (remoteAccount, slot, slotValue) = prover.verifyStorageSlot(
        stateCommitment, 
        readArgs.proof
    );

    remoteAccountId = accumulator(remoteAccountId, remoteAccount);
}
```

## StateProver Copies

The Receiver cannot call contracts on remote chains. To verify proofs from remote chains, it maintains **local copies** of StateProvers with matching bytecode.

### Registering a Copy

```solidity
function updateStateProverCopy(
    RemoteReadArgs calldata scpPointerReadArgs,
    IStateProver scpCopy
) external returns (bytes32 scpPointerId);
```

The Receiver verifies:
1. The proof reads from `STATE_PROVER_POINTER_SLOT` on the remote pointer
2. The local copy's code hash matches the pointer's stored code hash
3. The new version is higher than any existing copy (monotonicity)

### Why Code Hash Matching?

StateProvers must have identical bytecode on all chains to ensure:
- Same verification logic everywhere
- No trust assumptions about remote prover behavior
- Deterministic results regardless of execution location

## Usage Examples

### Example 1: Verify Ethereum → Arbitrum (Single Hop)

On Arbitrum, verify a message broadcast on Ethereum:

```solidity
// Setup: Deploy receiver and prover on Arbitrum
Receiver receiver = new Receiver();
ChildToParentProver prover = new ChildToParentProver(block.chainid);
StateProverPointer pointer = new StateProverPointer(owner);
pointer.setImplementationAddress(address(prover));

// Construct the route (single hop: Arbitrum → Ethereum)
address[] memory route = new address[](1);
route[0] = address(pointer);

// Prepare inputs
bytes[] memory scpInputs = new bytes[](1);
scpInputs[0] = abi.encode(ethereumBlockNumber); // Input for getTargetStateCommitment

// Storage proof for the Broadcaster on Ethereum
bytes memory storageProof = abi.encode(
    rlpBlockHeader,
    broadcasterAddress,
    slot,
    accountProof,
    storageProof
);

// Verify
IReceiver.RemoteReadArgs memory args = IReceiver.RemoteReadArgs({
    route: route,
    scpInputs: scpInputs,
    proof: storageProof
});

(bytes32 broadcasterId, uint256 timestamp) = receiver.verifyBroadcastMessage(
    args,
    message,
    publisher
);
```

### Example 2: Verify Arbitrum → Optimism (Two Hops via Ethereum)

On Optimism, verify a message broadcast on Arbitrum:

```solidity
// Step 1: Register the Arbitrum ParentToChildProver copy on Optimism
// (This proves Arbitrum state from Ethereum state)

// First, prove the Ethereum pointer's storage slot contains the prover code hash
IReceiver.RemoteReadArgs memory pointerProofArgs = IReceiver.RemoteReadArgs({
    route: [opChildToParentPointer],          // OP → Ethereum
    scpInputs: [bytes("")],                   // No input needed for OP C2P
    proof: pointerStorageProof                // Proof of pointer's code hash slot
});

receiver.updateStateProverCopy(pointerProofArgs, arbParentToChildProverCopy);

// Step 2: Verify the message from Arbitrum

address[] memory route = new address[](2);
route[0] = address(opChildToParentPointer);   // OP → Ethereum
route[1] = arbParentToChildPointerAddress;     // Ethereum → Arbitrum

bytes[] memory scpInputs = new bytes[](2);
scpInputs[0] = bytes("");                      // OP C2P: returns latest L1 block hash
scpInputs[1] = abi.encode(                     // Arb P2C: proves Arb state from Eth
    rlpEthBlockHeader,
    sendRoot,
    accountProof,
    storageProof
);

bytes memory broadcasterProof = abi.encode(
    rlpArbBlockHeader,
    broadcasterAddress,
    slot,
    accountProof,
    storageProof
);

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

## Error Handling

| Error | Cause |
|-------|-------|
| `InvalidRouteLength` | `route.length != scpInputs.length` |
| `EmptyRoute` | Empty route array provided |
| `ProverCopyNotFound` | No registered prover copy for a route hop |
| `MessageNotFound` | Storage slot value is zero (message not broadcast) |
| `WrongMessageSlot` | Proven slot doesn't match expected `keccak256(message, publisher)` |
| `WrongStateProverPointerSlot` | Update proof doesn't target `STATE_PROVER_POINTER_SLOT` |
| `DifferentCodeHash` | Local prover copy's code hash doesn't match remote pointer |
| `NewerProverVersion` | Existing prover copy has version >= new copy |

## Security Considerations

1. **Proof freshness**: Storage proofs are only valid against specific block hashes. Ensure proofs are generated against finalized blocks.

2. **Route trust**: The route determines which StateProverPointers (and their owners) are trusted. Only use routes through trusted pointers.

3. **Version monotonicity**: Prover copies can only be updated to newer versions, preventing rollback attacks.

4. **Finalization delays**: Messages can only be verified after their containing block is finalized. Total propagation time equals the sum of finalization times along the route.

## Related Documentation

- [BROADCASTER.md](./BROADCASTER.md) - How messages are broadcast
- [PROVERS.md](./PROVERS.md) - StateProver and StateProverPointer details
- Chain-specific provers: [ARBITRUM.md](./provers/ARBITRUM.md), [OPTIMISM.md](./provers/OPTIMISM.md), etc.
