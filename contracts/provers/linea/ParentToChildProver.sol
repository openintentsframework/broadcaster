// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ProverUtils} from "../../libraries/ProverUtils.sol";
import {IBlockHashProver} from "../../interfaces/IBlockHashProver.sol";

/// @notice Interface for Linea's L1 rollup contract that manages state root finalization.
/// @dev    Linea uses a zkEVM architecture where L2 state roots are submitted to L1 along with
///         validity proofs. The L1 contract verifies these proofs and stores finalized state roots.
///
///         References:
///         - Linea zkEVM finalization: https://docs.linea.build/architecture/overview/transaction-lifecycle
///         - Similar to zkSync Era's Validator contract
///         - Different from Optimistic Rollups (Arbitrum/Optimism) which use fraud proofs
interface ILineaRollup {
    /// @notice Returns the finalized L2 state root for a given L2 block number
    /// @dev    State roots are finalized after the zkEVM proof has been verified on L1
    ///         Only finalized blocks have accessible state roots
    /// @param  blockNumber The L2 block number
    /// @return The finalized state root for that block, or bytes32(0) if not finalized
    function stateRootHashes(uint256 blockNumber) external view returns (bytes32);
}

/// @notice Linea implementation of a parent to child IBlockHashProver.
/// @dev    This prover enables L1 (Ethereum) contracts to verify L2 (Linea) state.
///
///         Architecture:
///         Linea is a zkEVM rollup that uses zero-knowledge proofs to ensure validity:
///         1. L2 blocks are executed by the Linea sequencer
///         2. The zkEVM prover generates a validity proof for a batch of L2 blocks
///         3. This proof and the resulting L2 state root are submitted to the L1 rollup contract
///         4. The L1 contract verifies the zkEVM proof on-chain
///         5. Once verified, the L2 state root is finalized and can be used for state proofs
///
///         Key differences from Optimistic Rollups:
///         - Linea uses validity proofs (zkSNARKs) instead of fraud proofs
///         - State roots are immediately final once the zkEVM proof is verified (no challenge period)
///         - No dispute game or interactive proving needed
///
///         verifyTargetBlockHash: Verifies an L2 state root using a storage proof against the rollup contract
///         getTargetBlockHash: Directly reads a finalized L2 state root from the rollup contract
///         verifyStorageSlot: Verifies any storage slot on L2 using standard Ethereum Merkle Patricia Trie proofs
///
///         References:
///         - Linea zkEVM architecture: https://docs.linea.build/architecture/overview
///         - zkEVM finalization process: https://docs.linea.build/architecture/overview/transaction-lifecycle
///         - Similar to zkSync Era's state proof system
///         - Ethereum state proof verification: https://ethereum.org/en/developers/docs/data-structures-and-encoding/patricia-merkle-trie/
contract ParentToChildProver is IBlockHashProver {
    /// @dev Address of the Linea rollup contract on L1 (Ethereum mainnet).
    ///      This contract manages L2 state root finalization and zkEVM proof verification.
    ///
    ///      The rollup contract is deployed by the Linea team and is the source of truth
    ///      for finalized L2 state on L1.
    ///
    ///      Known addresses:
    ///      - Mainnet: Should be verified against official Linea documentation
    ///      - Testnet: Should be verified against official Linea documentation
    ///
    ///      References:
    ///      - Linea contract deployments: https://docs.linea.build/get-started/build/contracts
    ///      - https://etherscan.io/address/0xd19d4B5d358258f05D7B411E21A1460D11B0876F
    address public immutable lineaRollup;

    /// @dev Storage slot where state root hashes are stored in the Linea rollup contract.
    ///      This is typically a mapping(uint256 => bytes32) where the key is the L2 block number.
    ///
    ///      The actual slot should be verified against Linea's rollup contract implementation.
    ///      For a mapping at slot N, the storage location for key K is keccak256(K || N).
    uint256 public immutable stateRootHashesSlot;

    /// @notice Construct a new ParentToChildProver
    /// @param  _lineaRollup The address of the Linea rollup contract on L1
    /// @param  _stateRootHashesSlot The storage slot for the stateRootHashes mapping in the rollup contract
    constructor(address _lineaRollup, uint256 _stateRootHashesSlot) {
        lineaRollup = _lineaRollup;
        stateRootHashesSlot = _stateRootHashesSlot;
    }

    /// @notice Verify an L2 (child chain) state root given an L1 (home chain) block hash and a proof.
    /// @dev    This function verifies that a specific L2 state root was finalized on L1 by:
    ///         1. Verifying the provided L1 block header matches the homeBlockHash
    ///         2. Extracting the L1 state root from the block header
    ///         3. Using Merkle proofs to verify the Linea rollup contract's storage
    ///         4. Returning the L2 state root for the specified block number
    ///
    ///         The L2 state root can then be used to prove any L2 account state or storage
    ///         at that block using verifyStorageSlot.
    ///
    ///         Note: Unlike Optimistic Rollups, Linea's state roots are final immediately after
    ///         the zkEVM proof is verified. There is no challenge period.
    ///
    /// @param  homeBlockHash The block hash of the home chain (Ethereum L1).
    /// @param  input ABI encoded (bytes blockHeader, uint256 l2BlockNumber, bytes accountProof, bytes storageProof)
    ///         - blockHeader: RLP-encoded L1 block header
    ///         - l2BlockNumber: The L2 block number whose state root we want to verify
    ///         - accountProof: Merkle proof for the Linea rollup contract account in the L1 state trie
    ///         - storageProof: Merkle proof for the stateRootHashes mapping slot for the given L2 block number
    /// @return targetBlockHash The L2 state root hash for the specified L2 block number
    function verifyTargetBlockHash(bytes32 homeBlockHash, bytes calldata input)
        external
        view
        returns (bytes32 targetBlockHash)
    {
        // decode the input
        (bytes memory rlpBlockHeader, uint256 l2BlockNumber, bytes memory accountProof, bytes memory storageProof) =
            abi.decode(input, (bytes, uint256, bytes, bytes));

        // Calculate the storage slot for stateRootHashes[l2BlockNumber]
        // For a mapping(uint256 => bytes32) at slot stateRootHashesSlot,
        // the storage location for key l2BlockNumber is keccak256(l2BlockNumber || stateRootHashesSlot)
        //
        // Note: Using SlotDerivation library for this calculation
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/SlotDerivation.sol
        bytes32 slot = keccak256(abi.encode(l2BlockNumber, stateRootHashesSlot));

        // verify proofs and get the L2 state root
        targetBlockHash = ProverUtils.getSlotFromBlockHeader(
            homeBlockHash, rlpBlockHeader, lineaRollup, uint256(slot), accountProof, storageProof
        );
    }

    /// @notice Get a finalized L2 (child chain) state root for a given L2 block number.
    /// @dev    This directly reads from the Linea rollup contract on L1 to get a finalized
    ///         L2 state root. The state root is only available if the block has been finalized
    ///         through the zkEVM proof verification process.
    ///
    ///         If the block has not been finalized yet, this will return bytes32(0).
    ///
    ///         Finalization process:
    ///         1. Linea sequencer executes L2 blocks
    ///         2. zkEVM prover generates validity proof for a batch of blocks
    ///         3. Proof and state roots are submitted to L1 rollup contract
    ///         4. L1 contract verifies the zkEVM proof
    ///         5. State roots become immediately available for proofs (no challenge period)
    ///
    ///         References:
    ///         - Linea finalization: https://docs.linea.build/architecture/overview/transaction-lifecycle#finalization
    ///
    /// @param  input ABI encoded (uint256 l2BlockNumber)
    /// @return targetBlockHash The finalized L2 state root hash for the given block number
    function getTargetBlockHash(bytes calldata input) external view returns (bytes32 targetBlockHash) {
        // decode the input
        uint256 l2BlockNumber = abi.decode(input, (uint256));

        // get the finalized state root from the rollup contract
        targetBlockHash = ILineaRollup(lineaRollup).stateRootHashes(l2BlockNumber);
    }

    /// @notice Verify a storage slot on L2 (target chain) given an L2 state root and a proof.
    /// @dev    This function verifies L2 storage using standard Ethereum Merkle Patricia Trie proofs:
    ///         1. Verifies the provided L2 block header matches the targetBlockHash (state root)
    ///         2. Uses the account proof to verify the account exists in the L2 state trie
    ///         3. Uses the storage proof to verify the storage slot value in the account's storage trie
    ///
    ///         This follows the standard Ethereum state proof format. Linea's zkEVM maintains
    ///         EVM-equivalent state structure, so standard Ethereum proof verification works.
    ///
    ///         References:
    ///         - Ethereum proof format: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_getproof
    ///         - Linea EVM equivalence: https://docs.linea.build/architecture/overview
    ///         - MPT verification: https://github.com/ethereum-optimism/optimism/tree/develop/packages/contracts-bedrock/src/libraries/trie
    ///
    /// @param  targetBlockHash The L2 state root (obtained from verifyTargetBlockHash or getTargetBlockHash)
    /// @param  input ABI encoded (bytes blockHeader, address account, uint256 slot, bytes accountProof, bytes storageProof)
    /// @return account The address of the account on the target chain
    /// @return slot The storage slot of the account on the target chain
    /// @return value The value of the storage slot
    function verifyStorageSlot(bytes32 targetBlockHash, bytes calldata input)
        external
        pure
        returns (address account, uint256 slot, bytes32 value)
    {
        // decode the input
        bytes memory rlpBlockHeader;
        bytes memory accountProof;
        bytes memory storageProof;
        (rlpBlockHeader, account, slot, accountProof, storageProof) =
            abi.decode(input, (bytes, address, uint256, bytes, bytes));

        // verify proofs and get the value
        // Linea maintains EVM-equivalent state structure, so standard MPT proofs work
        value = ProverUtils.getSlotFromBlockHeader(
            targetBlockHash, rlpBlockHeader, account, slot, accountProof, storageProof
        );
    }

    /// @inheritdoc IBlockHashProver
    function version() external pure returns (uint256) {
        return 1;
    }
}
