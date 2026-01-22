// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ZkSyncPusher} from "../../../src/contracts/block-hash-pusher/zksync/ZkSyncPusher.sol";
import {IPusher} from "../../../src/contracts/block-hash-pusher/interfaces/IPusher.sol";
import {MockZkSyncMailbox} from "../mocks/MockZkSyncMailbox.sol";

contract ZkSyncPusherTest is Test {
    error GasPerPubdataMismatch();
    uint256 public constant REQUIRED_L2_GAS_PRICE_PER_PUBDATA = 800;

    address public user = makeAddr("user");
    address public mockZkSyncMailbox;
    address public buffer = makeAddr("buffer");

    address public zkSyncMailBoxAddress = 0x9A6DE0f62Aa270A8bCB1e2610078650D539B1Ef9; // Address for Ethereum Sepolia

    function setUp() public {
        mockZkSyncMailbox = address(new MockZkSyncMailbox());
    }

    function test_pushHashes_fork() public {
        vm.createSelectFork(vm.envString("ETHEREUM_RPC_URL"));

        ZkSyncPusher zkSyncPusher = new ZkSyncPusher(zkSyncMailBoxAddress, buffer);

        bytes memory l2TransactionData = abi.encode(
            ZkSyncPusher.L2Transaction({
                l2GasLimit: 357901,
                l2GasPerPubdataByteLimit: REQUIRED_L2_GAS_PRICE_PER_PUBDATA,
                refundRecipient: address(0)
            })
        );

        zkSyncPusher.pushHashes{value: 0.005 ether}(block.number - 1, 1, l2TransactionData);

        zkSyncPusher.pushHashes{value: 0.005 ether}(block.number - 10, 10, l2TransactionData);

        zkSyncPusher.pushHashes{value: 0.005 ether}(block.number - 15, 15, l2TransactionData);

        zkSyncPusher.pushHashes{value: 0.005 ether}(block.number - 1000, 10, l2TransactionData);

        zkSyncPusher.pushHashes{value: 0.005 ether}(block.number - 8000, 20, l2TransactionData);
    }

    function test_pushHashes_fork_reverts_with_incorrect_l2_gas_price_per_pubdata() public {
        vm.createSelectFork(vm.envString("ETHEREUM_RPC_URL"));

        ZkSyncPusher zkSyncPusher = new ZkSyncPusher(zkSyncMailBoxAddress, buffer);

        bytes memory l2TransactionData = abi.encode(
            ZkSyncPusher.L2Transaction({
                l2GasLimit: 357901,
                l2GasPerPubdataByteLimit: REQUIRED_L2_GAS_PRICE_PER_PUBDATA + 1,
                refundRecipient: address(0)
            })
        );

        vm.expectRevert(GasPerPubdataMismatch.selector);
        zkSyncPusher.pushHashes{value: 50000000000000000}(block.number - 1, 1, l2TransactionData);
    }

    function testFuzz_pushHashes(uint16 batchSize) public {
        vm.assume(batchSize > 0 && batchSize <= 256);
        vm.roll(batchSize + 1);

        ZkSyncPusher zkSyncPusher = new ZkSyncPusher(mockZkSyncMailbox, buffer);

        bytes memory l2TransactionData = abi.encode(
            ZkSyncPusher.L2Transaction({
                l2GasLimit: 1000000,
                l2GasPerPubdataByteLimit: REQUIRED_L2_GAS_PRICE_PER_PUBDATA,
                refundRecipient: address(0)
            })
        );

        vm.prank(user);
        zkSyncPusher.pushHashes(block.number - batchSize, batchSize, l2TransactionData);
    }

    function testFuzz_pushHashes_invalidBatchSize(uint16 batchSize) public {
        vm.assume(batchSize == 0 || batchSize > 8191);
        vm.roll(uint32(batchSize) + 1); // uint32 to avoid overflow

        ZkSyncPusher zkSyncPusher = new ZkSyncPusher(mockZkSyncMailbox, buffer);

        bytes memory l2TransactionData = abi.encode(
            ZkSyncPusher.L2Transaction({
                l2GasLimit: 1000000,
                l2GasPerPubdataByteLimit: REQUIRED_L2_GAS_PRICE_PER_PUBDATA,
                refundRecipient: address(0)
            })
        );

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IPusher.InvalidBatch.selector, block.number - batchSize, batchSize));
        zkSyncPusher.pushHashes(block.number - batchSize, batchSize, l2TransactionData);
    }

    function test_viewFunctions() public {
        ZkSyncPusher zkSyncPusher = new ZkSyncPusher(mockZkSyncMailbox, buffer);
        assertEq(zkSyncPusher.zkSyncDiamond(), mockZkSyncMailbox);
        assertEq(zkSyncPusher.bufferAddress(), buffer);
    }
}
