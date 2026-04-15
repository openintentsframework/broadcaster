# ERC-7888 Crosschain Broadcaster Documentation

This repository implements [ERC-7888](https://eips.ethereum.org/EIPS/eip-7888), a protocol for trustless cross-chain message verification using cryptographic storage proofs.

## Overview

ERC-7888 enables any chain to verify messages broadcast on any other chain that shares a common ancestor, creating a foundation for cross-chain interoperability without trusted intermediaries.

### Core Components

| Component | Description | Documentation |
|-----------|-------------|---------------|
| **Broadcaster** | Stores messages in deterministic storage slots | [BROADCASTER.md](BROADCASTER.md) |
| **Receiver** | Verifies messages from remote chains using storage proofs | [RECEIVER.md](RECEIVER.md) |
| **StateProver** | Chain-specific logic for verifying state commitments | [PROVERS.md](PROVERS.md) |
| **StateProverPointer** | Upgradeable pointer to StateProver implementations | [PROVERS.md](PROVERS.md) |

## Documentation Index

### Core Documentation

| Document | Description |
|----------|-------------|
| [BROADCASTER.md](BROADCASTER.md) | How to broadcast messages, storage layout, ZkSync broadcaster |
| [RECEIVER.md](RECEIVER.md) | Message verification, routes, prover copies, usage examples |
| [PROVERS.md](PROVERS.md) | StateProver architecture, pointers, copies mechanism |

### Chain-Specific Provers

| Chain | Documentation | State Commitment Type |
|-------|--------------|----------------------|
| Arbitrum | [provers/ARBITRUM.md](provers/ARBITRUM.md) | Block hash via Outbox |
| Optimism | [provers/OPTIMISM.md](provers/OPTIMISM.md) | Block hash via L1Block/FaultDisputeGame |
| Linea | [provers/LINEA.md](provers/LINEA.md) | SMT state root (MiMC) |
| Scroll | [provers/SCROLL.md](provers/SCROLL.md) | State root (direct) |
| Taiko | [provers/TAIKO.md](provers/TAIKO.md) | Block hash via SignalService |
| ZkSync | [provers/ZKSYNC.md](provers/ZKSYNC.md) | L2 logs root hash |

## Quick Start

### 1. Broadcasting a Message

```solidity
// On source chain
IBroadcaster broadcaster = IBroadcaster(BROADCASTER_ADDRESS);
bytes32 message = keccak256(abi.encode(yourData));
broadcaster.broadcastMessage(message);
```

### 2. Verifying a Message

```solidity
// On destination chain
IReceiver receiver = IReceiver(RECEIVER_ADDRESS);

IReceiver.RemoteReadArgs memory args = IReceiver.RemoteReadArgs({
    route: route,           // StateProverPointer addresses
    scpInputs: scpInputs,   // Inputs for each prover
    proof: storageProof     // Final storage proof
});

(bytes32 broadcasterId, uint256 timestamp) = receiver.verifyBroadcastMessage(
    args,
    message,
    publisher
);
```

See [RECEIVER.md](RECEIVER.md) for detailed examples.

## Supported Chains

| Chain | ChildToParent | ParentToChild | Notes |
|-------|:-------------:|:-------------:|-------|
| Arbitrum | ✅ | ✅ | Uses block hash buffer on L2, Outbox on L1 |
| Optimism | ✅ | ✅ | L1Block predeploy, FaultDisputeGame proofs |
| Linea | ✅ | ✅ | Sparse Merkle Tree with MiMC hashing |
| Scroll | ✅ | ✅ | Direct state roots (simplified proofs) |
| Taiko | ✅ | ✅ | SignalService checkpoints on both chains |
| ZkSync ERA | ✅ | ✅ | L2 logs Merkle proofs, custom Broadcaster |

## Contract Structure

```
src/contracts/
├── Broadcaster.sol          # Standard message broadcasting
├── ZkSyncBroadcaster.sol    # ZkSync-specific broadcaster
├── Receiver.sol             # Message verification
├── StateProverPointer.sol   # Upgradeable prover reference
├── interfaces/
│   ├── IBroadcaster.sol
│   ├── IReceiver.sol
│   ├── IStateProver.sol
│   └── IStateProverPointer.sol
├── libraries/
│   ├── ProverUtils.sol      # MPT verification utilities
│   └── linea/
│       ├── Mimc.sol         # MiMC hash function
│       └── SparseMerkleProof.sol
└── provers/
    ├── arbitrum/
    │   ├── ChildToParentProver.sol
    │   └── ParentToChildProver.sol
    ├── optimism/
    │   ├── ChildToParentProver.sol
    │   └── ParentToChildProver.sol
    ├── linea/
    │   ├── ChildToParentProver.sol
    │   └── ParentToChildProver.sol
    ├── scroll/
    │   ├── ChildToParentProver.sol
    │   └── ParentToChildProver.sol
    ├── taiko/
    │   ├── ChildToParentProver.sol
    │   └── ParentToChildProver.sol
    └── zksync/
        ├── ChildToParentProver.sol
        ├── ParentToChildProver.sol
        └── libraries/
            ├── Merkle.sol
            └── MessageHashing.sol
```

## External Links

- **EIP Specification**: [EIP-7888](https://eips.ethereum.org/EIPS/eip-7888)
- **Discussion**: [Ethereum Magicians Forum](https://ethereum-magicians.org/t/new-erc-cross-chain-broadcaster/22927)

## Security Considerations

1. **Finalization**: Only finalized blocks can be proven. Propagation time equals the sum of finalization times along the route.

2. **Route Trust**: The route determines which StateProverPointers (and their owners) are trusted. Only use routes through trusted pointers.

3. **Prover Upgrades**: StateProverPointer owners can update prover implementations. Ensure pointers are owned by appropriate parties.

4. **ZkSync**: Must use `ZkSyncBroadcaster` instead of standard `Broadcaster` due to different proof mechanism.

See individual documentation files for chain-specific security considerations.
