// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BlockHashArrayBuilder} from "../BlockHashArrayBuilder.sol";
import {IBuffer} from "../interfaces/IBuffer.sol";
import {IPusher} from "../interfaces/IPusher.sol";
import {IL1ScrollMessenger} from "@scroll-tech/scroll-contracts/L1/IL1ScrollMessenger.sol";

/// @title ScrollPusher
/// @notice Implementation of IPusher for pushing block hashes to Scroll L2.
/// @dev This contract sends block hashes from Ethereum L1 to a ScrollBuffer contract on Scroll L2
///      via the Scroll L1ScrollMessenger's `sendMessage` function. The pusher must be configured
///      with the correct L1ScrollMessenger address and buffer contract address.
contract ScrollPusher is BlockHashArrayBuilder, IPusher {
    /// @dev The address of the Scroll L1ScrollMessenger contract on L1.
    address private immutable _l1ScrollMessenger;

    /// @dev The address of the ScrollBuffer contract on L2.
    address private immutable _bufferAddress;

    /// @notice Parameters for the L2 transaction that will be executed on Scroll.
    /// @param gasLimit The gas limit for the L2 transaction.
    /// @param refundAddress The address to receive any refunds.
    struct ScrollL2Transaction {
        uint256 gasLimit;
        address refundAddress;
    }

    constructor(address l1ScrollMessenger_, address bufferAddress_) {
        _l1ScrollMessenger = l1ScrollMessenger_;
        _bufferAddress = bufferAddress_;
    }

    /// @inheritdoc IPusher
    function pushHashes(uint256 firstBlockNumber, uint256 batchSize, bytes calldata l2TransactionData)
        external
        payable
    {
        bytes32[] memory blockHashes = _buildBlockHashArray(firstBlockNumber, batchSize);
        bytes memory l2Calldata = abi.encodeCall(IBuffer.receiveHashes, (firstBlockNumber, blockHashes));

        ScrollL2Transaction memory l2Transaction = abi.decode(l2TransactionData, (ScrollL2Transaction));

        IL1ScrollMessenger(l1ScrollMessenger()).sendMessage{value: msg.value}(
            bufferAddress(),
            0,
            l2Calldata,
            l2Transaction.gasLimit,
            l2Transaction.refundAddress != address(0) ? l2Transaction.refundAddress : msg.sender
        );

        emit BlockHashesPushed(firstBlockNumber, firstBlockNumber + batchSize - 1);
    }

    /// @inheritdoc IPusher
    function bufferAddress() public view returns (address) {
        return _bufferAddress;
    }

    /// @notice The address of the Scroll L1ScrollMessenger contract on L1.
    /// @return The address of the Scroll L1ScrollMessenger contract on L1.
    function l1ScrollMessenger() public view returns (address) {
        return _l1ScrollMessenger;
    }
}
