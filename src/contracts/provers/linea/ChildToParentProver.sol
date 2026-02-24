// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SparseMerkleProof} from "../../libraries/linea/SparseMerkleProof.sol";
import {ProverUtils} from "../../libraries/ProverUtils.sol";
import {IStateProver} from "../../interfaces/IStateProver.sol";
import {IBuffer} from "../../block-hash-pusher/interfaces/IBuffer.sol";
import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";

/// @notice Linea implementation of a child to parent IStateProver.
/// @dev    verifyTargetStateCommitment and getTargetStateCommitment get block hashes from the block hash buffer.
///         verifyStorageSlot is implemented to work against any parent chain with a standard Ethereum block header and state trie.
contract ChildToParentProver is IStateProver {
    /// @dev Address of the block hash buffer contract.
    address public immutable blockHashBuffer;
    /// @dev Storage slot the buffer contract uses to store block hashes.
    ///      See https://github.com/openintentsframework/broadcaster/blob/main/src/contracts/block-hash-pusher/BaseBuffer.sol
    uint256 public constant blockHashMappingSlot = 1;

    /// @dev The chain ID of the home chain (child chain).
    uint256 public immutable homeChainId;

    error CallNotOnHomeChain();
    error CallOnHomeChain();
    error InvalidAccountProof();
    error InvalidStorageProof();
    error StorageValueMismatch();
    error AccountKeyMismatch();
    error AccountValueMismatch();
    error StorageKeyMismatch();

    constructor(address _blockHashBuffer, uint256 _homeChainId) {
        blockHashBuffer = _blockHashBuffer;
        homeChainId = _homeChainId;
    }

    /// @notice Get a parent chain block hash from the buffer at `blockHashBuffer` using a Linea SMT proof
    /// @dev Linea uses Sparse Merkle Trees with MiMC hashing, not MPT.
    ///      Proofs must be generated using linea_getProof RPC method.
    /// @param  homeBlockHash The state root of the home chain (Linea SMT state root).
    /// @param  input ABI encoded (uint256 targetBlockNumber, uint256 accountLeafIndex, bytes[] accountProof,
    ///         bytes accountValue, uint256 storageLeafIndex, bytes[] storageProof, bytes32 claimedStorageValue)
    function verifyTargetStateCommitment(bytes32 homeBlockHash, bytes calldata input)
        external
        view
        returns (bytes32 targetStateCommitment)
    {
        if (block.chainid == homeChainId) {
            revert CallOnHomeChain();
        }

        uint256 targetBlockNumber;
        uint256 accountLeafIndex;
        bytes[] memory accountProof;
        bytes memory accountValue;
        uint256 storageLeafIndex;
        bytes[] memory storageProof;
        bytes32 claimedStorageValue;

        (
            targetBlockNumber,
            accountLeafIndex,
            accountProof,
            accountValue,
            storageLeafIndex,
            storageProof,
            claimedStorageValue
        ) = abi.decode(input, (uint256, uint256, bytes[], bytes, uint256, bytes[], bytes32));

        uint256 slot = uint256(SlotDerivation.deriveMapping(bytes32(blockHashMappingSlot), targetBlockNumber));

        bool accountValid = SparseMerkleProof.verifyProof(accountProof, accountLeafIndex, homeBlockHash);
        if (!accountValid) {
            revert InvalidAccountProof();
        }

        SparseMerkleProof.Leaf memory accountLeaf = SparseMerkleProof.getLeaf(accountProof[accountProof.length - 1]);
        bytes32 expectedAccountHKey = SparseMerkleProof.hashAccountKey(blockHashBuffer);
        if (accountLeaf.hKey != expectedAccountHKey) {
            revert AccountKeyMismatch();
        }

        bytes32 expectedAccountHValue = SparseMerkleProof.hashAccountValue(accountValue);
        if (accountLeaf.hValue != expectedAccountHValue) {
            revert AccountValueMismatch();
        }

        SparseMerkleProof.Account memory accountData = SparseMerkleProof.getAccount(accountValue);

        bool storageValid = SparseMerkleProof.verifyProof(storageProof, storageLeafIndex, accountData.storageRoot);
        if (!storageValid) {
            revert InvalidStorageProof();
        }

        SparseMerkleProof.Leaf memory storageLeaf = SparseMerkleProof.getLeaf(storageProof[storageProof.length - 1]);
        bytes32 expectedStorageHKey = SparseMerkleProof.hashStorageKey(bytes32(slot));
        if (storageLeaf.hKey != expectedStorageHKey) {
            revert StorageKeyMismatch();
        }

        bytes32 expectedHValue = SparseMerkleProof.hashStorageValue(claimedStorageValue);
        if (storageLeaf.hValue != expectedHValue) {
            revert StorageValueMismatch();
        }

        targetStateCommitment = claimedStorageValue;
    }

    /// @notice Get a parent chain block hash from the buffer at `blockHashBuffer`.
    /// @param  input ABI encoded (uint256 targetBlockNumber)
    function getTargetStateCommitment(bytes calldata input) external view returns (bytes32 targetStateCommitment) {
        if (block.chainid != homeChainId) {
            revert CallNotOnHomeChain();
        }
        // decode the input
        uint256 targetBlockNumber = abi.decode(input, (uint256));

        // get the block hash from the buffer
        targetStateCommitment = IBuffer(blockHashBuffer).parentChainBlockHash(targetBlockNumber);
    }

    /// @notice Verify a storage slot given a target chain block hash and a proof.
    /// @param  targetStateCommitment The block hash of the target chain.
    /// @param  input ABI encoded (bytes blockHeader, address account, uint256 slot, bytes accountProof, bytes storageProof)
    function verifyStorageSlot(bytes32 targetStateCommitment, bytes calldata input)
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
        value = ProverUtils.getSlotFromBlockHeader(
            targetStateCommitment, rlpBlockHeader, account, slot, accountProof, storageProof
        );
    }

    /// @inheritdoc IStateProver
    function version() external pure returns (uint256) {
        return 1;
    }
}
