// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IBroadcaster} from "./interfaces/IBroadcaster.sol";

contract Broadcaster is IBroadcaster {
    function broadcastMessage(bytes32 message) external {
        // calculate the storage slot for the message
        uint256 slot = _messageSlot(message, msg.sender);

        // ensure the message has not already been broadcast
        require(_sload(slot) == 0, "Broadcaster: message already broadcasted");

        // store the message and its timestamp
        _sstore(slot, block.timestamp);

        emit MessageBroadcast(message, msg.sender);
    }

    /// @notice Not required by the standard, but useful for visibility. TODO: consider adding to the standard.
    function hasBroadcasted(bytes32 message, address publisher) external view returns (bool) {
        return _sload(_messageSlot(message, publisher)) != 0;
    }

    /// @dev Helper function to store a value in a storage slot.
    function _sstore(uint256 s, uint256 v) internal {
        assembly {
            sstore(s, v)
        }
    }

    /// @dev Helper function to load a storage slot.
    function _sload(uint256 s) internal view returns (uint256 r) {
        assembly {
            r := sload(s)
        }
    }

    /// @dev Helper function to calculate the storage slot for a message.
    function _messageSlot(bytes32 message, address publisher) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(message, publisher)));
    }
}
