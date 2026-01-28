# Arbitrum Provers

Arbitrum is an Optimistic Rollup that settles to Ethereum. It stores finalized L2 block hashes in the L1 Outbox contract and provides access to L1 block hashes via a block hash buffer contract on L2.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Ethereum (L1)                                  │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                         Outbox Contract                            │  │
│  │  mapping(bytes32 sendRoot => bytes32 blockHash) public roots;     │  │
│  │                                                                    │  │
│  │  • Stores Arbitrum block hashes indexed by sendRoot               │  │
│  │  • Updated by the Rollup contract after challenge periods         │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ sendRoot → blockHash
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          Arbitrum (L2)                                   │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                    Block Hash Buffer                               │  │
│  │  mapping(uint256 blockNumber => bytes32 blockHash)                │  │
│  │  Address: 0x0000000048C4Ed10cF14A02B9E0AbDDA5227b071              │  │
│  │                                                                    │  │
│  │  • Stores L1 block hashes pushed by the Sequencer                 │  │
│  │  • Historical L1 block hashes available on L2                     │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## ChildToParentProver

**Direction**: Arbitrum (L2) → Ethereum (L1)

This prover enables verification of Ethereum state from Arbitrum by reading L1 block hashes from the block hash buffer contract.

### Configuration

```solidity
contract ChildToParentProver is IStateProver {
    /// @dev Block hash buffer on Arbitrum One
    address public constant blockHashBuffer = 0x0000000048C4Ed10cF14A02B9E0AbDDA5227b071;
    
    /// @dev Storage slot for parentChainBlockHash mapping
    uint256 public constant blockHashMappingSlot = 51;
    
    /// @dev Arbitrum chain ID (set at deployment)
    uint256 public immutable homeChainId;
}
```

### Functions

#### `getTargetStateCommitment`

**Called on**: Arbitrum (home chain)  
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

**Called on**: Remote chains (not Arbitrum)  
**Returns**: Ethereum block hash (proven from Arbitrum state)

```solidity
function verifyTargetStateCommitment(bytes32 homeBlockHash, bytes calldata input)
    external view returns (bytes32 targetStateCommitment)
{
    (
        bytes memory rlpBlockHeader,
        uint256 targetBlockNumber,
        bytes memory accountProof,
        bytes memory storageProof
    ) = abi.decode(input, (bytes, uint256, bytes, bytes));

    // Calculate storage slot: keccak256(abi.encode(targetBlockNumber, 51))
    uint256 slot = SlotDerivation.deriveMapping(bytes32(blockHashMappingSlot), targetBlockNumber);

    // Verify proof and return L1 block hash
    targetStateCommitment = ProverUtils.getSlotFromBlockHeader(
        homeBlockHash, rlpBlockHeader, blockHashBuffer, slot, accountProof, storageProof
    );
}
```

**Input encoding**:
```solidity
abi.encode(
    bytes rlpBlockHeader,      // RLP-encoded Arbitrum block header
    uint256 targetBlockNumber, // L1 block number to retrieve
    bytes accountProof,        // MPT proof for buffer contract
    bytes storageProof         // MPT proof for storage slot
)
```

#### `verifyStorageSlot`

**Called on**: Any chain  
**Verifies**: Storage slot against Ethereum block hash

```solidity
function verifyStorageSlot(bytes32 targetStateCommitment, bytes calldata input)
    external pure returns (address account, uint256 slot, bytes32 value)
{
    (
        bytes memory rlpBlockHeader,
        address account,
        uint256 slot,
        bytes memory accountProof,
        bytes memory storageProof
    ) = abi.decode(input, (bytes, address, uint256, bytes, bytes));

    value = ProverUtils.getSlotFromBlockHeader(
        targetStateCommitment, rlpBlockHeader, account, slot, accountProof, storageProof
    );
}
```

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

**Direction**: Ethereum (L1) → Arbitrum (L2)

This prover enables verification of Arbitrum state from Ethereum by reading L2 block hashes from the Outbox contract.

### Configuration

```solidity
contract ParentToChildProver is IStateProver {
    /// @dev Outbox contract address on Ethereum (chain-specific)
    address public immutable outbox;
    
    /// @dev Storage slot for roots mapping in Outbox (typically 3)
    uint256 public immutable rootsSlot;
    
    /// @dev Ethereum chain ID
    uint256 public immutable homeChainId;
}
```

**Outbox addresses (examples)**:
- Arbitrum One: `0x0B9857ae2D4A3DBe74ffE1d7DF045bb7F96E4840`
- Arbitrum Sepolia: `0x65f07C7D521164a4d5DaC6eB8Fac8DA067A3B78F`

### Functions

#### `getTargetStateCommitment`

**Called on**: Ethereum (home chain)  
**Returns**: Arbitrum block hash

