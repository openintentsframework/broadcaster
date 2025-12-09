// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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
///      verifyStorageSlot: Verifies storage against the L2 state root
///
///      Note: Unlike other rollups that store blockHash, Linea stores stateRootHash directly.
///      The "targetBlockHash" returned is actually the L2 state root for interface compatibility.
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

    constructor(address _lineaRollup, uint256 _stateRootHashesSlot, uint256 _homeChainId) {
        lineaRollup = _lineaRollup;
        stateRootHashesSlot = _stateRootHashesSlot;
        homeChainId = _homeChainId;
    }

    /// @notice Verify L2 state root using L1 LineaRollup storage proof
    /// @dev Called on non-home chains (e.g., for two-hop L2→L2 verification)
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

        // Decode the input
        (bytes memory rlpBlockHeader, uint256 l2BlockNumber, bytes memory accountProof, bytes memory storageProof) =
            abi.decode(input, (bytes, uint256, bytes, bytes));

        // Calculate storage slot for stateRootHashes[l2BlockNumber]
        uint256 slot = uint256(SlotDerivation.deriveMapping(bytes32(stateRootHashesSlot), l2BlockNumber));

        // Verify proofs and get the L2 state root from L1's LineaRollup
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

    /// @notice Verify a storage slot given a target chain state root and a proof
    /// @dev Works on any chain.
    ///      IMPORTANT: For Linea, targetBlockHash is actually the L2 STATE ROOT (not block hash)
    ///      because LineaRollup stores stateRootHashes, not blockHashes.
    ///      This function verifies the storage proof directly against the state root,
    ///      bypassing block header verification.
    /// @param targetBlockHash The L2 state root (from getTargetBlockHash or verifyTargetBlockHash)
    /// @param input ABI encoded (address account, uint256 slot, bytes accountProof, bytes storageProof)
    ///              Note: No rlpBlockHeader needed since we use state root directly
    /// @return account The address of the account on L2
    /// @return slot The storage slot
    /// @return value The value at the storage slot
    function verifyStorageSlot(bytes32 targetBlockHash, bytes calldata input)
        external
        pure
        returns (address account, uint256 slot, bytes32 value)
    {
        // Decode the input - no block header needed for Linea
        // since we already have the state root directly from LineaRollup
        bytes memory accountProof;
        bytes memory storageProof;
        (account, slot, accountProof, storageProof) =
            abi.decode(input, (address, uint256, bytes, bytes));

        // For Linea, targetBlockHash IS the L2 state root
        // We verify proofs directly against it, skipping block header verification
        value = ProverUtils.getStorageSlotFromStateRoot(
            targetBlockHash, // This is actually the L2 state root
            accountProof,
            storageProof,
            account,
            slot
        );
    }

    /// @inheritdoc IBlockHashProver
    function version() external pure returns (uint256) {
        return 1;
    }
}
