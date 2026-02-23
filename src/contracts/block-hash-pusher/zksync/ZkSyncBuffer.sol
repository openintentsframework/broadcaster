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
/// @custom:security-contact security@openzeppelin.com
contract ZkSyncBuffer is BaseBuffer {
    /// @dev The address of the pusher contract on L1.
    address private immutable _pusher;

    /// @notice Thrown when attempting to set an invalid pusher address.
    error InvalidPusherAddress();

    constructor(address pusher_) {
        require(pusher_ != address(0), InvalidPusherAddress());
        _pusher = pusher_;
    }

    /// @inheritdoc IBuffer
    function receiveHashes(uint256 firstBlockNumber, bytes32[] calldata blockHashes) external {
        require(msg.sender == aliasedPusher(), NotPusher());

        _receiveHashes(firstBlockNumber, blockHashes);
    }

    /// @inheritdoc IBuffer
    function pusher() public view returns (address) {
        return _pusher;
    }

    /// @notice The aliased address of the pusher contract on L2.
    function aliasedPusher() public view returns (address) {
        return AddressAliasHelper.applyL1ToL2Alias(_pusher);
    }
}
