// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BasePusher} from "../BasePusher.sol";
import {IBuffer} from "../interfaces/IBuffer.sol";

interface IMailbox {
    function requestL2Transaction(
        address _contractL2,
        uint256 _l2Value,
        bytes calldata _calldata,
        uint256 _l2GasLimit,
        uint256 _l2GasPerPubdataByteLimit,
        bytes[] calldata _factoryDeps,
        address _refundRecipient
    ) external payable returns (bytes32 canonicalTxHash);
}

contract ZkSyncPusher is BasePusher {
    address private immutable _zkSyncDiamond;

    address private immutable _bufferAddress;

    error FailedToPushHashes();

    struct L2Transaction {
        uint256 l2GasLimit;
        uint256 l2GasPerPubdataByteLimit;
        address refundRecipient;
    }

    constructor(address zkSyncDiamond_, address bufferAddress_) {
        _zkSyncDiamond = zkSyncDiamond_;
        _bufferAddress = bufferAddress_;
    }

    function pushHashes(uint256 batchSize, bytes memory l2TransactionData) external payable {
        (uint256 firstBlockNumber, bytes32[] memory blockHashes) = _buildBlockHashArray(batchSize);
        bytes memory l2Calldata = abi.encodeCall(IBuffer.receiveHashes, (firstBlockNumber, blockHashes));

        L2Transaction memory l2Transaction = abi.decode(l2TransactionData, (L2Transaction));

        bytes32 canonicalTxHash = IMailbox(zkSyncDiamond()).requestL2Transaction{value: msg.value}(
            bufferAddress(),
            0,
            l2Calldata,
            l2Transaction.l2GasLimit,
            l2Transaction.l2GasPerPubdataByteLimit,
            new bytes[](0),
            l2Transaction.refundRecipient != address(0) ? l2Transaction.refundRecipient : msg.sender
        );

        if (canonicalTxHash == bytes32(0)) {
            revert FailedToPushHashes();
        }

        emit BlockHashesPushed(firstBlockNumber, firstBlockNumber + batchSize - 1);
    }

    function bufferAddress() public view returns (address) {
        return _bufferAddress;
    }

    function zkSyncDiamond() public view returns (address) {
        return _zkSyncDiamond;
    }
}
