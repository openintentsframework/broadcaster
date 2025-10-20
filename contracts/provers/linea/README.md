# Linea Prover Implementation

This directory contains the prover implementation for the Linea network, following the same patterns as the Arbitrum and Optimism provers.

## Overview

Linea is a zkEVM (zero-knowledge Ethereum Virtual Machine) rollup that uses zero-knowledge proofs to ensure the validity of off-chain computations. Unlike Optimistic Rollups (like Arbitrum and Optimism) that use fraud proofs, Linea uses validity proofs which provide immediate finality once verified.

**Important**: Linea has architectural differences from OP Stack chains that affect cross-chain state verification patterns.

## Contracts

### ParentToChildProver.sol

**Purpose**: Enables L1 (Ethereum) contracts to verify L2 (Linea) state.

**Key Features**:
- Reads finalized L2 state roots from the Linea rollup contract on L1
- State roots are immediately final after zkEVM proof verification (no challenge period)
- Verifies L2 storage using standard Ethereum Merkle Patricia Trie proofs

**Architecture**:
```
L1 (Ethereum)                    L2 (Linea)
     │                                │
     │  LineaRollup Contract           │
     │  stores finalized                │
     │  L2 state roots                  │
     │      │                           │
     │      ├─ zkEVM Proof ◄─────────┤
     │      │  Verification             │
     │      │                           │
     │      ├─ State Root               │
     │      │  Finalization             │
     │      │                           │
     ├─ ParentToChildProver            │
     │  reads finalized                 │
     │  state roots                     │
     │                                  │
     │◄─────── MPT Proof ──────────────┤
     │   (verifies L2 storage)          │
```

**Methods**:
- `verifyTargetBlockHash()`: Verifies L2 state root using storage proofs against the rollup contract
- `getTargetBlockHash()`: Directly reads finalized L2 state roots from the rollup contract
- `verifyStorageSlot()`: Verifies any L2 storage slot using Merkle proofs

**Constructor Parameters**:
- `_lineaRollup`: Address of the Linea rollup contract on L1
- `_stateRootHashesSlot`: Storage slot for the stateRootHashes mapping

**References**:
- Linea zkEVM finalization: https://docs.linea.build/architecture/overview/transaction-lifecycle
- zkSync Era (similar zkEVM): https://docs.zksync.io/
- Ethereum state proofs: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_getproof

## ⚠️ Linea Compatibility Considerations

### What Works ✅
- **L1→L2 State Verification**: ParentToChildProver correctly verifies Linea L2 state from Ethereum L1
- **Message Broadcasting**: Standard broadcaster functionality works on both chains
- **Cross-chain Communication**: Can verify L2 messages from L1 using the prover

### What Doesn't Work ❌
- **L2→L1 State Verification**: Linea L2 does **not** have an L1StateInfo system contract like OP Stack chains
- **Direct L1 State Access**: L2 contracts cannot directly verify L1 state without external oracles

### Recommended Usage Patterns

#### For L1→L2 Verification (✅ Recommended)
```solidity
// Deploy on L1 (Ethereum)
ParentToChildProver prover = new ParentToChildProver(
    0xd19d4B5d358258f05D7B411E21A1460D11B0876F, // Linea rollup contract
    0 // stateRootHashes storage slot (verify this)
);

// Use to verify Linea L2 state from L1
bytes32 l2StateRoot = prover.getTargetBlockHash(l2BlockNumber);
```

#### For L2→L1 Verification (⚠️ Requires Alternative Approaches)
If you need to verify L1 state from L2, consider:

1. **Message Passing**: Use Linea's native message service
2. **Oracle Pattern**: Deploy an oracle that posts L1 state to L2
3. **Off-chain Verification**: Handle verification off-chain or through trusted relayers

## Key Differences from Optimistic Rollups

### Linea (zkEVM with Validity Proofs)
- ✅ **Immediate Finality**: State roots are final once the zkEVM proof is verified
- ✅ **No Challenge Period**: No need to wait 7 days like Optimistic Rollups
- ✅ **Validity Proofs**: zkSNARKs prove computation is correct
- ⚠️ **Proof Generation**: Requires complex zero-knowledge proof generation (computationally intensive)

