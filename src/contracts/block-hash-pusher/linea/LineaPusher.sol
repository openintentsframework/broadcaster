// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BlockHashArrayBuilder} from "../BlockHashArrayBuilder.sol";
import {IBuffer} from "../interfaces/IBuffer.sol";
import {IPusher} from "../interfaces/IPusher.sol";
import {IMessageService} from "@linea-contracts/messaging/interfaces/IMessageService.sol";

/// @title LineaPusher
/// @notice Implementation of IPusher for pushing block hashes to Linea L2.
/// @dev This contract sends block hashes from Ethereum L1 to a LineaBuffer contract on Linea L2
///      via the Linea MessageService's `sendMessage` function. The pusher must be configured
///      with the correct rollup address and buffer contract address.
contract LineaPusher is BlockHashArrayBuilder, IPusher {
    /// @dev The address of the Linea Rollup contract on L1.
    address private immutable _lineaRollup;

    /// @dev The address of the LineaBuffer contract on L2.
    address private immutable _bufferAddress;

    /// @notice Parameters for the L2 transaction that will be executed on Linea.
    /// @param _fee The fee paid for the postman to claim the message on L2
    struct LineaL2Transaction {
        uint256 _fee;
    }

    constructor(address rollup_, address bufferAddress_) {
        _lineaRollup = rollup_;
        _bufferAddress = bufferAddress_;
    }

    /// @inheritdoc IPusher
    function pushHashes(uint256 firstBlockNumber, uint256 batchSize, bytes calldata l2TransactionData)
        external
        payable
    {
        bytes32[] memory blockHashes = _buildBlockHashArray(firstBlockNumber, batchSize);
        bytes memory l2Calldata = abi.encodeCall(IBuffer.receiveHashes, (firstBlockNumber, blockHashes));

        LineaL2Transaction memory l2Transaction = abi.decode(l2TransactionData, (LineaL2Transaction));

        IMessageService(lineaRollup()).sendMessage{value: msg.value}(bufferAddress(), l2Transaction._fee, l2Calldata);

        emit BlockHashesPushed(firstBlockNumber, firstBlockNumber + batchSize - 1);
    }

    /// @inheritdoc IPusher
    function bufferAddress() public view returns (address) {
        return _bufferAddress;
    }

    /// @notice The address of the Linea Rollup contract on L1.
    /// @return The address of the Linea Rollup contract on L1.
    function lineaRollup() public view returns (address) {
        return _lineaRollup;
    }
}
