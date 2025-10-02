// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;


contract BlockHeaders {

    struct L1BlockHeader {
        bytes32 parentHash;
        bytes32 sha3Uncles;
        address miner;
        bytes32 stateRoot;
        bytes32 transactionsRoot;
        bytes32 receiptsRoot;
        bytes   logsBloom;
        uint256 difficulty;
        uint256 number;
        uint64  gasLimit;
        uint64  gasUsed;
        uint64  timestamp;
        bytes   extraData;
        bytes32 mixHash;
        bytes8  nonce;
        uint256 baseFeePerGas;
        bytes32 withdrawalsRoot;
        uint64 blobGasUsed;
        uint64 excessBlobGas;
        bytes32 parentBeaconBlockRoot;
        bytes32 requestsHash;
    }

    struct L2BlockHeader {
        bytes32 parentHash;
        bytes32 sha3Uncles;
        address miner;
        bytes32 stateRoot;
        bytes32 transactionsRoot;
        bytes32 receiptsRoot;
        bytes   logsBloom;
        uint256 difficulty;
        uint256 number;
        uint64  gasLimit;
        uint64  gasUsed;
        uint64  timestamp;
        bytes   extraData;
        bytes32 mixHash;
        bytes8  nonce;
        uint256 baseFeePerGas;
        bytes32 withdrawalsRoot;
        uint64 blobGasUsed;
        uint64 excessBlobGas;
        bytes32 parentBeaconBlockRoot;
        bytes32 requestsHash;
        uint256 l1BlockNumber;
        uint256 sendCount;
        bytes32 sendRoot;
    }
}