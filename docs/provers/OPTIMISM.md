# Optimism Provers

Optimism (and OP Stack chains) is an Optimistic Rollup that settles to Ethereum. The L2 has access to L1 block hashes via the `L1Block` predeploy, and L1 can verify L2 state through the `AnchorStateRegistry` and Fault Dispute Games.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Ethereum (L1)                                  │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                    AnchorStateRegistry                             │  │
│  │  Storage slot 3: address anchorGame                               │  │
│  │                                                                    │  │
│  │  • Points to the current valid FaultDisputeGame                   │  │
│  │  • Game contains the L2 output root (rootClaim)                   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                     FaultDisputeGame (CWIA Proxy)                  │  │
│  │  rootClaim = keccak256(OutputRootProof)                           │  │
│  │                                                                    │  │
│  │  OutputRootProof {                                                │  │
│  │    version, stateRoot, messagePasserStorageRoot, latestBlockhash  │  │
│  │  }                                                                │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ L2 block hash in OutputRootProof
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          Optimism (L2)                                   │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                      L1Block Predeploy                             │  │
│  │  Address: 0x4200000000000000000000000000000000000015               │  │
│  │  Storage slot 2: bytes32 hash (latest L1 block hash)              │  │
│  │                                                                    │  │
│  │  • Updated by the depositor account each L2 block                 │  │
│  │  • Only stores the LATEST L1 block hash (no history)              │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## ChildToParentProver

**Direction**: Optimism (L2) → Ethereum (L1)

This prover enables verification of Ethereum state from Optimism by reading the L1 block hash from the `L1Block` predeploy.

### Configuration

```solidity
contract ChildToParentProver is IStateProver {
    /// @dev L1Block predeploy address (same on all OP Stack chains)
    address public constant l1BlockPredeploy = 0x4200000000000000000000000000000000000015;
    
    /// @dev Storage slot for the L1 block hash
    uint256 public constant l1BlockHashSlot = 2;
    
    /// @dev Optimism chain ID
    uint256 public immutable homeChainId;
}
```

### Important Limitation

The `L1Block` predeploy only stores the **latest** L1 block hash, not historical hashes. This has operational implications:

- Proofs must be generated **just-in-time** rather than pre-cached
- Pre-generated proofs become stale when `L1Block` updates (~every few minutes)
- If `L1Block` updates too frequently, verification calls may need to be retried

### Functions

#### `getTargetStateCommitment`

**Called on**: Optimism (home chain)  
**Returns**: Latest Ethereum block hash

```solidity
function getTargetStateCommitment(bytes calldata) 
    external view returns (bytes32 targetStateCommitment)
{
    return IL1Block(l1BlockPredeploy).hash();
}
```

**Input encoding**: Empty bytes (input is ignored)

#### `verifyTargetStateCommitment`

**Called on**: Remote chains (not Optimism)  
**Returns**: Ethereum block hash (proven from Optimism state)

```solidity
function verifyTargetStateCommitment(bytes32 homeStateCommitment, bytes calldata input)
    external view returns (bytes32 targetStateCommitment)
{
    (
        bytes memory rlpBlockHeader,
        bytes memory accountProof,
        bytes memory storageProof
    ) = abi.decode(input, (bytes, bytes, bytes));

    // Verify proof against L1Block predeploy's storage
    targetStateCommitment = ProverUtils.getSlotFromBlockHeader(
        homeStateCommitment, 
        rlpBlockHeader, 
        l1BlockPredeploy, 
        l1BlockHashSlot,  // slot 2
        accountProof, 
        storageProof
    );
}
```

**Input encoding**:
```solidity
abi.encode(
    bytes rlpBlockHeader,   // RLP-encoded Optimism block header
    bytes accountProof,     // MPT proof for L1Block predeploy
    bytes storageProof      // MPT proof for slot 2
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

**Direction**: Ethereum (L1) → Optimism (L2)

This prover enables verification of Optimism state from Ethereum through the Fault Dispute Game system.

### Configuration

```solidity
contract ParentToChildProver is IStateProver {
    /// @dev Storage slot for anchorGame in AnchorStateRegistry
    uint256 public constant ANCHOR_GAME_SLOT = 3;
    
    /// @dev AnchorStateRegistry address on Ethereum
    address public immutable anchorStateRegistry;
    
    /// @dev Ethereum chain ID
    uint256 public immutable homeChainId;
}
```

### Output Root Structure

The Fault Dispute Game stores an `OutputRootProof`:

```solidity
struct OutputRootProof {
    bytes32 version;                  // Version identifier
    bytes32 stateRoot;                // L2 state root
    bytes32 messagePasserStorageRoot; // L2ToL1MessagePasser storage root
    bytes32 latestBlockhash;          // L2 block hash ← This is what we extract
}

