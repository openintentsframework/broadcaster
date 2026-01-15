// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseBuffer} from "../BaseBuffer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {IBuffer} from "../interfaces/IBuffer.sol";

/// @title ScrollBuffer
/// @notice Implementation of BaseBuffer for storing Ethereum L1 block hashes on Scroll L2.
/// @dev This contract extends BaseBuffer with access control specific to Scroll's L1->L2 messaging.
///      The pusher address on L1 must send the message via L1ScrollMessenger to the buffer address on L2.
///      The ScrollL2Messenger is responsible for relaying the message to the buffer contract on L2.
/// @notice The contract is `Ownable` but the ownership is renounced after the pusher address is set.
///         This ensures that the pusher address is set only once and cannot be changed.
contract ScrollBuffer is BaseBuffer, Ownable {
    /// @dev The address of the pusher contract on L1.
    address private _pusherAddress;

    /// @notice Thrown when attempting to receive hashes before the pusher address has been set.
    error PusherAddressNotSet();

    /// @notice Thrown when attempting to set an invalid pusher address.
    error InvalidPusherAddress();

    /// @notice Emitted when the pusher address is set and ownership is renounced.
    /// @param pusherAddress The address of the pusher contract on L1.
    event PusherAddressSet(address pusherAddress);

    constructor(address initialOwner_) Ownable(initialOwner_) {}

    /// @notice Sets the pusher address and renounces ownership.
    /// @dev This function can only be called once by the owner. After setting the pusher address,
    ///      ownership is renounced to prevent further modifications. The pusher address is used to
    ///      derive the aliased pusher address that will be authorized to push hashes.
    /// @param newPusherAddress The address of the ZkSyncPusher contract on L1.
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
        if (_pusherAddress == address(0)) {
            revert PusherAddressNotSet();
        }

        if (msg.sender != aliasedPusher()) {
            revert NotPusher();
        }

        _receiveHashes(firstBlockNumber, blockHashes);
    }

    /// @inheritdoc IBuffer
    function pusher() public view returns (address) {
        return _pusherAddress;
    }

    /// @notice The aliased address of the pusher contract on L2.
    function aliasedPusher() public view returns (address) {
        if (_pusherAddress == address(0)) {
            revert PusherAddressNotSet();
        }
        return AddressAliasHelper.applyL1ToL2Alias(_pusherAddress);
    }
}
