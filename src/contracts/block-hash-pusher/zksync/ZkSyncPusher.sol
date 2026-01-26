// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BlockHashArrayBuilder} from "../BlockHashArrayBuilder.sol";
import {IBuffer} from "../interfaces/IBuffer.sol";
import {IPusher} from "../interfaces/IPusher.sol";

/// @notice Interface for the ZkSync Mailbox contract used to send L1->L2 messages.
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

/// @title ZkSyncPusher
/// @notice Implementation of IPusher for pushing block hashes to ZkSync Era L2.
/// @dev This contract sends block hashes from Ethereum L1 to a ZkSyncBuffer contract on ZkSync Era L2
///      via the ZkSync Mailbox's `requestL2Transaction` function. The pusher must be configured
///      with the correct ZkSync Diamond proxy address.
contract ZkSyncPusher is BlockHashArrayBuilder, IPusher {
    /// @dev The address of the ZkSync Diamond proxy contract on L1.
    address private immutable _zkSyncDiamond;

    /// @notice Thrown when the L2 transaction request fails.
    error FailedToPushHashes();

    /// @notice Parameters for the L2 transaction that will be executed on ZkSync.
    /// @param l2GasLimit The gas limit for the L2 transaction.
    /// @param l2GasPerPubdataByteLimit The gas per pubdata byte limit.
    /// @param refundRecipient The address to receive any refunds.
    struct ZkSyncL2Transaction {
        uint256 l2GasLimit;
        uint256 l2GasPerPubdataByteLimit;
        address refundRecipient;
    }

    constructor(address zkSyncDiamond_) {
        _zkSyncDiamond = zkSyncDiamond_;
    }

    /// @inheritdoc IPusher
    function pushHashes(address buffer, uint256 firstBlockNumber, uint256 batchSize, bytes calldata l2TransactionData)
        external
        payable
    {
        if (buffer == address(0)) {
            revert InvalidBuffer(buffer);
        }

        bytes32[] memory blockHashes = _buildBlockHashArray(firstBlockNumber, batchSize);
        bytes memory l2Calldata = abi.encodeCall(IBuffer.receiveHashes, (firstBlockNumber, blockHashes));

        ZkSyncL2Transaction memory l2Transaction = abi.decode(l2TransactionData, (ZkSyncL2Transaction));

        /// In the current behavior of the ZkSync Mailbox, the `l2GasPerPubdataByteLimit` value must be equal to the `REQUIRED_L2_GAS_PRICE_PER_PUBDATA` value,
        /// which is a constant defined by ZkSync. The current value is 800. However, since this might change in the future, the value must be passed in as a parameter.
        bytes32 canonicalTxHash = IMailbox(zkSyncDiamond()).requestL2Transaction{value: msg.value}(
            buffer,
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

    /// @notice The address of the ZkSync Diamond proxy contract on L1.
    /// @return The address of the ZkSync Diamond proxy contract on L1.
    function zkSyncDiamond() public view returns (address) {
        return _zkSyncDiamond;
    }
}
