// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseBuffer} from "../BaseBuffer.sol";
import {IBuffer} from "../interfaces/IBuffer.sol";
import {IL2ScrollMessenger} from "@scroll-tech/scroll-contracts/L2/IL2ScrollMessenger.sol";

/// @title ScrollBuffer
/// @notice Implementation of BaseBuffer for storing Ethereum L1 block hashes on Scroll L2.
/// @dev This contract extends BaseBuffer with access control specific to Scroll's L1->L2 messaging.
///      The pusher address on L1 must send the message via L1ScrollMessenger to the buffer address on L2.
///      The L2ScrollMessenger contract on L2 is responsible for relaying the message to the buffer contract on L2.
/// @custom:security-contact security@openzeppelin.org
contract ScrollBuffer is BaseBuffer {
    /// @dev The address of the L2ScrollMessenger contract on L2.
    address private immutable _l2ScrollMessenger;

    /// @dev The address of the pusher contract on L1.
    address private immutable _pusher;

    /// @notice Thrown when attempting to set an invalid L2ScrollMessenger address.
    error InvalidL2ScrollMessengerAddress();

    /// @notice Thrown when attempting to set an invalid pusher address.
    error InvalidPusherAddress();

    /// @notice Thrown when the domain message sender does not match the pusher address.
    error DomainMessageSenderMismatch();

    /// @notice Thrown when the sender is not the L2ScrollMessenger contract.
    error InvalidSender();

    constructor(address l2ScrollMessenger_, address pusher_) {
        require(l2ScrollMessenger_ != address(0), InvalidL2ScrollMessengerAddress());
        require(pusher_ != address(0), InvalidPusherAddress());

        _l2ScrollMessenger = l2ScrollMessenger_;
        _pusher = pusher_;
    }

    /// @inheritdoc IBuffer
    function receiveHashes(uint256 firstBlockNumber, bytes32[] calldata blockHashes) external {
        IL2ScrollMessenger l2ScrollMessengerCached = IL2ScrollMessenger(l2ScrollMessenger());

        require(msg.sender == address(l2ScrollMessengerCached), InvalidSender());
        require(l2ScrollMessengerCached.xDomainMessageSender() == _pusher, DomainMessageSenderMismatch());

        _receiveHashes(firstBlockNumber, blockHashes);
    }

    /// @inheritdoc IBuffer
    function pusher() public view returns (address) {
        return _pusher;
    }

    /// @notice The address of the L2ScrollMessenger contract on L2.
    /// @return The address of the L2ScrollMessenger contract on L2.
    function l2ScrollMessenger() public view returns (address) {
        return _l2ScrollMessenger;
    }
}
