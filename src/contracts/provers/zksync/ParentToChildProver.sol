// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ProverUtils} from "../../libraries/ProverUtils.sol";
import {IBlockHashProver} from "../../interfaces/IBlockHashProver.sol";
//import {SlotDerivation} from "openzeppelin/utils/SlotDerivation.sol";

import {SparseMerkleTree, TreeEntry} from "./helpers/SparseMerkleTree.sol";

/// @notice Interface for the zkSync's contract
interface IZkSyncDiamond {
    /// @notice Returns the hash of the stored batch
    function storedBatchHash(uint256) external view returns (bytes32);
}

/// @notice Arbitrum implementation of a child to parent IBlockHashProver.
/// @dev    verifyTargetBlockHash and getTargetBlockHash get block hashes from the child chain's Outbox contract.
///         verifyStorageSlot is implemented to work against any Arbitrum child chain with a standard Ethereum block header and state trie.
contract ParentToChildProver is IBlockHashProver {

    IZkSyncDiamond immutable public zksyncDiamondAddress;
    SparseMerkleTree public smt;

    error InvalidBatchHash();


    /// @notice Metadata of the batch provided by the offchain resolver
    /// @dev batchHash is omitted because it will be calculated from the proof
    struct BatchMetadata {
        uint64 batchNumber;
        uint64 indexRepeatedStorageChanges;
        uint256 numberOfLayer1Txs;
        bytes32 priorityOperationsHash;
        bytes32 l2LogsTreeRoot;
        uint256 timestamp;
        bytes32 commitment;
    }

    /// @notice Storage proof that proves a storage key-value pair is included in the batch
    struct StorageProof {
        // Metadata of the batch
        BatchMetadata metadata;
        // Account and key-value pair of its storage
        address account;
        uint256 key;
        bytes32 value;
        // Proof path and leaf index
        bytes32[] path;
        uint64 index;
    }

    constructor(IZkSyncDiamond _zksyncDiamondAddress, SparseMerkleTree _smt) {
        zksyncDiamondAddress = _zksyncDiamondAddress;
        smt = _smt;
    }

    /// @notice Verify a target chain block hash given a home chain block hash and a proof.
    /// @param  homeBlockHash The block hash of the home chain.
    /// @param  input ABI encoded (bytes blockHeader, bytes32 sendRoot, bytes accountProof, bytes storageProof)
    function verifyTargetBlockHash(bytes32 homeBlockHash, bytes calldata input)
        external
        view
        returns (bytes32 targetBlockHash)
    {
        (StorageProof calldata proof) = abi.decode(input, StorageProof);



       
    }

    /// @notice Get a target chain block hash given a target chain sendRoot
    /// @param  input ABI encoded (bytes32 sendRoot)
    function getTargetBlockHash(bytes calldata input) external view returns (bytes32 targetBlockHash) {
        uint256 batchNumber = abi.decode(input, (uint256));

        targetBlockHash = zksyncDiamondAddress.storedBatchHash(batchNumber);
       
    }

    /// @notice Verify a storage slot given a target chain block hash and a proof.
    /// @param  targetBlockHash The block hash of the target chain.
    /// @param  input ABI encoded (bytes blockHeader, address account, uint256 slot, bytes accountProof, bytes storageProof)
    function verifyStorageSlot(bytes32 targetBlockHash, bytes calldata input)
        external
        pure
        returns (address account, uint256 slot, bytes32 value)
    {
       (StorageProof calldata_proof) = abi.decode(input, StorageProof);

       bytes32 l2BatchHash = smt.getRootHash(
            _proof.path, 
            TreeEntry({
                key: _proof.key,
                value: _proof.value,
                leafIndex: _proof.index
            }), 
            _proof.account
        );

        // Build stored batch info and compute its hash
        // batchHash of the StoredBatchInfo is computed from the proof
        StoredBatchInfo memory batch = StoredBatchInfo({
            batchNumber: _proof.metadata.batchNumber,
            batchHash: l2BatchHash,
            indexRepeatedStorageChanges: _proof.metadata.indexRepeatedStorageChanges,
            numberOfLayer1Txs: _proof.metadata.numberOfLayer1Txs,
            priorityOperationsHash: _proof.metadata.priorityOperationsHash,
            l2LogsTreeRoot: _proof.metadata.l2LogsTreeRoot,
            timestamp: _proof.metadata.timestamp,
            commitment: _proof.metadata.commitment
        });
        bytes32 computedL1BatchHash = _hashStoredBatchInfo(batch);
        

        if(computedL1BatchHash != targetBlockHash) {
            revert InvalidBatchHash();
        }

        account = _proof.account;
        slot = _proof.key;
        value = _proof.value;


    }

    /// @inheritdoc IBlockHashProver
    function version() external pure returns (uint256) {
        return 1;
    }
}
