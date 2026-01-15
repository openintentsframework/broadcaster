// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ScrollPusher} from "../../../src/contracts/block-hash-pusher/scroll/ScrollPusher.sol";
import {IPusher} from "../../../src/contracts/block-hash-pusher/interfaces/IPusher.sol";
import {MockL1ScrollMessenger} from "../mocks/MockL1ScrollMessenger.sol";

contract ScrollPusherTest is Test {
    address public user = makeAddr("user");
    address public mockL1ScrollMessenger;
    address public buffer = makeAddr("buffer");

    address public l1ScrollMessengerAddress = 0x50c7d3e7f7c656493D1D76aaa1a836CedfCBB16A; // Address for Ethereum Sepolia

    function setUp() public {
        mockL1ScrollMessenger = address(new MockL1ScrollMessenger());
    }

    function test_pushHashes_fork() public {
        vm.createSelectFork(vm.envString("ETHEREUM_RPC_URL"));

        ScrollPusher scrollPusher = new ScrollPusher(l1ScrollMessengerAddress, buffer);

        bytes memory l2TransactionData =
            abi.encode(ScrollPusher.ScrollL2Transaction({gasLimit: 400000, refundAddress: msg.sender}));

        scrollPusher.pushHashes{value: 0.005 ether}(1, l2TransactionData);

        scrollPusher.pushHashes{value: 0.005 ether}(10, l2TransactionData);

        scrollPusher.pushHashes{value: 0.005 ether}(15, l2TransactionData);
    }

    function testFuzz_pushHashes(uint16 batchSize) public {
        vm.assume(batchSize > 0 && batchSize <= 8191);
        vm.roll(batchSize + 1);

        ScrollPusher scrollPusher = new ScrollPusher(mockL1ScrollMessenger, buffer);

        bytes memory l2TransactionData =
            abi.encode(ScrollPusher.ScrollL2Transaction({gasLimit: 0, refundAddress: address(0)}));

        vm.prank(user);
        scrollPusher.pushHashes(batchSize, l2TransactionData);
    }

    function testFuzz_pushHashes_invalidBatchSize(uint16 batchSize) public {
        vm.assume(batchSize == 0 || batchSize > 8191);
        vm.roll(uint32(batchSize) + 1); // uint32 to avoid overflow

        ScrollPusher scrollPusher = new ScrollPusher(mockL1ScrollMessenger, buffer);

        bytes memory l2TransactionData =
            abi.encode(ScrollPusher.ScrollL2Transaction({gasLimit: 0, refundAddress: address(0)}));

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IPusher.InvalidBatchSize.selector, batchSize));
        scrollPusher.pushHashes(batchSize, l2TransactionData);
    }

    function test_viewFunctions() public {
        ScrollPusher scrollPusher = new ScrollPusher(mockL1ScrollMessenger, buffer);
        assertEq(scrollPusher.l1ScrollMessenger(), mockL1ScrollMessenger);
        assertEq(scrollPusher.bufferAddress(), buffer);
    }
}
