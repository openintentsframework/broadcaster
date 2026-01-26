// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ZkSyncBuffer} from "../../../src/contracts/block-hash-pusher/zksync/ZkSyncBuffer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {IBuffer} from "../../../src/contracts/block-hash-pusher/interfaces/IBuffer.sol";

contract ZkSyncBufferTest is Test {
    address public pusher = makeAddr("pusher");

    function setUp() public {}

    function testFuzz_receiveHashes(uint16 batchSize, uint8 firstBlockNumber) public {
        vm.assume(batchSize > 0 && batchSize <= 8191);

        ZkSyncBuffer buffer = new ZkSyncBuffer(pusher);

        bytes32[] memory blockHashes = new bytes32[](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            blockHashes[i] = keccak256(abi.encode(i + 1));
        }

        address aliasedPusher = AddressAliasHelper.applyL1ToL2Alias(pusher);
        assertEq(buffer.pusher(), pusher);
        assertEq(buffer.aliasedPusher(), aliasedPusher);

        vm.prank(aliasedPusher);
        buffer.receiveHashes(firstBlockNumber, blockHashes);
    }

    function testFuzz_receiveHashes_reverts_if_not_pusher(address notPusher) public {
        vm.assume(notPusher != pusher);
        address aliasedPusher = AddressAliasHelper.applyL1ToL2Alias(pusher);
        vm.assume(notPusher != aliasedPusher);

        ZkSyncBuffer buffer = new ZkSyncBuffer(pusher);

        assertEq(buffer.pusher(), pusher);
        assertEq(buffer.aliasedPusher(), aliasedPusher);

        bytes32[] memory blockHashes = new bytes32[](1);
        blockHashes[0] = keccak256(abi.encode(1));

        vm.prank(notPusher);
        vm.expectRevert(abi.encodeWithSelector(IBuffer.NotPusher.selector));
        buffer.receiveHashes(1, blockHashes);
    }
}
