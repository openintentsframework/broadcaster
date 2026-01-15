// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseBuffer} from "../BaseBuffer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IBuffer} from "../interfaces/IBuffer.sol";
import {IL2ScrollMessenger} from "@scroll-tech/scroll-contracts/L2/IL2ScrollMessenger.sol";

/// @title ScrollBuffer
/// @notice Implementation of BaseBuffer for storing Ethereum L1 block hashes on Scroll L2.
/// @dev This contract extends BaseBuffer with access control specific to Scroll's L1->L2 messaging.
///      The pusher address on L1 must send the message via L1ScrollMessenger to the buffer address on L2.
///      The L2ScrollMessenger contract on L2 is responsible for relaying the message to the buffer contract on L2.
/// @notice The contract is `Ownable` but the ownership is renounced after the pusher address is set.
///         This ensures that the pusher address is set only once and cannot be changed.
contract ScrollBuffer is BaseBuffer, Ownable {
    /// @dev The address of the L2ScrollMessenger contract on L2.
    address private _l2ScrollMessenger;

    /// @dev The address of the pusher contract on L1.
    address private _pusherAddress;

    /// @notice Thrown when attempting to receive hashes before the pusher address has been set.
    error PusherAddressNotSet();

    /// @notice Thrown when attempting to set an invalid L2ScrollMessenger address.
    error InvalidL2ScrollMessengerAddress();

    /// @notice Thrown when attempting to set an invalid pusher address.
    error InvalidPusherAddress();

    /// @notice Thrown when the domain message sender does not match the pusher address.
    error DomainMessageSenderMismatch();

    /// @notice Thrown when the sender is not the L2ScrollMessenger contract.
    error InvalidSender();

    /// @notice Emitted when the pusher address is set and ownership is renounced.
    /// @param pusherAddress The address of the pusher contract on L1.
    event PusherAddressSet(address pusherAddress);

    constructor(address l2ScrollMessenger_, address initialOwner_) Ownable(initialOwner_) {
        _l2ScrollMessenger = l2ScrollMessenger_;

        if (l2ScrollMessenger_ == address(0)) {
            revert InvalidL2ScrollMessengerAddress();
        }
    }

    /// @notice Sets the pusher address and renounces ownership.
    /// @dev This function can only be called once by the owner. After setting the pusher address,
    ///      ownership is renounced to prevent further modifications.
    /// @param newPusherAddress The address of the ScrollPusher contract on L1.
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
        IL2ScrollMessenger l2ScrollMessengerCached = IL2ScrollMessenger(l2ScrollMessenger());

        if (msg.sender != address(l2ScrollMessengerCached)) {
            revert InvalidSender();
        }
        if (_pusherAddress == address(0)) {
            revert PusherAddressNotSet();
        }
        if (l2ScrollMessengerCached.xDomainMessageSender() != _pusherAddress) {
            revert DomainMessageSenderMismatch();
        }

        _receiveHashes(firstBlockNumber, blockHashes);
    }

    /// @inheritdoc IBuffer
    function pusher() public view returns (address) {
        return _pusherAddress;
    }

    /// @notice The address of the L2ScrollMessenger contract on L2.
    /// @return The address of the L2ScrollMessenger contract on L2.
    function l2ScrollMessenger() public view returns (address) {
        return _l2ScrollMessenger;
    }
}
