// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ProverUtils} from "../../libraries/ProverUtils.sol";
import {IBlockHashProver} from "../../interfaces/IBlockHashProver.sol";
import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";

interface ICheckpointStore {
    struct Checkpoint {
        uint48 blockNumber;
        bytes32 blockHash;
        bytes32 stateRoot;
    }

    function getCheckpoint(uint48 _blockNumber) external view returns (Checkpoint memory);
}

/// @notice Taiko implementation of a parent to child IBlockHashProver.
/// @dev    Home chain: L1 (Ethereum). Target chain: L2 (Taiko).
///         verifyTargetBlockHash gets L2 block hashes from L1's SignalService checkpoint storage.
///         getTargetBlockHash reads L2 block hashes directly from L1's SignalService.
///         verifyStorageSlot works against any Ethereum-compatible chain with standard block headers.
contract ParentToChildProver is IBlockHashProver {
    /// @dev Address of the L1 SignalService contract
    address public immutable signalService;

    /// @dev Storage slot where SignalService stores checkpoints mapping
    ///      mapping(uint48 blockNumber => CheckpointRecord checkpoint)
    ///      CheckpointRecord { bytes32 blockHash; bytes32 stateRoot; }
    uint256 public immutable checkpointsSlot;

    /// @dev L1 chain ID (home chain where this prover is deployed)
    uint256 public immutable homeChainId;

    error CallNotOnHomeChain();
    error CallOnHomeChain();
    error TargetBlockHashNotFound();

    constructor(address _signalService, uint256 _checkpointsSlot, uint256 _homeChainId) {
        signalService = _signalService;
        checkpointsSlot = _checkpointsSlot;
        homeChainId = _homeChainId;
    }

    /// @notice Verify L2 block hash using L1 SignalService checkpoint with storage proof
    /// @dev    Called on non-home chains (e.g., Taiko L2)
    /// @param  homeBlockHash The L1 block hash
    /// @param  input ABI encoded (bytes rlpBlockHeader, uint48 l2BlockNumber, bytes accountProof, bytes storageProof)
    /// @return targetBlockHash The L2 block hash stored in L1's SignalService
    function verifyTargetBlockHash(bytes32 homeBlockHash, bytes calldata input)
        external
        view
        returns (bytes32 targetBlockHash)
    {
        if (block.chainid == homeChainId) {
            revert CallOnHomeChain();
        }

        // Decode the input
        (bytes memory rlpBlockHeader, uint48 l2BlockNumber, bytes memory accountProof, bytes memory storageProof) =
            abi.decode(input, (bytes, uint48, bytes, bytes));

        // Calculate the storage slot for the checkpoint
        // checkpointSlot = keccak256(abi.encode(l2BlockNumber, checkpointsSlot))
        uint256 slot = uint256(SlotDerivation.deriveMapping(bytes32(checkpointsSlot), l2BlockNumber));

        // Verify proofs and get the L2 block hash from L1's SignalService
        // CheckpointRecord.blockHash is stored at the base slot
        targetBlockHash =
            ProverUtils.getSlotFromBlockHeader(homeBlockHash, rlpBlockHeader, signalService, slot, accountProof, storageProof);

        if (targetBlockHash == bytes32(0)) {
            revert TargetBlockHashNotFound();
        }
    }

    /// @notice Get L2 block hash directly from L1 SignalService
    /// @dev    Called on home chain (L1)
    /// @param  input ABI encoded (uint48 l2BlockNumber)
    /// @return targetBlockHash The L2 block hash
    function getTargetBlockHash(bytes calldata input) external view returns (bytes32 targetBlockHash) {
        if (block.chainid != homeChainId) {
            revert CallNotOnHomeChain();
        }

        // Decode the input
        uint48 l2BlockNumber = abi.decode(input, (uint48));

        // Get the checkpoint from SignalService
        ICheckpointStore.Checkpoint memory checkpoint = ICheckpointStore(signalService).getCheckpoint(l2BlockNumber);

        targetBlockHash = checkpoint.blockHash;

        if (targetBlockHash == bytes32(0)) {
            revert TargetBlockHashNotFound();
        }
    }

    /// @notice Verify a storage slot given a target chain block hash and a proof
    /// @param  targetBlockHash The block hash of the target chain (L2)
    /// @param  input ABI encoded (bytes blockHeader, address account, uint256 slot, bytes accountProof, bytes storageProof)
    /// @return account The address of the account on the target chain
    /// @return slot The storage slot of the account on the target chain
    /// @return value The value of the storage slot
    function verifyStorageSlot(bytes32 targetBlockHash, bytes calldata input)
        external
        pure
        returns (address account, uint256 slot, bytes32 value)
    {
        // Decode the input
        bytes memory rlpBlockHeader;
        bytes memory accountProof;
        bytes memory storageProof;
        (rlpBlockHeader, account, slot, accountProof, storageProof) =
            abi.decode(input, (bytes, address, uint256, bytes, bytes));

        // Verify proofs and get the value
        value = ProverUtils.getSlotFromBlockHeader(
            targetBlockHash, rlpBlockHeader, account, slot, accountProof, storageProof
        );
    }

    /// @inheritdoc IBlockHashProver
    function version() external pure returns (uint256) {
        return 1;
    }
}