```solidity
function getTargetStateCommitment(bytes calldata input) 
    external view returns (bytes32 targetStateCommitment)
{
    bytes32 sendRoot = abi.decode(input, (bytes32));
    targetStateCommitment = IOutbox(outbox).roots(sendRoot);
    
    if (targetStateCommitment == bytes32(0)) {
        revert TargetBlockHashNotFound();
    }
}
```

**Input encoding**: `abi.encode(bytes32 sendRoot)`

The `sendRoot` is a commitment to the Arbitrum state that can be looked up in the Rollup contract or derived from Arbitrum blocks.

#### `verifyTargetStateCommitment`

**Called on**: Remote chains (not Ethereum)  
**Returns**: Arbitrum block hash (proven from Ethereum state)

```solidity
function verifyTargetStateCommitment(bytes32 homeBlockHash, bytes calldata input)
    external view returns (bytes32 targetStateCommitment)
{
    (
        bytes memory rlpBlockHeader,
        bytes32 sendRoot,
        bytes memory accountProof,
        bytes memory storageProof
    ) = abi.decode(input, (bytes, bytes32, bytes, bytes));

    // Calculate storage slot: keccak256(abi.encode(sendRoot, rootsSlot))
    uint256 slot = SlotDerivation.deriveMapping(bytes32(rootsSlot), sendRoot);

    targetStateCommitment = ProverUtils.getSlotFromBlockHeader(
        homeBlockHash, rlpBlockHeader, outbox, slot, accountProof, storageProof
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
    bytes32 sendRoot,       // Arbitrum sendRoot commitment
    bytes accountProof,     // MPT proof for Outbox contract
    bytes storageProof      // MPT proof for roots[sendRoot] slot
)
```

#### `verifyStorageSlot`

**Called on**: Any chain  
**Verifies**: Storage slot against Arbitrum block hash

```solidity
function verifyStorageSlot(bytes32 targetStateCommitment, bytes calldata input)
    external pure returns (address account, uint256 slot, bytes32 value)
{
    (
        bytes memory rlpBlockHeader,
        address account,
        uint256 slot,
        bytes memory accountProof,
        bytes memory storageProof
    ) = abi.decode(input, (bytes, address, uint256, bytes, bytes));

    value = ProverUtils.getSlotFromBlockHeader(
        targetStateCommitment, rlpBlockHeader, account, slot, accountProof, storageProof
    );
}
```

**Input encoding**:
```solidity
abi.encode(
    bytes rlpBlockHeader,   // RLP-encoded Arbitrum block header
    address account,        // Contract address on Arbitrum
    uint256 slot,          // Storage slot
    bytes accountProof,    // MPT account proof
    bytes storageProof     // MPT storage proof
)
```

## Usage Example: Verifying Arbitrum Message from Optimism

```solidity
// On Optimism, verify a message broadcast on Arbitrum

// 1. Route: Optimism → Ethereum → Arbitrum
address[] memory route = new address[](2);
route[0] = opChildToParentPointer;    // OP's C2P prover pointer
route[1] = arbParentToChildPointer;   // Arb's P2C prover pointer (on Ethereum)

// 2. Inputs for each hop
bytes[] memory scpInputs = new bytes[](2);

// First hop: OP C2P (get Ethereum block hash)
scpInputs[0] = bytes("");  // OP uses L1Block predeploy, no input needed

// Second hop: Arb P2C (prove Arbitrum state from Ethereum)
scpInputs[1] = abi.encode(
    rlpEthBlockHeader,     // Ethereum block header
    arbSendRoot,           // Arbitrum sendRoot
    outboxAccountProof,    // Proof for Outbox contract
    outboxStorageProof     // Proof for roots[sendRoot]
);

// 3. Final proof: Broadcaster storage on Arbitrum
bytes memory broadcasterProof = abi.encode(
    rlpArbBlockHeader,     // Arbitrum block header
    broadcasterAddress,    // Broadcaster contract
    messageSlot,           // keccak256(message, publisher)
    accountProof,          // Proof for Broadcaster
    storageProof          // Proof for message slot
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

### SendRoot vs Block Hash

Arbitrum uses a two-step lookup:
1. The `sendRoot` is a commitment included in Arbitrum blocks
2. The Outbox maps `sendRoot → blockHash`

This requires knowing the sendRoot for the Arbitrum block you want to prove against.

### Block Hash Buffer

The block hash buffer on Arbitrum:
- Is maintained by Offchain Labs' infrastructure
- Stores historical L1 block hashes
- Uses slot 51 for the `parentChainBlockHash` mapping
- Address is deterministic: `0x0000000048C4Ed10cF14A02B9E0AbDDA5227b071`

### Finality

Arbitrum's optimistic nature means:
- Block hashes are only in the Outbox after the challenge period (~1 week)
- More recent blocks may use different proving mechanisms
- The prover only works with finalized Arbitrum blocks

## Related Documentation

- [../PROVERS.md](../PROVERS.md) - General prover architecture
- [../RECEIVER.md](../RECEIVER.md) - How routes and verification work
- [Arbitrum Documentation](https://docs.arbitrum.io/)
