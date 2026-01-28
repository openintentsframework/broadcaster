// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IBuffer} from "../../src/contracts/block-hash-pusher/interfaces/IBuffer.sol";

contract BufferMock is IBuffer {
    mapping(uint256 => bytes32) public parentChainBlockHash;

    uint256 public newestBlockNumber;

    function receiveHashes(uint256 firstBlockNumber, bytes32[] memory blockHashes) external {
        for (uint256 i = 0; i < blockHashes.length; i++) {
            parentChainBlockHash[firstBlockNumber + i] = blockHashes[i];
        }

        newestBlockNumber = uint64(firstBlockNumber + blockHashes.length - 1);
    }

    /// @dev The address of the pusher contract on the parent chain.
    function pusher() external view returns (address) {
        return address(0);
    }
}
