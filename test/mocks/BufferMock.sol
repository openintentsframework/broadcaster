// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IBuffer} from "block-hash-pusher/contracts/interfaces/IBuffer.sol";

contract BufferMock is IBuffer {


    mapping(uint256 => bytes32) public parentChainBlockHash;

    uint64 public newestBlockNumber;


    function receiveHashes(uint256 firstBlockNumber, bytes32[] memory blockHashes) external {
        for (uint256 i = 0; i < blockHashes.length; i++) {
            parentChainBlockHash[firstBlockNumber + i] = blockHashes[i];
        }

        newestBlockNumber = uint64(firstBlockNumber + blockHashes.length - 1);
    }

    function bufferSize() external view returns (uint256) {
        return 0;
    }

    function systemPusher() external view returns (address) {
        return address(0);
    }
    /// @dev The aliased address of the pusher contract on the parent chain.
    function aliasedPusher() external view returns (address) {
        return address(0);
    }
    
    function blockHashMapping(uint256) external view returns (bytes32) {
        return bytes32(0);
    }
    
    function blockNumberBuffer(uint256) external view returns (uint256) {
        return 0;
    }
    /// @dev Whether the system address has pushed a block hash to the buffer.
    ///      Once this is set, only the system address can push more hashes.
    function systemHasPushed() external view returns (bool){
        return false;
    }
}