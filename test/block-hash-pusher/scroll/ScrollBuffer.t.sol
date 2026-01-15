// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ScrollBuffer} from "../../../src/contracts/block-hash-pusher/scroll/ScrollBuffer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IBuffer} from "../../../src/contracts/block-hash-pusher/interfaces/IBuffer.sol";
import {MockL2ScrollMessenger} from "../mocks/MockL2ScrollMessenger.sol";
import {IScrollMessenger} from "@scroll-tech/scroll-contracts/libraries/IScrollMessenger.sol";

contract ScrollBufferTest is Test {
    address public pusher = makeAddr("pusher");
    address public owner = makeAddr("owner");

    address public relayer = makeAddr("relayer");

    MockL2ScrollMessenger public mockL2ScrollMessenger;

    function setUp() public {
        mockL2ScrollMessenger = new MockL2ScrollMessenger();
    }

    function testFuzz_receiveHashes(uint16 batchSize, uint8 firstBlockNumber) public {
        vm.assume(batchSize > 0 && batchSize <= 8191);

        ScrollBuffer buffer = new ScrollBuffer(address(mockL2ScrollMessenger), owner);

        bytes32[] memory blockHashes = new bytes32[](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            blockHashes[i] = keccak256(abi.encode(i + 1));
        }

        vm.prank(owner);
        buffer.setPusherAddress(pusher);

        bytes memory l2Calldata = abi.encodeCall(buffer.receiveHashes, (firstBlockNumber, blockHashes));

        vm.expectCall(address(buffer), l2Calldata);
        vm.expectEmit();
        emit IScrollMessenger.RelayedMessage(keccak256(l2Calldata));
        vm.prank(relayer);
        mockL2ScrollMessenger.relayMessage(pusher, address(buffer), 0, 0, l2Calldata);
    }

    function testFuzz_receiveHashes_reverts_if_sender_is_not_l2_scroll_messenger(address notL2ScrollMessenger) public {
        vm.assume(notL2ScrollMessenger != address(mockL2ScrollMessenger));
        ScrollBuffer buffer = new ScrollBuffer(address(mockL2ScrollMessenger), owner);

        bytes memory l2Calldata = abi.encodeCall(buffer.receiveHashes, (1, new bytes32[](1)));

        vm.expectRevert(abi.encodeWithSelector(ScrollBuffer.InvalidSender.selector));
        vm.prank(notL2ScrollMessenger);
        buffer.receiveHashes(1, new bytes32[](1));
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_receiveHashes_reverts_if_xDomainMessageSender_does_not_match_pusher(address notPusher) public {
        vm.assume(notPusher != pusher);
        ScrollBuffer buffer = new ScrollBuffer(address(mockL2ScrollMessenger), owner);

        bytes memory l2Calldata = abi.encodeCall(buffer.receiveHashes, (1, new bytes32[](1)));

        vm.expectEmit();
        emit IScrollMessenger.FailedRelayedMessage(keccak256(l2Calldata));
        vm.prank(relayer);
        mockL2ScrollMessenger.relayMessage(notPusher, address(buffer), 0, 0, l2Calldata);
    }

    function test_setPusherAddress() public {
        ScrollBuffer buffer = new ScrollBuffer(address(mockL2ScrollMessenger), owner);

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
        ScrollBuffer buffer = new ScrollBuffer(address(mockL2ScrollMessenger), owner);

        address notOwner = makeAddr("notOwner");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        buffer.setPusherAddress(pusher);
    }

    function test_setPusherAddress_reverts_if_pusher_address_is_invalid() public {
        ScrollBuffer buffer = new ScrollBuffer(address(mockL2ScrollMessenger), owner);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ScrollBuffer.InvalidPusherAddress.selector));
        buffer.setPusherAddress(address(0));
    }
}
