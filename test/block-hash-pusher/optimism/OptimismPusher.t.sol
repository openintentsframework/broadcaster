// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {OptimismPusher} from "../../../src/contracts/block-hash-pusher/optimism/OptimismPusher.sol";
import {IPusher} from "../../../src/contracts/block-hash-pusher/interfaces/IPusher.sol";
import {MockOpCrosschainDomainMessenger} from "../mocks/MockOpCrosschainDomainMessenger.sol";

contract OptimismPusherTest is Test {
    address public user = makeAddr("user");
    address public mockOpCrosschainDomainMessenger;
    address public buffer = makeAddr("buffer");

    address public l1CrossDomainMessengerProxyAddress = 0x58Cc85b8D04EA49cC6DBd3CbFFd00B4B8D6cb3ef; // Address for Ethereum Sepolia

    function setUp() public {
        mockOpCrosschainDomainMessenger = address(new MockOpCrosschainDomainMessenger());
    }

    function test_pushHashes_fork() public {
        vm.createSelectFork(vm.envString("ETHEREUM_RPC_URL"));

        OptimismPusher optimismPusher = new OptimismPusher(l1CrossDomainMessengerProxyAddress);

        bytes memory l2TransactionData = abi.encode(OptimismPusher.OptimismL2Transaction({gasLimit: 200000}));

        optimismPusher.pushHashes(buffer, block.number - 1, 1, l2TransactionData);

        optimismPusher.pushHashes(buffer, block.number - 10, 10, l2TransactionData);

        optimismPusher.pushHashes(buffer, block.number - 15, 15, l2TransactionData);

        optimismPusher.pushHashes(buffer, block.number - 1000, 10, l2TransactionData);

        optimismPusher.pushHashes(buffer, block.number - 8000, 20, l2TransactionData);
    }

    function testFuzz_pushHashes(uint16 batchSize) public {
        vm.assume(batchSize > 0 && batchSize <= 256);
        vm.roll(batchSize + 1);

        OptimismPusher optimismPusher = new OptimismPusher(mockOpCrosschainDomainMessenger);

        bytes memory l2TransactionData = abi.encode(OptimismPusher.OptimismL2Transaction({gasLimit: 200000}));

        vm.prank(user);
        optimismPusher.pushHashes(buffer, block.number - batchSize, batchSize, l2TransactionData);
    }

    function testFuzz_pushHashes_invalidBatchSize(uint16 batchSize) public {
        vm.assume(batchSize == 0 || batchSize > 8191);
        vm.roll(uint32(batchSize) + 1); // uint32 to avoid overflow

        OptimismPusher optimismPusher = new OptimismPusher(mockOpCrosschainDomainMessenger);

        bytes memory l2TransactionData = abi.encode(OptimismPusher.OptimismL2Transaction({gasLimit: 200000}));

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IPusher.InvalidBatch.selector, block.number - batchSize, batchSize));
        optimismPusher.pushHashes(buffer, block.number - batchSize, batchSize, l2TransactionData);
    }

    function test_constructor_reverts_if_l1_cross_domain_messenger_proxy_is_zero_address() public {
        vm.expectRevert(abi.encodeWithSelector(OptimismPusher.InvalidL1CrossDomainMessengerProxyAddress.selector));
        new OptimismPusher(address(0));
    }

    function test_viewFunctions() public {
        OptimismPusher optimismPusher = new OptimismPusher(mockOpCrosschainDomainMessenger);
        assertEq(optimismPusher.l1CrossDomainMessengerProxy(), mockOpCrosschainDomainMessenger);
    }
}
