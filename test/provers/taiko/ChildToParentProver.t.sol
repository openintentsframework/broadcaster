// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ChildToParentProver} from "../../../src/contracts/provers/taiko/ChildToParentProver.sol";

contract ChildToParentProverTest is Test {
    ChildToParentProver public prover;

    // Taiko Mainnet addresses (update with actual deployment addresses)
    address public constant L2_SIGNAL_SERVICE = 0x1670000000000000000000000000000000000005; // Predeploy
    uint256 public constant CHECKPOINTS_SLOT = 3;
    uint256 public constant L2_CHAIN_ID = 167000; // Taiko Mainnet

    function setUp() public {
        // Deploy the prover
        prover = new ChildToParentProver(L2_SIGNAL_SERVICE, CHECKPOINTS_SLOT, L2_CHAIN_ID);
    }

    function test_constructor() public view {
        assertEq(prover.signalService(), L2_SIGNAL_SERVICE);
        assertEq(prover.checkpointsSlot(), CHECKPOINTS_SLOT);
        assertEq(prover.homeChainId(), L2_CHAIN_ID);
    }

    function test_version() public view {
        assertEq(prover.version(), 1);
    }

    function test_verifyTargetBlockHash_revertsOnHomeChain() public {
        // This test runs on a fork of L2 (home chain)
        vm.chainId(L2_CHAIN_ID);

        bytes memory input = abi.encode(bytes(""), uint48(0), bytes(""), bytes(""));

        vm.expectRevert(ChildToParentProver.CallOnHomeChain.selector);
        prover.verifyTargetBlockHash(bytes32(0), input);
    }

    function test_getTargetBlockHash_revertsOffHomeChain() public {
        // Simulate being on L1
        vm.chainId(1); // Ethereum Mainnet

        bytes memory input = abi.encode(uint48(0));

        vm.expectRevert(ChildToParentProver.CallNotOnHomeChain.selector);
        prover.getTargetBlockHash(input);
    }

    // TODO: Add integration tests with actual proofs once test data is generated
    // function test_verifyTargetBlockHash_success() public {
    //     // Fork Ethereum L1
    //     vm.createSelectFork(vm.envString("ETH_MAINNET_RPC_URL"));
    //     
    //     // Load pre-generated proof from test/proofs/taiko/l2-to-l1-proof.hex
    //     bytes memory input = abi.decode(vm.parseBytes(vm.readFile("test/proofs/taiko/l2-to-l1-proof.hex")), (bytes));
    //     bytes32 l2BlockHash = 0x...; // Expected L2 block hash
    //     
    //     bytes32 l1BlockHash = prover.verifyTargetBlockHash(l2BlockHash, input);
    //     assertEq(l1BlockHash, expectedL1BlockHash);
    // }

    // TODO: Add integration test for getTargetBlockHash with live L2 fork
    // function test_getTargetBlockHash_success() public {
    //     // Fork Taiko L2
    //     vm.createSelectFork(vm.envString("TAIKO_L2_RPC_URL"));
    //     
    //     uint48 l1BlockNumber = 12345; // Known checkpointed L1 block
    //     bytes memory input = abi.encode(l1BlockNumber);
    //     
    //     bytes32 l1BlockHash = prover.getTargetBlockHash(input);
    //     assertNotEq(l1BlockHash, bytes32(0));
    // }
}

