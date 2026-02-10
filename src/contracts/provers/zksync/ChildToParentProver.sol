// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ProverUtils} from "../../libraries/ProverUtils.sol";
import {IStateProver} from "../../interfaces/IStateProver.sol";
import {IBuffer} from "../../block-hash-pusher/interfaces/IBuffer.sol";
import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";

/// @notice ZkSync implementation of a child to parent IStateProver.
/// @dev    verifyTargetStateCommitment and getTargetStateCommitment get block hashes from the block hash buffer.
///         See https://github.com/openintentsframework/broadcaster/blob/main/src/contracts/block-hash-pusher for more details.
///         verifyStorageSlot is implemented to work against any parent chain with a standard Ethereum block header and state trie.
contract ChildToParentProver is IStateProver {
    /// @dev Address of the block hash buffer contract.
    address public immutable BLOCK_HASH_BUFFER;
    /// @dev Storage slot the buffer contract uses to store block hashes.
    ///      See https://github.com/openintentsframework/broadcaster/blob/main/src/contracts/block-hash-pusher/BaseBuffer.sol
    uint256 public constant BLOCK_HASH_MAPPING_SLOT = 1;

    /// @dev The chain ID of the home chain (child chain).
    uint256 public immutable HOME_CHAIN_ID;

    error CallNotOnHomeChain();
    error CallOnHomeChain();

    constructor(address _blockHashBuffer, uint256 _homeChainId) {
        BLOCK_HASH_BUFFER = _blockHashBuffer;
        HOME_CHAIN_ID = _homeChainId;
    }

    /// @notice Get a parent chain block hash from the buffer at `BLOCK_HASH_BUFFER` using a storage proof
    /// @param  homeBlockHash The block hash of the home chain.
    /// @param  input ABI encoded (bytes blockHeader, uint256 targetBlockNumber, bytes accountProof, bytes storageProof)
    function verifyTargetStateCommitment(bytes32 homeBlockHash, bytes calldata input)
        external
        view
        returns (bytes32 targetStateCommitment)
    {
        if (block.chainid == HOME_CHAIN_ID) {
            revert CallOnHomeChain();
        }
        // decode the input
        (bytes memory rlpBlockHeader, uint256 targetBlockNumber, bytes memory accountProof, bytes memory storageProof) =
            abi.decode(input, (bytes, uint256, bytes, bytes));

        // calculate the slot based on the provided block number
        // see: https://github.com/OffchainLabs/block-hash-pusher/blob/a1e26f2e42e6306d1e7f03c5d20fa6aa64ff7a12/contracts/Buffer.sol#L32
        uint256 slot = uint256(SlotDerivation.deriveMapping(bytes32(BLOCK_HASH_MAPPING_SLOT), targetBlockNumber));

        // verify proofs and get the block hash
        targetStateCommitment = ProverUtils.getSlotFromBlockHeader(
            homeBlockHash, rlpBlockHeader, BLOCK_HASH_BUFFER, slot, accountProof, storageProof
        );
    }

    /// @notice Get a parent chain block hash from the buffer at `BLOCK_HASH_BUFFER`.
    /// @param  input ABI encoded (uint256 targetBlockNumber)
    function getTargetStateCommitment(bytes calldata input) external view returns (bytes32 targetStateCommitment) {
        if (block.chainid != HOME_CHAIN_ID) {
            revert CallNotOnHomeChain();
        }
        // decode the input
        uint256 targetBlockNumber = abi.decode(input, (uint256));

        // get the block hash from the buffer
        targetStateCommitment = IBuffer(BLOCK_HASH_BUFFER).parentChainBlockHash(targetBlockNumber);
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
