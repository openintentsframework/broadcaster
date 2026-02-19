// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, Vm} from "forge-std/Test.sol";
import {OptimismBuffer} from "../../../src/contracts/block-hash-pusher/optimism/OptimismBuffer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IBuffer} from "../../../src/contracts/block-hash-pusher/interfaces/IBuffer.sol";
import {MockOpCrosschainDomainMessenger} from "../mocks/MockOpCrosschainDomainMessenger.sol";
import {ICrossDomainMessenger} from "@eth-optimism/contracts/libraries/bridge/ICrossDomainMessenger.sol";

contract OptimismBufferTest is Test {
    address public pusher = makeAddr("pusher");

    address public relayer = makeAddr("relayer");

    MockOpCrosschainDomainMessenger public mockOpCrosschainDomainMessenger;

    function setUp() public {
        mockOpCrosschainDomainMessenger = new MockOpCrosschainDomainMessenger();
    }

    function testFuzz_receiveHashes(uint16 batchSize, uint8 firstBlockNumber) public {
        vm.assume(batchSize > 0 && batchSize <= 8191);

        OptimismBuffer buffer = new OptimismBuffer(address(mockOpCrosschainDomainMessenger), pusher);

        bytes32[] memory blockHashes = new bytes32[](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            blockHashes[i] = keccak256(abi.encode(i + 1));
        }

        bytes memory l2Calldata = abi.encodeCall(buffer.receiveHashes, (firstBlockNumber, blockHashes));

        vm.expectCall(address(buffer), l2Calldata);
        if (firstBlockNumber == 0) {
            vm.expectRevert("Message sending failed");
        }
        vm.prank(relayer);
        mockOpCrosschainDomainMessenger.relayMessage(address(buffer), pusher, l2Calldata, 0);
    }

    function test_receiveHashes_does_not_emit_event_when_no_hashes_written() public {
        OptimismBuffer buffer = new OptimismBuffer(address(mockOpCrosschainDomainMessenger), pusher);

        bytes32[] memory blockHashes = new bytes32[](5);
        for (uint256 i = 0; i < 5; i++) {
            blockHashes[i] = keccak256(abi.encode(i + 1));
        }

        bytes memory l2Calldata = abi.encodeCall(buffer.receiveHashes, (1, blockHashes));

        // First push: should emit
        vm.expectEmit();
        emit IBuffer.BlockHashesPushed(1, 5);
        vm.prank(relayer);
        mockOpCrosschainDomainMessenger.relayMessage(address(buffer), pusher, l2Calldata, 0);
        assertEq(buffer.newestBlockNumber(), 5);

        // Duplicate push: should NOT emit BlockHashesPushed
        vm.recordLogs();
        vm.prank(relayer);
        mockOpCrosschainDomainMessenger.relayMessage(address(buffer), pusher, l2Calldata, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != IBuffer.BlockHashesPushed.selector, "Unexpected BlockHashesPushed event");
        }
        assertEq(buffer.newestBlockNumber(), 5);
    }

    function test_constructor_reverts_if_pusher_is_zero_address() public {
        vm.expectRevert(abi.encodeWithSelector(OptimismBuffer.InvalidPusherAddress.selector));
        new OptimismBuffer(address(mockOpCrosschainDomainMessenger), address(0));
    }

    function test_constructor_reverts_if_l2_scroll_messenger_is_zero_address() public {
        vm.expectRevert(abi.encodeWithSelector(OptimismBuffer.InvalidL2CrossDomainMessengerAddress.selector));
        new OptimismBuffer(address(0), pusher);
    }

    function testFuzz_receiveHashes_reverts_if_sender_is_not_l2_cross_domain_messenger(address notOpCrosschainDomainMessenger)
        public
    {
        vm.assume(notOpCrosschainDomainMessenger != address(mockOpCrosschainDomainMessenger));
        OptimismBuffer buffer = new OptimismBuffer(address(mockOpCrosschainDomainMessenger), pusher);

        bytes memory l2Calldata = abi.encodeCall(buffer.receiveHashes, (1, new bytes32[](1)));

        vm.expectRevert(abi.encodeWithSelector(OptimismBuffer.InvalidSender.selector));
        vm.prank(notOpCrosschainDomainMessenger);
        buffer.receiveHashes(1, new bytes32[](1));
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_receiveHashes_reverts_if_xDomainMessageSender_does_not_match_pusher(address notPusher) public {
        vm.assume(notPusher != pusher);
        OptimismBuffer buffer = new OptimismBuffer(address(mockOpCrosschainDomainMessenger), pusher);

        bytes memory l2Calldata = abi.encodeCall(buffer.receiveHashes, (1, new bytes32[](1)));

        vm.expectRevert();
        vm.prank(relayer);
        mockOpCrosschainDomainMessenger.relayMessage(address(buffer), notPusher, l2Calldata, 0);
    }
}
