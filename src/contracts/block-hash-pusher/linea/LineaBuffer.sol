// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseBuffer} from "../BaseBuffer.sol";
import {IBuffer} from "../interfaces/IBuffer.sol";
import {IMessageService} from "@linea-contracts/messaging/interfaces/IMessageService.sol";

/// @title LineaBuffer
/// @notice Implementation of BaseBuffer for storing Ethereum L1 block hashes on Linea L2.
/// @dev This contract extends BaseBuffer with access control specific to Linea's L1->L2 messaging.
///      The pusher address on L1 must send the message via Linea Rollup to the buffer address on L2.
///      The Linea MessageService on L2 is responsible for relaying the message to the buffer contract on L2.
///      In order to do this, anyone is able to claim the message on the message service contract on L2.
///      Currently Linea runs a postman service that claims messages on L2, but this might not happen for more expensive messages and
///      users might need to claim the messages themselves in those cases.
contract LineaBuffer is BaseBuffer {
    /// @dev The address of the L2MessageService contract on L2.
    address private immutable _l2MessageService;

    /// @dev The address of the pusher contract on L1.
    address private immutable _pusher;

    /// @notice Thrown when attempting to set an invalid L2MessageService address.
    error InvalidL2MessageServiceAddress();

    /// @notice Thrown when attempting to set an invalid pusher address.
    error InvalidPusherAddress();

    /// @notice Thrown when the sender is not the Linea MessageService contract.
    error InvalidSender();

    /// @notice Thrown when the sender does not match the pusher address.
    error SenderMismatch();

    constructor(address l2MessageService_, address pusher_) {
        require(l2MessageService_ != address(0), InvalidL2MessageServiceAddress());
        require(pusher_ != address(0), InvalidPusherAddress());

        _l2MessageService = l2MessageService_;
        _pusher = pusher_;
    }

    /// @inheritdoc IBuffer
    function receiveHashes(uint256 firstBlockNumber, bytes32[] calldata blockHashes) external {
        IMessageService l2MessageServiceCached = IMessageService(l2MessageService());

        require(msg.sender == address(l2MessageServiceCached), InvalidSender());
        require(l2MessageServiceCached.sender() == _pusher, SenderMismatch());

        _receiveHashes(firstBlockNumber, blockHashes);
    }

    /// @inheritdoc IBuffer
    function pusher() public view returns (address) {
        return _pusher;
    }

    /// @notice The address of the Linea L2MessageService contract on L2.
    /// @return The address of the Linea L2MessageService contract on L2.
    function l2MessageService() public view returns (address) {
        return _l2MessageService;
    }
}
