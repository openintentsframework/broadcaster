// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseBuffer} from "../BaseBuffer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
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
/// @notice The contract is `Ownable` but the ownership is renounced after the pusher address is set.
///         This ensures that the pusher address is set only once and cannot be changed.
contract LineaBuffer is BaseBuffer, Ownable {
    /// @dev The address of the L2MessageService contract on L2.
    address private _l2MessageService;

    /// @dev The address of the pusher contract on L1.
    address private _pusherAddress;

    /// @notice Thrown when attempting to receive hashes before the pusher address has been set.
    error PusherAddressNotSet();

    /// @notice Thrown when attempting to set an invalid L2MessageService address.
    error InvalidL2MessageServiceAddress();

    /// @notice Thrown when attempting to set an invalid pusher address.
    error InvalidPusherAddress();

    /// @notice Thrown when the sender is not the Linea MessageService contract.
    error InvalidSender();

    /// @notice Thrown when the sender does not match the pusher address.
    error SenderMismatch();

    /// @notice Emitted when the pusher address is set and ownership is renounced.
    /// @param pusherAddress The address of the pusher contract on L1.
    event PusherAddressSet(address pusherAddress);

    constructor(address l2MessageService_, address initialOwner_) Ownable(initialOwner_) {
        _l2MessageService = l2MessageService_;

        if (l2MessageService_ == address(0)) {
            revert InvalidL2MessageServiceAddress();
        }
    }

    /// @notice Sets the pusher address and renounces ownership.
    /// @dev This function can only be called once by the owner. After setting the pusher address,
    ///      ownership is renounced to prevent further modifications.
    /// @param newPusherAddress The address of the LineaPusher contract on L1.
    function setPusherAddress(address newPusherAddress) external onlyOwner {
        if (newPusherAddress == address(0)) {
            revert InvalidPusherAddress();
        }

        _pusherAddress = newPusherAddress;

        emit PusherAddressSet(newPusherAddress);
        renounceOwnership();
    }

    /// @inheritdoc IBuffer
    function receiveHashes(uint256 firstBlockNumber, bytes32[] calldata blockHashes) external {
        IMessageService l2MessageServiceCached = IMessageService(l2MessageService());

        if (msg.sender != address(l2MessageServiceCached)) {
            revert InvalidSender();
        }
        if (_pusherAddress == address(0)) {
            revert PusherAddressNotSet();
        }
        if (l2MessageServiceCached.sender() != _pusherAddress) {
            revert SenderMismatch();
        }

        _receiveHashes(firstBlockNumber, blockHashes);
    }

    /// @inheritdoc IBuffer
    function pusher() public view returns (address) {
        return _pusherAddress;
    }

    /// @notice The address of the Linea L2MessageService contract on L2.
    /// @return The address of the Linea L2MessageService contract on L2.
    function l2MessageService() public view returns (address) {
        return _l2MessageService;
    }
}
