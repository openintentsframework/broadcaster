// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ZkSyncBuffer} from "../../../src/contracts/block-hash-pusher/zksync/ZkSyncBuffer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {IBuffer} from "../../../src/contracts/block-hash-pusher/interfaces/IBuffer.sol";

contract ZkSyncBufferTest is Test {
    address public pusher = makeAddr("pusher");
    address public owner = makeAddr("owner");

    function setUp() public {}

    function testFuzz_receiveHashes(uint16 batchSize, uint8 firstBlockNumber) public {
        vm.assume(batchSize > 0 && batchSize <= 8191);

        ZkSyncBuffer buffer = new ZkSyncBuffer(owner);

        bytes32[] memory blockHashes = new bytes32[](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            blockHashes[i] = keccak256(abi.encode(i + 1));
        }

        vm.prank(owner);
        buffer.setPusherAddress(pusher);

        address aliasedPusher = AddressAliasHelper.applyL1ToL2Alias(pusher);
        assertEq(buffer.pusher(), pusher);
        assertEq(buffer.aliasedPusher(), aliasedPusher);

        vm.prank(aliasedPusher);
        buffer.receiveHashes(firstBlockNumber, blockHashes);
    }

    function test_receiveHashes_reverts_if_pusher_not_set() public {
        ZkSyncBuffer buffer = new ZkSyncBuffer(owner);

        vm.expectRevert(abi.encodeWithSelector(ZkSyncBuffer.PusherAddressNotSet.selector));
        buffer.receiveHashes(1, new bytes32[](1));
    }

    function testFuzz_receiveHashes_reverts_if_not_pusher(address notPusher) public {
        vm.assume(notPusher != pusher);

        ZkSyncBuffer buffer = new ZkSyncBuffer(owner);

        vm.prank(owner);
        buffer.setPusherAddress(pusher);

        address aliasedPusher = AddressAliasHelper.applyL1ToL2Alias(pusher);
        assertEq(buffer.pusher(), pusher);
        assertEq(buffer.aliasedPusher(), aliasedPusher);

        bytes32[] memory blockHashes = new bytes32[](1);
        blockHashes[0] = keccak256(abi.encode(1));

        vm.prank(notPusher);
        vm.expectRevert(abi.encodeWithSelector(IBuffer.NotPusher.selector));
        buffer.receiveHashes(1, blockHashes);
    }

    function test_setPusherAddress() public {
        ZkSyncBuffer buffer = new ZkSyncBuffer(owner);

        assertEq(buffer.pusher(), address(0));
        assertEq(buffer.owner(), owner);

        vm.prank(owner);
        buffer.setPusherAddress(pusher);
        assertEq(buffer.pusher(), pusher);
        assertEq(buffer.owner(), address(0));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        buffer.setPusherAddress(pusher);
    }

    function test_setPusherAddress_reverts_if_not_owner() public {
        ZkSyncBuffer buffer = new ZkSyncBuffer(owner);

        address notOwner = makeAddr("notOwner");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        buffer.setPusherAddress(pusher);
    }

    function test_setPusherAddress_reverts_if_pusher_address_is_invalid() public {
        ZkSyncBuffer buffer = new ZkSyncBuffer(owner);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZkSyncBuffer.InvalidPusherAddress.selector));
        buffer.setPusherAddress(address(0));
    }
}
