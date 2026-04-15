// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ProverUtils} from "../../libraries/ProverUtils.sol";
import {IStateProver} from "../../interfaces/IStateProver.sol";
import {IBuffer} from "../../block-hash-pusher/interfaces/IBuffer.sol";
import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";

/// @notice OP-Stack implementation of a child to parent IStateProver.
/// @dev    verifyTargetStateCommitment and getTargetStateCommitment get block hashes from the block hash buffer.
///         See https://github.com/openintentsframework/broadcaster/blob/main/src/contracts/block-hash-pusher for more details.
///         verifyStorageSlot is implemented to work against any parent chain with a standard Ethereum block header and state trie.
/// @custom:security-contact security@openzeppelin.com
contract ChildToParentProver is IStateProver {
    /// @dev Address of the block hash buffer contract.
    address public immutable blockHashBuffer;
    /// @dev Storage slot the buffer contract uses to store block hashes.
    ///      See https://github.com/openintentsframework/broadcaster/blob/main/src/contracts/block-hash-pusher/BaseBuffer.sol
    uint256 public constant BLOCK_HASH_MAPPING_SLOT = 1;

    /// @dev The chain ID of the home chain (child chain).
    uint256 public immutable homeChainId;

    error CallNotOnHomeChain();
    error CallOnHomeChain();
    error InvalidTargetStateCommitment();

    constructor(address _blockHashBuffer, uint256 _homeChainId) {
        blockHashBuffer = _blockHashBuffer;
        homeChainId = _homeChainId;
    }

    /// @notice Get a parent chain block hash from the buffer at `blockHashBuffer` using a storage proof
    /// @param  homeBlockHash The block hash of the home chain.
    /// @param  input ABI encoded (bytes blockHeader, uint256 targetBlockNumber, bytes accountProof, bytes storageProof)
    function verifyTargetStateCommitment(bytes32 homeBlockHash, bytes calldata input)
        external
        view
        returns (bytes32 targetStateCommitment)
    {
        if (block.chainid == homeChainId) {
            revert CallOnHomeChain();
        }
        // decode the input
        (bytes memory rlpBlockHeader, uint256 targetBlockNumber, bytes memory accountProof, bytes memory storageProof) =
            abi.decode(input, (bytes, uint256, bytes, bytes));

        // calculate the slot based on the provided block number
        // see: https://github.com/openintentsframework/broadcaster/blob/8d02f8e8e39de27de8f0ded481d3c4e5a129351f/src/contracts/block-hash-pusher/BaseBuffer.sol#L24
        uint256 slot = uint256(SlotDerivation.deriveMapping(bytes32(BLOCK_HASH_MAPPING_SLOT), targetBlockNumber));

        // verify proofs and get the block hash
        targetStateCommitment = ProverUtils.getSlotFromBlockHeader(
            homeBlockHash, rlpBlockHeader, blockHashBuffer, slot, accountProof, storageProof
        );
        require(targetStateCommitment != bytes32(0), InvalidTargetStateCommitment());
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
        require(targetStateCommitment != bytes32(0), InvalidTargetStateCommitment());
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
