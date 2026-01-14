// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPusher} from "./interfaces/IPusher.sol";
import {Blockhash} from "@openzeppelin/contracts/utils/Blockhash.sol";

abstract contract BasePusher is IPusher {
    /// @notice The max allowable number of hashes to push per call to pushHashes.
    uint256 public constant MAX_BATCH_SIZE = 8191; // EIP-2935 history storage window

    /// @dev Build an array of the last 256 block hashes
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
