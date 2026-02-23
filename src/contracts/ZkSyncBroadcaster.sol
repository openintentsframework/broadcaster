// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IBroadcaster} from "./interfaces/IBroadcaster.sol";

import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";

/// @notice Interface for ZkSync's L1 messenger contract that enables sending messages from L2 to L1.
interface IL1Messenger {
    /// @notice Sends a message from L2 to L1.
    /// @param _message The message data to send to L1.
    /// @return The message hash.
    function sendToL1(bytes calldata _message) external returns (bytes32);
}

/// @title ZkSyncBroadcaster
/// @notice ZkSync-specific implementation of the Broadcaster contract that enables publishing messages on-chain
///         with deduplication and timestamping, and additionally sends messages to L1.
/// @dev This contract extends the standard Broadcaster functionality by also sending messages to L1 via ZkSync's
///      L1Messenger. Like the standard Broadcaster, message timestamps are stored in deterministic storage slots
///      calculated from hash(message, publisher) to prevent duplicate broadcasts. Each broadcast is timestamped
///      with the block timestamp and emits an event for off-chain indexing. Additionally, when a message is
///      broadcast, it sends an L2->L1 message containing the original message and timestamp (ABI encoded together).
///      The storage layout is designed to be efficiently provable for cross-chain message verification.
/// @custom:security-contact security@openzeppelin.com
contract ZkSyncBroadcaster is IBroadcaster {
    /// @notice Error thrown when attempting to broadcast a message that has already been broadcast by the same publisher.
    error MessageAlreadyBroadcasted();

    /// @notice The ZkSync L1 messenger contract used to send messages from L2 to L1.
    IL1Messenger private _l1Messenger;

    constructor(address l1Messenger_) {
        _l1Messenger = IL1Messenger(l1Messenger_);
    }

    /// @notice Broadcasts a message on-chain with deduplication and sends it to L1.
    /// @dev The broadcast timestamp is stored in a deterministic storage slot calculated from hash(message, msg.sender).
    ///      This ensures that each (message, publisher) pair can only be broadcast once.
    ///      A MessageBroadcast event is emitted for off-chain indexing. Additionally, this ZkSync-specific
    ///      implementation sends an L2->L1 message via the L1Messenger containing the message slot and
    ///      timestamp ABI encoded together (bytes32 slot, uint256 timestamp).
    /// @param message The 32-byte message to broadcast.
    /// @custom:throws MessageAlreadyBroadcasted if this exact message has already been broadcast by the sender.
    function broadcastMessage(bytes32 message) external {
        // calculate the storage slot for the message
        bytes32 slot = _computeMessageSlot(message, msg.sender);

        // ensure the message has not already been broadcast
        if (_loadStorageSlot(slot) != 0) {
            revert MessageAlreadyBroadcasted();
        }

        // store the message and its timestamp
        _writeStorageSlot(slot, block.timestamp);

        // send the slot and timestamp to L1 via ZkSync's L1Messenger
        _l1Messenger.sendToL1(abi.encode(slot, uint256(block.timestamp)));

        // emit the event
        emit MessageBroadcast(message, msg.sender);
    }

    /// @notice Checks if a message has been broadcasted by a given publisher.
    /// @dev Not required by the standard, but useful for visibility.
    /// @param message The message to check.
    /// @param publisher The address of the publisher who may have broadcast the message.
    /// @return True if the message has been broadcasted by the publisher, false otherwise.
    function hasBroadcasted(bytes32 message, address publisher) external view returns (bool) {
        return _loadStorageSlot(_computeMessageSlot(message, publisher)) != 0;
    }

    /// @notice Returns the L1 messenger contract address.
    /// @return The IL1Messenger contract instance used to send messages to L1.
    function l1Messenger() public view returns (IL1Messenger) {
        return _l1Messenger;
    }

    /// @dev Helper function to store a value in a storage slot.
    /// @param slot The storage slot to write to.
    /// @param value The value to store.
    function _writeStorageSlot(bytes32 slot, uint256 value) internal {
        StorageSlot.getUint256Slot(slot).value = value;
    }

    /// @dev Helper function to load a storage slot.
    /// @param slot The storage slot to read from.
    /// @return value The value stored in the slot.
    function _loadStorageSlot(bytes32 slot) internal view returns (uint256 value) {
        value = StorageSlot.getUint256Slot(slot).value;
    }

    /// @dev Helper function to calculate the storage slot for a message.
    /// @param message The message to compute the slot for.
    /// @param publisher The address of the publisher.
    /// @return The computed storage slot.
    function _computeMessageSlot(bytes32 message, address publisher) internal pure returns (bytes32) {
        return keccak256(abi.encode(message, publisher));
    }
}
