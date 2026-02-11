// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IPusher} from "./interfaces/IPusher.sol";
import {Blockhash} from "@openzeppelin/contracts/utils/Blockhash.sol";

/// @title BlockHashArrayBuilder
/// @notice Contract for pushing parent chain block hashes to a child chain buffer.
/// @dev This contract provides the core functionality for building arrays of recent block hashes
///      that can be pushed to a buffer contract on a child chain. Concrete implementations should
///      override `pushHashes` to implement chain-specific cross-chain messaging mechanisms.
/// @notice Inspired by: https://github.com/OffchainLabs/block-hash-pusher/blob/main/contracts/Pusher.sol
abstract contract BlockHashArrayBuilder {
    /// @notice Thrown when the block number is invalid
    error InvalidBlockNumber(uint256 blockNumber);

    /// @notice Builds an array of block hashes for the most recent blocks.
    /// @dev Retrieves block hashes starting from `block.number - batchSize` up to `block.number - 1`.
    ///      The block hashes are retrieved using OpenZeppelin's Blockhash utility, which handles
    ///      the EIP-2935 history storage window limitations.
    /// @param firstBlockNumber The block number of the first block in the array.
    /// @param batchSize The number of block hashes to retrieve. Must be between 1 and MAX_BATCH_SIZE.
    /// @return blockHashes Array of block hashes, ordered from oldest to newest.
    function _buildBlockHashArray(uint256 firstBlockNumber, uint256 batchSize)
        internal
        view
        returns (bytes32[] memory blockHashes)
    {
        require(batchSize != 0 && batchSize <= MAX_BATCH_SIZE(), IPusher.InvalidBatch(firstBlockNumber, batchSize));

        require(firstBlockNumber + batchSize <= block.number, IPusher.InvalidBatch(firstBlockNumber, batchSize));

        blockHashes = new bytes32[](batchSize);

        for (uint256 i; i < batchSize; i++) {
            blockHashes[i] = _blockHash(firstBlockNumber + i);
        }
    }

    /// @notice Retrieves the block hash for a given block number.
    /// @param blockNumber The block number to retrieve the hash for.
    /// @return The block hash.
    function _blockHash(uint256 blockNumber) internal view virtual returns (bytes32) {
        // Note that this library is only supported on chains that support EIP-2935.
        bytes32 blockHash = Blockhash.blockHash(blockNumber);
        require(blockHash != 0, InvalidBlockNumber(blockNumber));
        return blockHash;
    }

    /// @notice The max allowable number of hashes to push per call to pushHashes.
    /// @return the max batch size
    function MAX_BATCH_SIZE() public pure virtual returns (uint256) {
        // EIP-2935 history storage window is 8191 blocks
        return 8191;
    }
}
