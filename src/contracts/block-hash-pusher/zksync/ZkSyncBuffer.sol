// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseBuffer} from "../BaseBuffer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";

contract ZkSyncBuffer is BaseBuffer, Ownable {
    address private _pusherAddress;

    error PusherAddressNotSet();

    event PusherAddressSet(address pusherAddress);

    constructor(address initialOwner_) Ownable(initialOwner_) {}

    function setPusherAddress(address pusherAddress_) external onlyOwner {
        _pusherAddress = pusherAddress_;

        emit PusherAddressSet(pusherAddress_);
        renounceOwnership();
    }

    function receiveHashes(uint256 firstBlockNumber, bytes32[] calldata blockHashes) external {
        if (_pusherAddress == address(0)) {
            revert PusherAddressNotSet();
        }

        if (msg.sender != aliasedPusher()) {
            revert NotPusher();
        }

        _receiveHashes(firstBlockNumber, blockHashes);
    }

    function pusher() public view returns (address) {
        return _pusherAddress;
    }

    function aliasedPusher() public view returns (address) {
        return AddressAliasHelper.applyL1ToL2Alias(_pusherAddress);
    }
}
