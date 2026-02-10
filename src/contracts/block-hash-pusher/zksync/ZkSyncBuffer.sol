// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseBuffer} from "../BaseBuffer.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {IBuffer} from "../interfaces/IBuffer.sol";

/// @title ZkSyncBuffer
/// @notice Implementation of BaseBuffer for storing Ethereum L1 block hashes on ZkSync Era L2.
/// @dev This contract extends BaseBuffer with access control specific to ZkSync's L1->L2 messaging.
///      When a message is sent from L1 to L2 via ZkSync's Mailbox, the sender address is aliased.
///      The buffer only accepts hash pushes from the aliased pusher address.
contract ZkSyncBuffer is BaseBuffer {
    /// @notice The address of the pusher contract on L1.
    address public immutable pusher;

    /// @notice Thrown when attempting to set an invalid pusher address.
    error InvalidPusherAddress();

    constructor(address pusher_) {
        pusher = pusher_;

        if (pusher_ == address(0)) {
            revert InvalidPusherAddress();
        }
    }

    /// @inheritdoc IBuffer
    function receiveHashes(uint256 firstBlockNumber, bytes32[] calldata blockHashes) external {
        if (msg.sender != aliasedPusher()) {
            revert NotPusher();
        }

        _receiveHashes(firstBlockNumber, blockHashes);
    }

    /// @notice The aliased address of the pusher contract on L2.
    function aliasedPusher() public view returns (address) {
        if (pusher == address(0)) {
            revert InvalidPusherAddress();
        }
        return AddressAliasHelper.applyL1ToL2Alias(pusher);
    }
}
