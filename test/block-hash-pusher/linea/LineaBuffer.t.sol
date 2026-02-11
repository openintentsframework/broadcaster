// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {LineaBuffer} from "../../../src/contracts/block-hash-pusher/linea/LineaBuffer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IBuffer} from "../../../src/contracts/block-hash-pusher/interfaces/IBuffer.sol";
import {MockLineaMessageService} from "../mocks/MockLineaMessageService.sol";
import {IMessageService} from "@linea-contracts/messaging/interfaces/IMessageService.sol";

contract LineaBufferTest is Test {
    address public pusher = makeAddr("pusher");
    address public claimer = makeAddr("claimer");

    MockLineaMessageService public mockLineaMessageService;

    function setUp() public {
        mockLineaMessageService = new MockLineaMessageService();
    }

    function testFuzz_receiveHashes(uint16 batchSize, uint8 firstBlockNumber) public {
        vm.assume(batchSize > 0 && batchSize <= 8191);

        LineaBuffer buffer = new LineaBuffer(address(mockLineaMessageService), pusher);

        bytes32[] memory blockHashes = new bytes32[](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            blockHashes[i] = keccak256(abi.encode(i + 1));
        }

        bytes memory l2Calldata = abi.encodeCall(buffer.receiveHashes, (firstBlockNumber, blockHashes));

        vm.expectCall(address(buffer), l2Calldata);
        vm.expectEmit();
        emit IMessageService.MessageClaimed(keccak256(l2Calldata));
        vm.prank(claimer);
        mockLineaMessageService.claimMessage(pusher, address(buffer), 0.005 ether, 0, payable(claimer), l2Calldata, 0);
    }

    function testFuzz_receiveHashes_reverts_if_sender_is_not_linea_message_service(address notLineaMessageService)
        public
    {
        vm.assume(notLineaMessageService != address(mockLineaMessageService));
        LineaBuffer buffer = new LineaBuffer(address(mockLineaMessageService), pusher);

        bytes memory l2Calldata = abi.encodeCall(buffer.receiveHashes, (1, new bytes32[](1)));

        vm.expectRevert(abi.encodeWithSelector(LineaBuffer.InvalidSender.selector));
        vm.prank(notLineaMessageService);
        buffer.receiveHashes(1, new bytes32[](1));
    }

    function test_constructor_reverts_if_pusher_is_zero_address() public {
        vm.expectRevert(abi.encodeWithSelector(LineaBuffer.InvalidPusherAddress.selector));
        new LineaBuffer(address(mockLineaMessageService), address(0));
    }

    function test_constructor_reverts_if_l2_message_service_is_zero_address() public {
        vm.expectRevert(abi.encodeWithSelector(LineaBuffer.InvalidL2MessageServiceAddress.selector));
        new LineaBuffer(address(0), pusher);
    }

    function testFuzz_receiveHashes_reverts_if_sender_does_not_match_pusher(address notPusher) public {
        vm.assume(notPusher != pusher);
        LineaBuffer buffer = new LineaBuffer(address(mockLineaMessageService), pusher);

        bytes memory l2Calldata = abi.encodeCall(buffer.receiveHashes, (1, new bytes32[](1)));

        vm.expectRevert(abi.encodeWithSelector(LineaBuffer.SenderMismatch.selector));
        vm.prank(claimer);
        mockLineaMessageService.claimMessage(
            notPusher, address(buffer), 0.005 ether, 0, payable(claimer), l2Calldata, 0
        );
    }
}
