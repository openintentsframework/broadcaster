// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IBuffer} from "./interfaces/IBuffer.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";

abstract contract BaseBuffer is IBuffer {
    uint256 private constant _bufferSize = 393168;

    uint64 private _newestBlockNumber;

    uint256[_bufferSize] private _blockNumberBuffer;

    mapping(uint256 => bytes32) private _parentChainBlockHashes;

    /// @inheritdoc IBuffer
    function parentChainBlockHash(uint256 parentChainBlockNumber) external view returns (bytes32) {
        bytes32 _parentChainBlockHash = _parentChainBlockHashes[parentChainBlockNumber];

        if (_parentChainBlockHash == 0) {
            revert UnknownParentChainBlockHash(parentChainBlockNumber);
        }

        return _parentChainBlockHash;
    }

    function _receiveHashes(uint256 firstBlockNumber, bytes32[] calldata blockHashes) internal {
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
            _newestBlockNumber = uint64(lastBlockNumber);
        }

        emit BlockHashesPushed(firstBlockNumber, lastBlockNumber);
    }

    function bufferSize() public pure returns (uint256) {
        return _bufferSize;
    }

    function newestBlockNumber() public view returns (uint64) {
        return _newestBlockNumber;
    }

    function blockNumberBuffer(uint256 _index) public view returns (uint256) {
        return _blockNumberBuffer[_index];
    }
}
