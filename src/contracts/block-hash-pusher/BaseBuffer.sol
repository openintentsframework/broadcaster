// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IBuffer} from "./interfaces/IBuffer.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";

contract BaseBuffer is IBuffer {

    /// @inheritdoc IBuffer
    function parentChainBlockHash(uint256 parentChainBlockNumber) external view returns (bytes32) {
        bytes32 _parentChainBlockHash = blockHashMapping[parentChainBlockNumber];

        if (_parentChainBlockHash == 0) {
            revert UnknownParentChainBlockHash(parentChainBlockNumber);
        }

        return _parentChainBlockHash;
    }

    function _receiveHashes(uint256 firstBlockNumber, bytes32[] calldata blockHashes) internal {
        // write the hashes to the buffer, evicting old hashes as necessary
        for (uint256 i = 0; i < blockHashes.length; i++) {
            uint256 blockNumber = firstBlockNumber + i;
            uint256 bufferIndex = blockNumber % bufferSize;
            uint256 existingBlockNumber = blockNumberBuffer[bufferIndex];
            if (blockNumber <= existingBlockNumber) {
                // noop
                continue;
            }
            if (existingBlockNumber != 0) {
                // evict the old block hash
                blockHashMapping[existingBlockNumber] = 0;
            }
            // store the new block hash
            blockHashMapping[blockNumber] = blockHashes[i];
            blockNumberBuffer[bufferIndex] = blockNumber;
        }

        uint256 lastBlockNumber = firstBlockNumber + blockHashes.length - 1;

        if (lastBlockNumber > newestBlockNumber) {
            // update the newest block number
            newestBlockNumber = uint64(lastBlockNumber);
        }

        emit BlockHashesPushed(firstBlockNumber, lastBlockNumber);
    }
}