// rootClaim = keccak256(abi.encode(OutputRootProof))
```

### Functions

#### `getTargetStateCommitment`

**Called on**: Ethereum (home chain)  
**Returns**: Optimism block hash

```solidity
function getTargetStateCommitment(bytes calldata input) 
    external view returns (bytes32 targetStateCommitment)
{
    (address gameProxy, OutputRootProof memory rootClaimPreimage) = 
        abi.decode(input, (address, OutputRootProof));

    // Verify game is valid
    require(
        IAnchorStateRegistry(anchorStateRegistry).isGameClaimValid(gameProxy),
        "Invalid game proxy"
    );

    // Verify preimage matches game's root claim
    bytes32 rootClaim = IFaultDisputeGame(gameProxy).rootClaim();
    require(
        rootClaim == keccak256(abi.encode(rootClaimPreimage)),
        "Invalid root claim preimage"
    );

    return rootClaimPreimage.latestBlockhash;
}
```

**Input encoding**:
```solidity
abi.encode(
    address gameProxy,              // FaultDisputeGame address
    OutputRootProof rootClaimPreimage // Preimage of the rootClaim
)
```

#### `verifyTargetStateCommitment`

**Called on**: Remote chains (not Ethereum)  
**Returns**: Optimism block hash (proven from Ethereum state)

This function performs a complex verification:

1. Extract the anchor game address from AnchorStateRegistry storage
2. Verify the game proxy's code hash via account proof
3. Extract the rootClaim from the game proxy bytecode (CWIA pattern)
4. Verify the rootClaim preimage
5. Return the L2 block hash from the preimage

```solidity
function verifyTargetStateCommitment(bytes32 homeStateCommitment, bytes calldata input)
    external view returns (bytes32 targetStateCommitment)
{
    (
        bytes memory rlpBlockHeader,
        bytes memory asrAccountProof,
        bytes memory asrStorageProof,
        bytes memory gameProxyAccountProof,
        bytes memory gameProxyCode,
        OutputRootProof memory rootClaimPreimage
    ) = abi.decode(input, (bytes, bytes, bytes, bytes, bytes, OutputRootProof));

    // Verify block header
    require(homeStateCommitment == keccak256(rlpBlockHeader), "Invalid home block header");
    bytes32 stateRoot = ProverUtils.extractStateRootFromBlockHeader(rlpBlockHeader);

    // Get anchor game address from AnchorStateRegistry
    address anchorGame = address(uint160(uint256(
        ProverUtils.getStorageSlotFromStateRoot(
            stateRoot, asrAccountProof, asrStorageProof, 
            anchorStateRegistry, ANCHOR_GAME_SLOT
        )
    )));

    // Verify game proxy code hash
    (bool exists, bytes memory accountValue) = 
        ProverUtils.getAccountDataFromStateRoot(stateRoot, gameProxyAccountProof, anchorGame);
    require(exists, "Anchor game account does not exist");
    bytes32 codeHash = ProverUtils.extractCodeHashFromAccountData(accountValue);
    require(keccak256(gameProxyCode) == codeHash, "Invalid game proxy code");

    // Extract rootClaim from CWIA proxy bytecode
    bytes32 rootClaim = _getRootClaimFromGameProxyCode(gameProxyCode);

    // Verify preimage
    require(rootClaim == keccak256(abi.encode(rootClaimPreimage)), "Invalid root claim preimage");

    return rootClaimPreimage.latestBlockhash;
}
```

**Input encoding**:
```solidity
abi.encode(
    bytes rlpBlockHeader,           // RLP-encoded Ethereum block header
    bytes asrAccountProof,          // MPT proof for AnchorStateRegistry
    bytes asrStorageProof,          // MPT proof for anchorGame slot
    bytes gameProxyAccountProof,    // MPT proof for game proxy account
    bytes gameProxyCode,            // Full bytecode of game proxy
    OutputRootProof rootClaimPreimage // Preimage of the rootClaim
)
```

#### `verifyStorageSlot`

Same as ChildToParentProver's `verifyStorageSlot`.

### CWIA Proxy Bytecode Layout

The Fault Dispute Game uses a Clone With Immutable Args (CWIA) proxy:

```
┌──────────────┬────────────────────────────────────┐
│    Bytes     │            Description             │
├──────────────┼────────────────────────────────────┤
│ [0, 0x62)    │ Proxy bytecode                     │
│ [0x62, 0x76) │ Game creator address (20 bytes)    │
│ [0x76, 0x96) │ Root claim (32 bytes) ← Extract    │
│ [0x96, 0xB6) │ Parent block hash (32 bytes)       │
│ [0xB6, ...)  │ Extra data                         │
└──────────────┴────────────────────────────────────┘
```

The prover extracts the root claim at offset `0x62 + 20 = 0x76`:

```solidity
function _getRootClaimFromGameProxyCode(bytes memory bytecode) 
    internal pure returns (bytes32 rootClaim) 
{
    return abi.decode(Bytes.slice(bytecode, 0x62 + 20, 0x62 + 52), (bytes32));
}
```

## Usage Example: Verifying Ethereum Message from Optimism

```solidity
// On Optimism, verify a message broadcast on Ethereum

// 1. Route: Optimism → Ethereum (single hop)
address[] memory route = new address[](1);
route[0] = opChildToParentPointer;

// 2. Input for OP C2P (empty - uses latest L1 block)
bytes[] memory scpInputs = new bytes[](1);
scpInputs[0] = bytes("");

// 3. Proof for Broadcaster storage on Ethereum
bytes memory broadcasterProof = abi.encode(
    rlpEthBlockHeader,     // Ethereum block header
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

### L1Block Staleness

Since `L1Block` only stores the latest L1 block hash:
- Proofs must be fresh (generated just before verification)
- If the proof becomes stale, regenerate it with the new L1 block
- Consider implementing retry logic for production systems

### Fault Dispute Games

The ParentToChildProver relies on:
- The `AnchorStateRegistry` tracking valid games
- The game's `isGameClaimValid()` returning true
- The ability to provide the full game proxy bytecode

### Finality

Optimism's finality depends on the mechanism:
- **Fault proofs**: ~7 days challenge period
- **Validity proofs** (future): Near-instant finality after proof verification

## Related Documentation

- [../PROVERS.md](../PROVERS.md) - General prover architecture
- [../RECEIVER.md](../RECEIVER.md) - How routes and verification work
- [Optimism Documentation](https://docs.optimism.io/)
