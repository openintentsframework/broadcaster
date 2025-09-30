// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Interface for the Arbitrum block hash buffer contract
/// @dev See https://github.com/OffchainLabs/block-hash-pusher
interface IBuffer {
    function parentChainBlockHash(uint256 blockNumber) external view returns (bytes32);
}
