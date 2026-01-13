// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IPusher {
    /// @notice Emitted when block hashes are pushed to the buffer.
    /// @param  firstBlockNumber The block number of the first block in the batch.
    /// @param  lastBlockNumber The block number of the last block in the batch.
    event BlockHashesPushed(uint256 firstBlockNumber, uint256 lastBlockNumber);

    /// @notice Thrown when incorrect msg.value is provided
    error IncorrectMsgValue(uint256 expected, uint256 provided);

    /// @notice Thrown when the batch size is invalid.
    error InvalidBatchSize(uint256 batchSize);

    /// @notice Push some hashes of previous blocks to the buffer on the child chain
    /// @param batchSize The number of hashes to push. Must be less than or equal to MAX_BATCH_SIZE. Must be at least 1.
    /// @param l2TransactionData The data of the L2 transaction.
    function pushHashes(
        uint256 batchSize,
        bytes memory l2TransactionData
    ) external payable;

    /// @notice The max allowable number of hashes to push per call to pushHashes.
    function MAX_BATCH_SIZE() external view returns (uint256);

    /// @notice The address of the buffer contract on the child chain.
    function bufferAddress() external view returns (address);
}
