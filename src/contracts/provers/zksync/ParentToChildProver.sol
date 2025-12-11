// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ProverUtils} from "../../libraries/ProverUtils.sol";
import {IBlockHashProver} from "../../interfaces/IBlockHashProver.sol";
import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";

import {SparseMerkleTree, TreeEntry} from "./helpers/SparseMerkleTree.sol";

/// @notice Interface for the zkSync's contract
interface IZkSyncDiamond {
    /// @notice Returns the hash of the stored batch
    function storedBatchHash(uint256) external view returns (bytes32);
}

/// @notice  Implementation of a parent to child IBlockHashProver.
/// @dev    verifyTargetBlockHash and getTargetBlockHash get block hashes from the zksync diamond.
///         verifyStorageSlot is implemented to work against any zksync diamond.
contract ParentToChildProver is IBlockHashProver {

    IZkSyncDiamond immutable public zksyncDiamondAddress;
    SparseMerkleTree public smt;
    uint256 private immutable storedBatchHashSlot;

    error InvalidBatchHash();
    error TargetBlockHashNotFound();


    struct StoredBatchInfo {
        uint64 batchNumber;
        bytes32 batchHash;
        uint64 indexRepeatedStorageChanges;
        uint256 numberOfLayer1Txs;
        bytes32 priorityOperationsHash;
        bytes32 dependencyRootsRollingHash;
        bytes32 l2LogsTreeRoot;
        uint256 timestamp;
        bytes32 commitment;
    }


    /// @notice Metadata of the batch provided by the offchain resolver
    /// @dev batchHash is omitted because it will be calculated from the proof
    struct BatchMetadata {
        uint64 batchNumber;
        uint64 indexRepeatedStorageChanges;
        uint256 numberOfLayer1Txs;
        bytes32 priorityOperationsHash;
        bytes32 dependencyRootsRollingHash;
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

    struct ConcatenatedStorageProofs {
        StorageProof l2ToL1Proof;
        StorageProof l3ToL2Proof;
    }

    constructor(IZkSyncDiamond _zksyncDiamondAddress, SparseMerkleTree _smt, uint256 _storedBatchHashSlot) {
        zksyncDiamondAddress = _zksyncDiamondAddress;
        smt = _smt;
        storedBatchHashSlot = _storedBatchHashSlot;
    }

    /// @notice Verify a target chain block hash given a home chain block hash and a proof.
    /// @param  homeBlockHash The block hash of the home chain.
    /// @param  input ABI encoded (bytes blockHeader, bytes32 sendRoot, bytes accountProof, bytes storageProof)
    function verifyTargetBlockHash(bytes32 homeBlockHash, bytes calldata input)
        external
        view
        returns (bytes32 targetBlockHash)
    {
         // decode the input
        (bytes memory rlpBlockHeader, uint256 batchNumber, bytes memory accountProof, bytes memory storageProof) =
            abi.decode(input, (bytes, uint256, bytes, bytes));

        
        uint256 slot = uint256(SlotDerivation.deriveMapping(bytes32(storedBatchHashSlot), batchNumber));

        // verify proofs and get the block hash
        targetBlockHash =
            ProverUtils.getSlotFromBlockHeader(homeBlockHash, rlpBlockHeader, address(zksyncDiamondAddress), slot, accountProof, storageProof);
    }

    /// @notice Get a target chain batch hash given a target chain batch number
    /// @param  input ABI encoded (uint256 batchNumber)
    function getTargetBlockHash(bytes calldata input) external view returns (bytes32 targetBlockHash) {
        uint256 batchNumber = abi.decode(input, (uint256));

        targetBlockHash = zksyncDiamondAddress.storedBatchHash(batchNumber);

        if(targetBlockHash == bytes32(0)) {
            revert TargetBlockHashNotFound();
        }
       
    }

    /// @notice Verify a storage slot given a target chain block hash and a proof.
    /// @param  targetBlockHash The block hash of the target chain.
    /// @param  input ABI encoded (bytes blockHeader, address account, uint256 slot, bytes accountProof, bytes storageProof)
    function verifyStorageSlot(bytes32 targetBlockHash, bytes calldata input)
        external
        view
        returns (address account, uint256 slot, bytes32 value)
    {
       (ConcatenatedStorageProofs memory _proof) = abi.decode(input, (ConcatenatedStorageProofs));

       StorageProof memory l3ToL2Proof = _proof.l3ToL2Proof;


       bytes32 l3BatchHash = smt.getRootHash(
            l3ToL2Proof.path, 
            TreeEntry({
                key: l3ToL2Proof.key,
                value: l3ToL2Proof.value,
                leafIndex: l3ToL2Proof.index
            }), 
            l3ToL2Proof.account
        );

        // Build stored batch info and compute its hash
        // batchHash of the StoredBatchInfo is computed from the proof
        StoredBatchInfo memory batch = StoredBatchInfo({
            batchNumber: l3ToL2Proof.metadata.batchNumber,
            batchHash: l3BatchHash,
            indexRepeatedStorageChanges: l3ToL2Proof.metadata.indexRepeatedStorageChanges,
            numberOfLayer1Txs: l3ToL2Proof.metadata.numberOfLayer1Txs,
            priorityOperationsHash: l3ToL2Proof.metadata.priorityOperationsHash,
            dependencyRootsRollingHash: l3ToL2Proof.metadata.dependencyRootsRollingHash,
            l2LogsTreeRoot: l3ToL2Proof.metadata.l2LogsTreeRoot,
            timestamp: l3ToL2Proof.metadata.timestamp,
            commitment: l3ToL2Proof.metadata.commitment
        });

        bytes32 computedL3ToL2BatchHash = _hashStoredBatchInfo(batch);

        StorageProof memory l2ToL1Proof = _proof.l2ToL1Proof;


        if(computedL3ToL2BatchHash != l2ToL1Proof.value){
            revert("Hash mismatch");
        }

        bytes32 l2BatchHash = smt.getRootHash(
            l2ToL1Proof.path, 
            TreeEntry({
                key: l2ToL1Proof.key,
                value: l2ToL1Proof.value,
                leafIndex: l2ToL1Proof.index
            }), 
            l2ToL1Proof.account
        );

        StoredBatchInfo memory l1Batch = StoredBatchInfo({
            batchNumber: l2ToL1Proof.metadata.batchNumber,
            batchHash: l2BatchHash,
            indexRepeatedStorageChanges: l2ToL1Proof.metadata.indexRepeatedStorageChanges,
            numberOfLayer1Txs: l2ToL1Proof.metadata.numberOfLayer1Txs,
            priorityOperationsHash: l2ToL1Proof.metadata.priorityOperationsHash,
            dependencyRootsRollingHash: l2ToL1Proof.metadata.dependencyRootsRollingHash,
            l2LogsTreeRoot: l2ToL1Proof.metadata.l2LogsTreeRoot,
            timestamp: l2ToL1Proof.metadata.timestamp,
            commitment: l2ToL1Proof.metadata.commitment
        });

        bytes32 computedL2ToL1BatchHash = _hashStoredBatchInfo(l1Batch);


        if(computedL2ToL1BatchHash != targetBlockHash){
            revert InvalidBatchHash();
        }
        account = l3ToL2Proof.account;
        slot = l3ToL2Proof.key;
        value = l3ToL2Proof.value;
    }

    function _hashStoredBatchInfo(StoredBatchInfo memory _storedBatchInfo) internal pure returns (bytes32) {
        return keccak256(abi.encode(_storedBatchInfo));
    }

    /// @inheritdoc IBlockHashProver
    function version() external pure returns (uint256) {
        return 1;
    }
}