// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {LineaPusher} from "../../../src/contracts/block-hash-pusher/linea/LineaPusher.sol";
import {IPusher} from "../../../src/contracts/block-hash-pusher/interfaces/IPusher.sol";
import {MockLineaMessageService} from "../mocks/MockLineaMessageService.sol";
import {IMessageService} from "@linea-contracts/messaging/interfaces/IMessageService.sol";

contract LineaPusherTest is Test {
    address public user = makeAddr("user");
    address public mockLineaRollup;
    address public buffer = makeAddr("buffer");

    address public lineaRollupAddress = 0xB218f8A4Bc926cF1cA7b3423c154a0D627Bdb7E5; // Address for Ethereum Sepolia

    function setUp() public {
        mockLineaRollup = address(new MockLineaMessageService());
    }

    function test_pushHashes_fork() public {
        vm.createSelectFork(vm.envString("ETHEREUM_RPC_URL"));

        LineaPusher lineaPusher = new LineaPusher(lineaRollupAddress);

        bytes memory l2TransactionData = abi.encode(LineaPusher.LineaL2Transaction({_fee: 0.005 ether}));

        lineaPusher.pushHashes{value: 0.005 ether}(buffer, block.number - 1, 1, l2TransactionData);

        lineaPusher.pushHashes{value: 0.005 ether}(buffer, block.number - 10, 10, l2TransactionData);

        lineaPusher.pushHashes{value: 0.005 ether}(buffer, block.number - 15, 15, l2TransactionData);

        lineaPusher.pushHashes{value: 0.005 ether}(buffer, block.number - 1000, 10, l2TransactionData);

        lineaPusher.pushHashes{value: 0.005 ether}(buffer, block.number - 8000, 20, l2TransactionData);

        // push hashes with _fee < msg.value should revert
        vm.expectRevert(abi.encodeWithSelector(IMessageService.ValueSentTooLow.selector));
        lineaPusher.pushHashes{value: 0.004 ether}(buffer, block.number - 1, 1, l2TransactionData);
    }

    function testFuzz_pushHashes(uint16 batchSize) public {
        vm.assume(batchSize > 0 && batchSize <= 256);
        vm.roll(batchSize + 1);

        LineaPusher lineaPusher = new LineaPusher(mockLineaRollup);

        bytes memory l2TransactionData = abi.encode(LineaPusher.LineaL2Transaction({_fee: 0.005 ether}));

        vm.deal(user, 0.005 ether);
        vm.prank(user);
        lineaPusher.pushHashes{value: 0.005 ether}(buffer, block.number - batchSize, batchSize, l2TransactionData);
    }

    function testFuzz_pushHashes_reverts_if_value_too_low(uint16 batchSize) public {
        vm.assume(batchSize > 0 && batchSize <= 256);
        vm.roll(batchSize + 1);

        LineaPusher lineaPusher = new LineaPusher(mockLineaRollup);

        bytes memory l2TransactionData = abi.encode(LineaPusher.LineaL2Transaction({_fee: 0.005 ether}));

        vm.deal(user, 0.005 ether);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IMessageService.ValueSentTooLow.selector));
        lineaPusher.pushHashes{value: 0.001 ether}(buffer, block.number - batchSize, batchSize, l2TransactionData);
    }

    function testFuzz_pushHashes_invalidBatchSize(uint16 batchSize) public {
        vm.assume(batchSize == 0 || batchSize > 8191);
        vm.roll(uint32(batchSize) + 1); // uint32 to avoid overflow

        LineaPusher lineaPusher = new LineaPusher(mockLineaRollup);

        bytes memory l2TransactionData = abi.encode(LineaPusher.LineaL2Transaction({_fee: 0.005 ether}));

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IPusher.InvalidBatch.selector, block.number - batchSize, batchSize));
        lineaPusher.pushHashes(buffer, block.number - batchSize, batchSize, l2TransactionData);
    }

    function test_constructor_reverts_if_rollup_is_zero_address() public {
        vm.expectRevert(abi.encodeWithSelector(LineaPusher.InvalidLineaRollupAddress.selector));
        new LineaPusher(address(0));
    }

    function test_viewFunctions() public {
        LineaPusher lineaPusher = new LineaPusher(mockLineaRollup);
        assertEq(lineaPusher.lineaRollup(), mockLineaRollup);
    }
}
