// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseBuffer} from "../BaseBuffer.sol";
import {IBuffer} from "../interfaces/IBuffer.sol";
import {ICrossDomainMessenger} from "@eth-optimism/contracts/libraries/bridge/ICrossDomainMessenger.sol";

/// @title OptimismBuffer
/// @notice Implementation of BaseBuffer for storing Ethereum L1 block hashes on Optimism L2.
/// @dev This contract extends BaseBuffer with access control specific to Optimism's L1->L2 messaging.
///      The pusher address on L1 must send the message via L1CrossDomainMessengerProxy to the buffer address on L2.
///      The L2CrossDomainMessenger contract on L2 is responsible for relaying the message to the buffer contract on L2.
/// @custom:security-contact security@openzeppelin.com
contract OptimismBuffer is BaseBuffer {
    /// @dev The address of the L2CrossDomainMessenger contract on L2.
    address private immutable _l2CrossDomainMessenger;

    /// @dev The address of the pusher contract on L1.
    address private immutable _pusher;

    /// @notice Thrown when attempting to set an invalid L2CrossDomainMessenger address.
    error InvalidL2CrossDomainMessengerAddress();

    /// @notice Thrown when attempting to set an invalid pusher address.
    error InvalidPusherAddress();

    /// @notice Thrown when the domain message sender does not match the pusher address.
    error DomainMessageSenderMismatch();

    /// @notice Thrown when the sender is not the L2CrossDomainMessenger contract.
    error InvalidSender();

    constructor(address l2CrossDomainMessenger_, address pusher_) {
        require(l2CrossDomainMessenger_ != address(0), InvalidL2CrossDomainMessengerAddress());
        require(pusher_ != address(0), InvalidPusherAddress());

        _l2CrossDomainMessenger = l2CrossDomainMessenger_;
        _pusher = pusher_;
    }

    /// @inheritdoc IBuffer
    function receiveHashes(uint256 firstBlockNumber, bytes32[] calldata blockHashes) external {
        ICrossDomainMessenger l2CrossDomainMessengerCached = ICrossDomainMessenger(l2CrossDomainMessenger());

        require(msg.sender == address(l2CrossDomainMessengerCached), InvalidSender());
        require(l2CrossDomainMessengerCached.xDomainMessageSender() == _pusher, DomainMessageSenderMismatch());

        _receiveHashes(firstBlockNumber, blockHashes);
    }

    /// @inheritdoc IBuffer
    function pusher() public view returns (address) {
        return _pusher;
    }

    /// @notice The address of the L2CrossDomainMessenger contract on L2.
    /// @return The address of the L2CrossDomainMessenger contract on L2.
    function l2CrossDomainMessenger() public view returns (address) {
        return _l2CrossDomainMessenger;
    }
}
