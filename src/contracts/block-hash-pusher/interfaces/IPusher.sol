// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice Interface for pusher contracts that push parent chain block hashes to a buffer on a child chain.
/// @dev    Pusher contracts are deployed on the parent chain (L1) and are responsible for:
///         - Building arrays of recent block hashes from the parent chain
///         - Sending these hashes to a buffer contract on the child chain via chain-specific cross-chain messaging
/// @notice Inspired by: https://github.com/OffchainLabs/block-hash-pusher/blob/main/contracts/interfaces/IPusher.sol
interface IPusher {
    /// @notice Emitted when block hashes are pushed to the buffer.
    /// @param  firstBlockNumber The block number of the first block in the batch.
    /// @param  lastBlockNumber The block number of the last block in the batch.
    event BlockHashesPushed(uint256 indexed firstBlockNumber, uint256 indexed lastBlockNumber);

    /// @notice Thrown when incorrect msg.value is provided
    error IncorrectMsgValue(uint256 expected, uint256 provided);

    /// @notice Thrown when the batch is invalid.
    error InvalidBatch(uint256 firstBlockNumber, uint256 batchSize);

    /// @notice Thrown when the buffer address is invalid.
    error InvalidBuffer(address buffer);

    /// @notice Push some hashes of previous blocks to the buffer on the child chain
    /// @param buffer The address of the buffer contract on the child chain.
    /// @param firstBlockNumber The first block number to push.
    /// @param batchSize The number of hashes to push. Must be less than or equal to MAX_BATCH_SIZE. Must be at least 1.
    /// @param l2TransactionData The data of the L2 transaction.
    function pushHashes(address buffer, uint256 firstBlockNumber, uint256 batchSize, bytes calldata l2TransactionData)
        external
        payable;
}