### Arbitrum/Optimism (Optimistic Rollups with Fraud Proofs)
- ⏳ **Challenge Period**: 7-day waiting period for withdrawals
- 🔄 **Fraud Proofs**: Dispute resolution through interactive proving or fault proofs
- ⚡ **Fast Proof Generation**: Simpler to generate proofs
- ❌ **Delayed Finality**: Must wait for challenge period to expire

### System Contract Address
The `ChildToParentProver` uses a predefined address for the L1StateInfo system contract:
```solidity
address public constant l1StateInfoContract = 0x0000000000000000000000000000000000005001;
```

**Note**: This address is based on common zkEVM patterns and should be verified against Linea's official documentation for mainnet/testnet deployments.

### Storage Slot Assumptions
Both contracts make assumptions about storage slot layouts:
- `ChildToParentProver`: Assumes L1 state root is at slot 0
- `ParentToChildProver`: Takes storage slot as constructor parameter (configurable)

These should be verified against actual contract deployments.

### EVM Equivalence
Linea maintains EVM equivalence, which means:
- Standard Ethereum Merkle Patricia Trie proofs work
- Account and storage structures are identical to Ethereum
- RLP encoding follows Ethereum standards

## Deployment Considerations

### On L1 (Ethereum) ✅ **Recommended**
Deploy `ParentToChildProver`:
```solidity
address lineaRollupAddress = 0xd19d4B5d358258f05D7B411E21A1460D11B0876F; // Linea rollup contract on L1
uint256 stateRootSlot = 0; // Storage slot for stateRootHashes mapping
ParentToChildProver parentProver = new ParentToChildProver(lineaRollupAddress, stateRootSlot);
```

**Important**: Verify the correct addresses and storage slots from Linea's official documentation before mainnet deployment.

### On L2 (Linea) ❌ **Not Recommended**
The `ChildToParentProver` has been removed because Linea L2 does not provide access to L1 state roots through a system contract like OP Stack chains do.

If you need to verify L1 state from L2, use alternative approaches:
1. **Oracle contracts** that fetch and post L1 state to L2
2. **Linea's message service** for cross-chain communication
3. **Off-chain verification** through trusted relayers

## Security Considerations

1. **State Root Finality**: Always ensure state roots are finalized before relying on them
2. **Proof Verification**: The ProverUtils library handles Merkle proof verification - ensure it's well-audited
3. **Rollup Contract Trust**: ParentToChildProver trusts the Linea rollup contract for state root accuracy
4. **Storage Slot Verification**: Verify storage slot mappings match actual contract implementations
5. **zkEVM Proof Verification**: Trust in the Linea rollup contract's zkEVM proof verification

## Future Enhancements

Potential improvements for production use:

1. **State Root Caching**: Implement caching mechanisms to reduce gas costs for repeated queries
2. **Batch Verification**: Support for verifying multiple storage slots in a single transaction
3. **Event-based Updates**: Listen for state root updates and cache them efficiently
4. **Enhanced Error Handling**: Better handling of edge cases and network-specific errors
5. **Cross-chain Message Integration**: Integration with Linea's message service for enhanced functionality

## References

### Linea Documentation
- Main Documentation: https://docs.linea.build/
- Architecture Overview: https://docs.linea.build/architecture/overview
- Transaction Lifecycle: https://docs.linea.build/architecture/overview/transaction-lifecycle
- Deployed Contracts: https://docs.linea.build/get-started/build/contracts

### Ethereum Standards
- State Proofs: https://ethereum.org/en/developers/docs/data-structures-and-encoding/patricia-merkle-trie/
- JSON-RPC eth_getProof: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_getproof
- Block Structure: https://ethereum.org/en/developers/docs/blocks/

### zkEVM Resources
- zkEVM Whitepaper: Various zkEVM implementations
- Linea Prover Architecture: https://docs.linea.build/technology/prover/proving

### Similar Implementations
- Arbitrum Prover: `../arbitrum/`
- Optimism Prover: `../optimism/`
- OP Stack L1Block Predeploy: https://github.com/ethereum-optimism/optimism/blob/develop/specs/predeploys.md

## License

MIT License - See LICENSE file for details.

## Contact & Support

For issues or questions:
- Linea Discord: https://discord.gg/linea
- Linea GitHub: https://github.com/Consensys/linea-contracts
- Documentation: https://docs.linea.build/
