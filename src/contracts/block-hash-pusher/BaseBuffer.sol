// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IBuffer} from "./interfaces/IBuffer.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";

/// @title BaseBuffer
/// @notice Abstract base contract for storing parent chain block hashes in a circular buffer.
/// @dev This contract implements a sparse circular buffer mechanism where block hashes are stored
///      using modulo-based indexing. When a block hash is stored at an index that already contains
///      a different block number, the old hash is evicted. This allows for efficient storage of
///      a sliding window of block hashes without requiring contiguous block numbers.
/// @dev Concrete implementations should override `receiveHashes` to add chain-specific access control.
/// @notice Inspired by: https://github.com/OffchainLabs/block-hash-pusher/blob/main/contracts/Buffer.sol
abstract contract BaseBuffer is IBuffer {
    /// @dev The size of the circular buffer.
    /// @dev For a parent chain with a block time of 12s (Ethereum), this is equivalent to roughly 54 days of history.
    uint256 private constant _bufferSize = 393168; // 48 * 8191, where 8191 is the EIP-2935 history storage window

    /// @dev The block number of the newest block in the buffer.
    uint256 private _newestBlockNumber;

    /// @dev Circular buffer storing block numbers at each index position.
    uint256[_bufferSize] private _blockNumberBuffer;

    /// @dev Mapping of block numbers to their corresponding block hashes.
    mapping(uint256 blockNumber => bytes32 blockHash) private _parentChainBlockHashes;

    /// @inheritdoc IBuffer
    function parentChainBlockHash(uint256 parentChainBlockNumber) external view returns (bytes32) {
        bytes32 _parentChainBlockHash = _parentChainBlockHashes[parentChainBlockNumber];

        if (_parentChainBlockHash == 0) {
            revert UnknownParentChainBlockHash(parentChainBlockNumber);
        }

        return _parentChainBlockHash;
    }

    /// @notice Internal function to receive and store block hashes in the buffer.
    /// @dev This function implements the core buffer logic: storing hashes using modulo-based indexing
    ///      and evicting old hashes when necessary. Concrete implementations should call this function
    ///      from their `receiveHashes` implementation after performing access control checks.
    /// @param firstBlockNumber The block number of the first block in the batch.
    /// @param blockHashes Array of block hashes to store, assumed to be in contiguous order.
    function _receiveHashes(uint256 firstBlockNumber, bytes32[] calldata blockHashes) internal {
        if (blockHashes.length == 0) {
            revert EmptyBlockHashes();
        }

        // write the hashes to the buffer, evicting old hashes as necessary
        for (uint256 i = 0; i < blockHashes.length; i++) {
            uint256 blockNumber = firstBlockNumber + i;
            uint256 bufferIndex = blockNumber % _bufferSize;
            uint256 existingBlockNumber = _blockNumberBuffer[bufferIndex];
            if (blockNumber <= existingBlockNumber) {
                // noop
                continue;
            }
            if (existingBlockNumber != 0) {
                // evict the old block hash
                _parentChainBlockHashes[existingBlockNumber] = 0;
            }
            // store the new block hash
            _parentChainBlockHashes[blockNumber] = blockHashes[i];
            _blockNumberBuffer[bufferIndex] = blockNumber;
        }

        uint256 lastBlockNumber = firstBlockNumber + blockHashes.length - 1;

        if (lastBlockNumber > _newestBlockNumber) {
            // update the newest block number
            _newestBlockNumber = lastBlockNumber;
        }

        emit BlockHashesPushed(firstBlockNumber, lastBlockNumber);
    }

    /// @inheritdoc IBuffer
    function bufferSize() public pure returns (uint256) {
        return _bufferSize;
    }

    /// @inheritdoc IBuffer
    function newestBlockNumber() public view returns (uint256) {
        return _newestBlockNumber;
    }

    /// @inheritdoc IBuffer
    function blockNumberBuffer(uint256 _index) public view returns (uint256) {
        return _blockNumberBuffer[_index];
    }
}
