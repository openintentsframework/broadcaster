# Documentation

## ERC-7888 Crosschain Broadcaster

This repository implements [ERC-7888](https://eips.ethereum.org/EIPS/eip-7888), a protocol for trustless cross-chain message verification using cryptographic storage proofs.

### Documentation Index

| Document | Description |
|----------|-------------|
| [ERC7888.md](ERC7888.md) | Complete specification overview, interfaces, and protocol mechanics |
| [PROVERS.md](PROVERS.md) | Chain-specific StateProver implementations and how to add new ones |
| [TUTORIAL.md](TUTORIAL.md) | Step-by-step guide to broadcasting and verifying messages |

### Quick Links

- **Specification**: [EIP-7888](https://eips.ethereum.org/EIPS/eip-7888)
- **Discussion**: [Ethereum Magicians](https://ethereum-magicians.org/t/new-erc-cross-chain-broadcaster/22927)

### Getting Started

1. Read [ERC7888.md](ERC7888.md) for protocol fundamentals
2. Follow [TUTORIAL.md](TUTORIAL.md) to implement your first cross-chain message
3. Reference [PROVERS.md](PROVERS.md) for chain-specific details

### Supported Chains

| Chain | ChildToParent | ParentToChild |
|-------|---------------|---------------|
| Arbitrum | ✅ | ✅ |
| Optimism | ✅ | ✅ |
| Linea | ✅ | ✅ |
| Scroll | ✅ | ✅ |
| zkSync Era | ✅ | ✅ |
| Taiko | ✅ | ✅ |

### Core Contracts

```
src/contracts/
├── Broadcaster.sol          # Message broadcasting
├── Receiver.sol             # Message verification
├── StateProverPointer.sol   # Upgradeable prover reference
├── interfaces/
│   ├── IBroadcaster.sol
│   ├── IReceiver.sol
│   ├── IStateProver.sol
│   └── IStateProverPointer.sol
└── provers/
    ├── arbitrum/
    ├── optimism/
    ├── linea/
    ├── scroll/
    ├── zksync/
    └── taiko/
```
