// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, Vm} from "forge-std/Test.sol";
import {ScrollBuffer} from "../../../src/contracts/block-hash-pusher/scroll/ScrollBuffer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IBuffer} from "../../../src/contracts/block-hash-pusher/interfaces/IBuffer.sol";
import {MockL2ScrollMessenger} from "../mocks/MockL2ScrollMessenger.sol";
import {IScrollMessenger} from "@scroll-tech/scroll-contracts/libraries/IScrollMessenger.sol";

contract ScrollBufferTest is Test {
    address public pusher = makeAddr("pusher");

    address public relayer = makeAddr("relayer");

    MockL2ScrollMessenger public mockL2ScrollMessenger;

    function setUp() public {
        mockL2ScrollMessenger = new MockL2ScrollMessenger();
    }

    function testFuzz_receiveHashes(uint16 batchSize, uint8 firstBlockNumber) public {
        vm.assume(batchSize > 0 && batchSize <= 8191);

        ScrollBuffer buffer = new ScrollBuffer(address(mockL2ScrollMessenger), pusher);

        bytes32[] memory blockHashes = new bytes32[](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            blockHashes[i] = keccak256(abi.encode(i + 1));
        }

        bytes memory l2Calldata = abi.encodeCall(buffer.receiveHashes, (firstBlockNumber, blockHashes));

        vm.expectCall(address(buffer), l2Calldata);
        if (firstBlockNumber == 0) {
            vm.expectEmit();
            emit IScrollMessenger.FailedRelayedMessage(keccak256(l2Calldata));
        } else {
            vm.expectEmit();
            emit IScrollMessenger.RelayedMessage(keccak256(l2Calldata));
        }
        vm.prank(relayer);
        mockL2ScrollMessenger.relayMessage(pusher, address(buffer), 0, 0, l2Calldata);
    }

    function test_receiveHashes_does_not_emit_event_when_no_hashes_written() public {
        ScrollBuffer buffer = new ScrollBuffer(address(mockL2ScrollMessenger), pusher);

        bytes32[] memory blockHashes = new bytes32[](5);
        for (uint256 i = 0; i < 5; i++) {
            blockHashes[i] = keccak256(abi.encode(i + 1));
        }

        bytes memory l2Calldata = abi.encodeCall(buffer.receiveHashes, (1, blockHashes));

        // First push: should emit
        vm.expectEmit();
        emit IBuffer.BlockHashesPushed(1, 5);
        vm.prank(relayer);
        mockL2ScrollMessenger.relayMessage(pusher, address(buffer), 0, 0, l2Calldata);
        assertEq(buffer.newestBlockNumber(), 5);

        // Duplicate push: should NOT emit BlockHashesPushed
        vm.recordLogs();
        vm.prank(relayer);
        mockL2ScrollMessenger.relayMessage(pusher, address(buffer), 0, 0, l2Calldata);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != IBuffer.BlockHashesPushed.selector, "Unexpected BlockHashesPushed event");
        }
        assertEq(buffer.newestBlockNumber(), 5);
    }

    function test_constructor_reverts_if_pusher_is_zero_address() public {
        vm.expectRevert(abi.encodeWithSelector(ScrollBuffer.InvalidPusherAddress.selector));
        new ScrollBuffer(address(mockL2ScrollMessenger), address(0));
    }

    function test_constructor_reverts_if_l2_scroll_messenger_is_zero_address() public {
        vm.expectRevert(abi.encodeWithSelector(ScrollBuffer.InvalidL2ScrollMessengerAddress.selector));
        new ScrollBuffer(address(0), pusher);
    }

    function testFuzz_receiveHashes_reverts_if_sender_is_not_l2_scroll_messenger(address notL2ScrollMessenger) public {
        vm.assume(notL2ScrollMessenger != address(mockL2ScrollMessenger));
        ScrollBuffer buffer = new ScrollBuffer(address(mockL2ScrollMessenger), pusher);

        bytes memory l2Calldata = abi.encodeCall(buffer.receiveHashes, (1, new bytes32[](1)));

        vm.expectRevert(abi.encodeWithSelector(ScrollBuffer.InvalidSender.selector));
        vm.prank(notL2ScrollMessenger);
        buffer.receiveHashes(1, new bytes32[](1));
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_receiveHashes_reverts_if_xDomainMessageSender_does_not_match_pusher(address notPusher) public {
        vm.assume(notPusher != pusher);
        ScrollBuffer buffer = new ScrollBuffer(address(mockL2ScrollMessenger), pusher);

        bytes memory l2Calldata = abi.encodeCall(buffer.receiveHashes, (1, new bytes32[](1)));

        vm.expectEmit();
        emit IScrollMessenger.FailedRelayedMessage(keccak256(l2Calldata));
        vm.prank(relayer);
        mockL2ScrollMessenger.relayMessage(notPusher, address(buffer), 0, 0, l2Calldata);
    }
}
