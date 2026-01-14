// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPusher} from "./interfaces/IPusher.sol";
import {Blockhash} from "@openzeppelin/contracts/utils/Blockhash.sol";

/// @title BasePusher
/// @notice Abstract base contract for pushing parent chain block hashes to a child chain buffer.
/// @dev This contract provides the core functionality for building arrays of recent block hashes
///      that can be pushed to a buffer contract on a child chain. Concrete implementations should
///      override `pushHashes` to implement chain-specific cross-chain messaging mechanisms.
/// @notice Inspired by: https://github.com/OffchainLabs/block-hash-pusher/blob/main/contracts/Pusher.sol
abstract contract BasePusher is IPusher {
    /// @notice The max allowable number of hashes to push per call to pushHashes.
    uint256 public constant MAX_BATCH_SIZE = 8191; // EIP-2935 history storage window

    /// @notice Builds an array of block hashes for the most recent blocks.
    /// @dev Retrieves block hashes starting from `block.number - batchSize` up to `block.number - 1`.
    ///      The block hashes are retrieved using OpenZeppelin's Blockhash utility, which handles
    ///      the EIP-2935 history storage window limitations.
    /// @notice This contract assumes that is deployed in a chain that supports EIP-2935. If the chain does not support it, the batch size MUST be limited to 256.
    /// @param batchSize The number of block hashes to retrieve. Must be between 1 and MAX_BATCH_SIZE.
    /// @return firstBlockNumber The block number of the first block in the array.
    /// @return blockHashes Array of block hashes, ordered from oldest to newest.
    function _buildBlockHashArray(uint256 batchSize)
        internal
        view
        returns (uint256 firstBlockNumber, bytes32[] memory blockHashes)
    {
        if (batchSize == 0 || batchSize > MAX_BATCH_SIZE) {
            revert InvalidBatchSize(batchSize);
        }

        blockHashes = new bytes32[](batchSize);

        firstBlockNumber = block.number - batchSize;
        for (uint256 i = 0; i < batchSize; i++) {
            blockHashes[i] = Blockhash.blockHash(firstBlockNumber + i);
        }
    }
}
