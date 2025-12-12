// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SparseMerkleProof} from "../../libraries/linea/SparseMerkleProof.sol";
import {ProverUtils} from "../../libraries/ProverUtils.sol";
import {IBlockHashProver} from "../../interfaces/IBlockHashProver.sol";
import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";

interface ILineaRollup {
    /// @notice Returns the state root hash for a given L2 block number
    /// @param blockNumber The L2 block number
    /// @return The state root hash (bytes32(0) if not finalized)
    function stateRootHashes(uint256 blockNumber) external view returns (bytes32);
}

/// @title Linea ParentToChildProver
/// @notice Enables verification of Linea L2 state from Ethereum L1
/// @dev Home chain: L1 (Ethereum). Target chain: L2 (Linea).
///      On L1: getTargetBlockHash reads L2 state root directly from LineaRollup
///      On L2: verifyTargetBlockHash proves L2 state root from L1 LineaRollup storage
///      verifyStorageSlot: Verifies storage against the L2 state root using Sparse Merkle Tree proofs
///
///      Note: Linea uses Sparse Merkle Tree (SMT) with MiMC hashing, NOT Merkle-Patricia Trie (MPT).
///      The state root stored on L1 is the SMT root, which requires linea_getProof for verification.
contract ParentToChildProver is IBlockHashProver {
    /// @dev Address of the LineaRollup contract on L1
    address public immutable lineaRollup;

    /// @dev Storage slot of the stateRootHashes mapping in LineaRollup
    ///      mapping(uint256 blockNumber => bytes32 stateRootHash)
    uint256 public immutable stateRootHashesSlot;

    /// @dev L1 chain ID (home chain)
    uint256 public immutable homeChainId;

    error CallNotOnHomeChain();
    error CallOnHomeChain();
    error TargetStateRootNotFound();
    error InvalidAccountProof();
    error InvalidStorageProof();
    error StorageValueMismatch();

    constructor(address _lineaRollup, uint256 _stateRootHashesSlot, uint256 _homeChainId) {
        lineaRollup = _lineaRollup;
        stateRootHashesSlot = _stateRootHashesSlot;
        homeChainId = _homeChainId;
    }

    /// @notice Verify L2 state root using L1 LineaRollup storage proof
    /// @dev Called on non-home chains (e.g., for two-hop L2→L2 verification)
    ///      Uses standard MPT proof for L1 state (Ethereum uses MPT)
    /// @param homeBlockHash The L1 block hash
    /// @param input ABI encoded (bytes rlpBlockHeader, uint256 l2BlockNumber, bytes accountProof, bytes storageProof)
    /// @return targetBlockHash The L2 state root (named "blockHash" for interface compatibility)
    function verifyTargetBlockHash(bytes32 homeBlockHash, bytes calldata input)
        external
        view
        returns (bytes32 targetBlockHash)
    {
        if (block.chainid == homeChainId) {
            revert CallOnHomeChain();
        }

        // Decode the input - uses MPT proof for L1 (Ethereum)
        (bytes memory rlpBlockHeader, uint256 l2BlockNumber, bytes memory accountProof, bytes memory storageProof) =
            abi.decode(input, (bytes, uint256, bytes, bytes));

        // Calculate storage slot for stateRootHashes[l2BlockNumber]
        uint256 slot = uint256(SlotDerivation.deriveMapping(bytes32(stateRootHashesSlot), l2BlockNumber));

        // Verify proofs and get the L2 state root from L1's LineaRollup
        // Note: L1 (Ethereum) uses MPT, so we use ProverUtils here
        targetBlockHash = ProverUtils.getSlotFromBlockHeader(
            homeBlockHash, rlpBlockHeader, lineaRollup, slot, accountProof, storageProof
        );

        if (targetBlockHash == bytes32(0)) {
            revert TargetStateRootNotFound();
        }
    }

    /// @notice Get L2 state root directly from L1 LineaRollup
    /// @dev Called on home chain (L1)
    /// @param input ABI encoded (uint256 l2BlockNumber)
    /// @return targetBlockHash The L2 state root
    function getTargetBlockHash(bytes calldata input) external view returns (bytes32 targetBlockHash) {
        if (block.chainid != homeChainId) {
            revert CallNotOnHomeChain();
        }

        // Decode the input
        uint256 l2BlockNumber = abi.decode(input, (uint256));

        // Get the state root from LineaRollup
        targetBlockHash = ILineaRollup(lineaRollup).stateRootHashes(l2BlockNumber);

        if (targetBlockHash == bytes32(0)) {
            revert TargetStateRootNotFound();
        }
    }

    /// @notice Verify a storage slot given a target chain state root and a Sparse Merkle Tree proof
    /// @dev Works on any chain. Uses Linea's SMT verification with MiMC hashing.
    ///      IMPORTANT: For Linea, targetBlockHash is the L2 SMT STATE ROOT (not block hash)
    ///      Proofs must be generated using linea_getProof RPC method.
    ///
    ///      Input format from linea_getProof:
    ///      - accountLeafIndex: from accountProof.leafIndex
    ///      - accountProof: from accountProof.proof.proofRelatedNodes (42 elements)
    ///      - accountValue: from accountProof.proof.value (192 bytes)
    ///      - storageLeafIndex: from storageProofs[0].leafIndex
    ///      - storageProof: from storageProofs[0].proof.proofRelatedNodes (42 elements)
    ///      - storageValue: the claimed storage value (32 bytes, to verify)
    ///
    /// @param targetBlockHash The L2 SMT state root (from getTargetBlockHash or verifyTargetBlockHash)
    /// @param input ABI encoded proof data from linea_getProof
    /// @return account The address of the account on L2
    /// @return slot The storage slot
    /// @return value The value at the storage slot
    function verifyStorageSlot(bytes32 targetBlockHash, bytes calldata input)
        external
        pure
        returns (address account, uint256 slot, bytes32 value)
    {
        // Decode the Linea SMT proof format
        uint256 accountLeafIndex;
        bytes[] memory accountProof;
        bytes memory accountValue;
        uint256 storageLeafIndex;
        bytes[] memory storageProof;
        bytes32 claimedStorageValue;

        (account, slot, accountLeafIndex, accountProof, accountValue, storageLeafIndex, storageProof, claimedStorageValue)
        = abi.decode(input, (address, uint256, uint256, bytes[], bytes, uint256, bytes[], bytes32));

        // Step 1: Verify account proof against L2 state root (SMT)
        bool accountValid = SparseMerkleProof.verifyProof(accountProof, accountLeafIndex, targetBlockHash);
        if (!accountValid) {
            revert InvalidAccountProof();
        }

        // Step 2: Extract storage root from the account value (192 bytes)
        SparseMerkleProof.Account memory accountData = SparseMerkleProof.getAccount(accountValue);

        // Step 3: Verify storage proof against account's storage root
        bool storageValid = SparseMerkleProof.verifyProof(storageProof, storageLeafIndex, accountData.storageRoot);
        if (!storageValid) {
            revert InvalidStorageProof();
        }

        // Step 4: Verify the claimed storage value matches the proof
        // Extract the storage leaf from the proof and check hValue matches hash of claimed value
        SparseMerkleProof.Leaf memory storageLeaf =
            SparseMerkleProof.getLeaf(storageProof[storageProof.length - 1]);

        bytes32 expectedHValue = SparseMerkleProof.hashStorageValue(claimedStorageValue);
        if (storageLeaf.hValue != expectedHValue) {
            revert StorageValueMismatch();
        }

        value = claimedStorageValue;
    }

    /// @inheritdoc IBlockHashProver
    function version() external pure returns (uint256) {
        return 2; // Version 2: SMT proof support
    }
}
