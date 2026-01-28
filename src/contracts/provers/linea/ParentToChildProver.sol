// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SparseMerkleProof} from "../../libraries/linea/SparseMerkleProof.sol";
import {ProverUtils} from "../../libraries/ProverUtils.sol";
import {IStateProver} from "../../interfaces/IStateProver.sol";
import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";
import {ZkEvmV2} from "@linea-contracts/rollup/ZkEvmV2.sol";

/// @title Linea ParentToChildProver
/// @notice Enables verification of Linea L2 state from Ethereum L1
/// @dev Home chain: L1 (Ethereum). Target chain: L2 (Linea).
///      On L1: getTargetStateCommitment reads L2 state root directly from LineaRollup
///      On L2: verifyTargetStateCommitment proves L2 state root from L1 LineaRollup storage
///      verifyStorageSlot: Verifies storage against the L2 state root using Sparse Merkle Tree proofs
///
///      Note: Linea uses Sparse Merkle Tree (SMT) with MiMC hashing, NOT Merkle-Patricia Trie (MPT).
///      The state root stored on L1 is the SMT root, which requires linea_getProof for verification.
contract ParentToChildProver is IStateProver {
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
    error AccountKeyMismatch();
    error AccountValueMismatch();
    error StorageKeyMismatch();

    constructor(address _lineaRollup, uint256 _stateRootHashesSlot, uint256 _homeChainId) {
        lineaRollup = _lineaRollup;
        stateRootHashesSlot = _stateRootHashesSlot;
        homeChainId = _homeChainId;
    }

    /// @notice Verify L2 state root using L1 LineaRollup storage proof
    /// @dev Called on non-home chains (e.g., for two-hop L2→L2 verification)
    ///      Uses standard MPT proof for L1 state (Ethereum uses MPT)
    /// @param homeStateCommitment The L1 block hash
    /// @param input ABI encoded (bytes rlpBlockHeader, uint256 l2BlockNumber, bytes accountProof, bytes storageProof)
    /// @return targetStateCommitment The L2 state root
    function verifyTargetStateCommitment(bytes32 homeStateCommitment, bytes calldata input)
        external
        view
        returns (bytes32 targetStateCommitment)
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
        targetStateCommitment = ProverUtils.getSlotFromBlockHeader(
            homeStateCommitment, rlpBlockHeader, lineaRollup, slot, accountProof, storageProof
        );

        if (targetStateCommitment == bytes32(0)) {
            revert TargetStateRootNotFound();
        }
    }

    /// @notice Get L2 state root directly from L1 LineaRollup
    /// @dev Called on home chain (L1)
    /// @param input ABI encoded (uint256 l2BlockNumber)
    /// @return targetStateCommitment The L2 state root
    function getTargetStateCommitment(bytes calldata input) external view returns (bytes32 targetStateCommitment) {
        if (block.chainid != homeChainId) {
            revert CallNotOnHomeChain();
        }

        // Decode the input
        uint256 l2BlockNumber = abi.decode(input, (uint256));

        // Get the state root from LineaRollup
        targetStateCommitment = ZkEvmV2(lineaRollup).stateRootHashes(l2BlockNumber);

        if (targetStateCommitment == bytes32(0)) {
            revert TargetStateRootNotFound();
        }
    }

    /// @notice Verify a storage slot given a target chain state root and a Sparse Merkle Tree proof
    /// @dev Works on any chain. Uses Linea's SMT verification with MiMC hashing.
    ///      IMPORTANT: For Linea, targetStateCommitment is the L2 SMT STATE ROOT (not block hash)
    ///      Proofs must be generated using linea_getProof RPC method.
    ///
    ///      Input format from linea_getProof:
    ///      - accountLeafIndex: from accountProof.leafIndex
    ///      - accountProof: from accountProof.proof.proofRelatedNodes (42 elements)
    ///      - accountValue: from accountProof.proof.value (192 bytes)
    ///      - storageLeafIndex: from storageProofs[0].leafIndex
    ///      - proof: from storageProofs[0].proof.proofRelatedNodes (42 elements)
    ///      - storageValue: the claimed storage value (32 bytes, to verify)
    ///
    ///      Security: This function verifies that:
    ///      1. The account proof is valid against the state root
    ///      2. The account proof corresponds to the claimed account address (hKey check)
    ///      3. The account value matches the proven account leaf (hValue check)
    ///      4. The storage proof is valid against the account's storage root
    ///      5. The storage proof corresponds to the claimed slot (hKey check)
    ///      6. The storage value matches the proof's hValue
    ///
    /// @param targetStateCommitment The L2 SMT state root (from getTargetStateCommitment or verifyTargetStateCommitment)
    /// @param input ABI encoded proof data from linea_getProof
    /// @return account The address of the account on L2
    /// @return slot The storage slot
    /// @return value The value at the storage slot
    function verifyStorageSlot(bytes32 targetStateCommitment, bytes calldata input)
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

        (
            account,
            slot,
            accountLeafIndex,
            accountProof,
            accountValue,
            storageLeafIndex,
            storageProof,
            claimedStorageValue
        ) = abi.decode(input, (address, uint256, uint256, bytes[], bytes, uint256, bytes[], bytes32));

        // Step 1: Verify account proof against L2 state root (SMT)
        bool accountValid = SparseMerkleProof.verifyProof(accountProof, accountLeafIndex, targetStateCommitment);
        if (!accountValid) {
            revert InvalidAccountProof();
        }

        // Step 2: Verify the account proof corresponds to the claimed account address
        // Extract the account leaf and verify its hKey matches the MiMC hash of the claimed address
        SparseMerkleProof.Leaf memory accountLeaf = SparseMerkleProof.getLeaf(accountProof[accountProof.length - 1]);
        bytes32 expectedAccountHKey = SparseMerkleProof.hashAccountKey(account);
        if (accountLeaf.hKey != expectedAccountHKey) {
            revert AccountKeyMismatch();
        }

        // Step 3: Verify the account value matches the proven account leaf
        // This binds the storageRoot to the proven account - without this check,
        // an attacker could supply an arbitrary accountValue with a fake storageRoot
        bytes32 expectedAccountHValue = SparseMerkleProof.hashAccountValue(accountValue);
        if (accountLeaf.hValue != expectedAccountHValue) {
            revert AccountValueMismatch();
        }

        // Step 4: Extract storage root from the account value (192 bytes)
        // Now we can safely use the storageRoot since we verified accountValue matches the proof
        SparseMerkleProof.Account memory accountData = SparseMerkleProof.getAccount(accountValue);

        // Step 5: Verify storage proof against account's storage root
        bool storageValid = SparseMerkleProof.verifyProof(storageProof, storageLeafIndex, accountData.storageRoot);
        if (!storageValid) {
            revert InvalidStorageProof();
        }

        // Step 6: Verify the storage proof corresponds to the claimed slot
        // Extract the storage leaf and verify its hKey matches the MiMC hash of the claimed slot
        SparseMerkleProof.Leaf memory storageLeaf = SparseMerkleProof.getLeaf(storageProof[storageProof.length - 1]);
        bytes32 expectedStorageHKey = SparseMerkleProof.hashStorageKey(bytes32(slot));
        if (storageLeaf.hKey != expectedStorageHKey) {
            revert StorageKeyMismatch();
        }

        // Step 7: Verify the claimed storage value matches the proof's hValue
        bytes32 expectedHValue = SparseMerkleProof.hashStorageValue(claimedStorageValue);
        if (storageLeaf.hValue != expectedHValue) {
            revert StorageValueMismatch();
        }

        value = claimedStorageValue;
    }

    /// @inheritdoc IStateProver
    function version() external pure returns (uint256) {
        return 1;
    }
}
