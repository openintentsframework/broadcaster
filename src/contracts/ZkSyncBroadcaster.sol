// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IBroadcaster} from "./interfaces/IBroadcaster.sol";

import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";

interface IL1Messenger {

    function sendToL1(bytes calldata _message) external returns (bytes32);
}

/// @title Broadcaster
/// @notice Enables publishing messages on-chain with deduplication and timestamping
/// @dev Message timestamps are stored in deterministic storage slots calculated from hash(message, publisher) to prevent duplicate broadcasts.
///      Each broadcast is timestamped with the block timestamp and emits an event for off-chain indexing.
///      The storage layout is designed to be efficiently provable for cross-chain message verification.
contract ZkSyncBroadcaster is IBroadcaster {
    error MessageAlreadyBroadcasted();

    IL1Messenger private _l1Messenger;

    constructor(address l1Messenger_){
        _l1Messenger = IL1Messenger(l1Messenger_);

    }

    /// @notice Broadcasts a message on-chain with deduplication
    /// @dev The broadcast timestamp is stored in a deterministic storage slot calculated from hash(message, msg.sender).
    ///      This ensures that each (message, publisher) pair can only be broadcast once.
    ///      A MessageBroadcast event is emitted for off-chain indexing.
    /// @param message The 32-byte message to broadcast
    /// @custom:throws MessageAlreadyBroadcasted if this exact message has already been broadcast by the sender
    function broadcastMessage(bytes32 message) external {
        // calculate the storage slot for the message
        bytes32 slot = _computeMessageSlot(message, msg.sender);

        // ensure the message has not already been broadcast

        if (_loadStorageSlot(slot) != 0) {
            revert MessageAlreadyBroadcasted();
        }

        // store the message and its timestamp
        _writeStorageSlot(slot, block.timestamp);

        _l1Messenger.sendToL1(abi.encode(message, block.timestamp));

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

    /// @dev Helper function to store a value in a storage slot.
    function _writeStorageSlot(bytes32 slot, uint256 value) internal {
        StorageSlot.getUint256Slot(slot).value = value;
    }

    /// @dev Helper function to load a storage slot.
    function _loadStorageSlot(bytes32 slot) internal view returns (uint256 value) {
        value = StorageSlot.getUint256Slot(slot).value;
    }

    /// @dev Helper function to calculate the storage slot for a message.
    function _computeMessageSlot(bytes32 message, address publisher) internal pure returns (bytes32) {
        return keccak256(abi.encode(message, publisher));
    }

    function l1Messenger() public view returns(IL1Messenger){
        return _l1Messenger;
    }
}
