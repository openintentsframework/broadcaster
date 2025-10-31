// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ParentToChildProver} from "../../../src/contracts/provers/taiko/ParentToChildProver.sol";

contract ParentToChildProverTest is Test {
    ParentToChildProver public prover;

    // Taiko Mainnet addresses (update with actual deployment addresses)
    address public constant L1_SIGNAL_SERVICE = 0x9e0a24964e5397B566c1ed39258e21aB5E35C77C;
    uint256 public constant CHECKPOINTS_SLOT = 3;
    uint256 public constant L1_CHAIN_ID = 1; // Ethereum Mainnet

    function setUp() public {
        // Deploy the prover
        prover = new ParentToChildProver(L1_SIGNAL_SERVICE, CHECKPOINTS_SLOT, L1_CHAIN_ID);
    }

    function test_constructor() public view {
        assertEq(prover.signalService(), L1_SIGNAL_SERVICE);
        assertEq(prover.checkpointsSlot(), CHECKPOINTS_SLOT);
        assertEq(prover.homeChainId(), L1_CHAIN_ID);
    }

    function test_version() public view {
        assertEq(prover.version(), 1);
    }

    function test_verifyTargetBlockHash_revertsOnHomeChain() public {
        // This test runs on a fork of L1 (home chain)
        vm.chainId(L1_CHAIN_ID);

        bytes memory input = abi.encode(bytes(""), uint48(0), bytes(""), bytes(""));

        vm.expectRevert(ParentToChildProver.CallOnHomeChain.selector);
        prover.verifyTargetBlockHash(bytes32(0), input);
    }

    function test_getTargetBlockHash_revertsOffHomeChain() public {
        // Simulate being on L2
        vm.chainId(167000); // Taiko L2 chain ID

        bytes memory input = abi.encode(uint48(0));

        vm.expectRevert(ParentToChildProver.CallNotOnHomeChain.selector);
        prover.getTargetBlockHash(input);
    }

    // TODO: Add integration tests with actual proofs once test data is generated
    // function test_verifyTargetBlockHash_success() public {
    //     // Fork Taiko L2
    //     vm.createSelectFork(vm.envString("TAIKO_L2_RPC_URL"));
    //     
    //     // Load pre-generated proof from test/proofs/taiko/l1-to-l2-proof.hex
    //     bytes memory input = abi.decode(vm.parseBytes(vm.readFile("test/proofs/taiko/l1-to-l2-proof.hex")), (bytes));
    //     bytes32 l1BlockHash = 0x...; // Expected L1 block hash
    //     
    //     bytes32 l2BlockHash = prover.verifyTargetBlockHash(l1BlockHash, input);
    //     assertEq(l2BlockHash, expectedL2BlockHash);
    // }

    // TODO: Add integration test for getTargetBlockHash with live L1 fork
    // function test_getTargetBlockHash_success() public {
    //     // Fork Ethereum L1
    //     vm.createSelectFork(vm.envString("ETH_MAINNET_RPC_URL"));
    //     
    //     uint48 l2BlockNumber = 12345; // Known checkpointed L2 block
    //     bytes memory input = abi.encode(l2BlockNumber);
    //     
    //     bytes32 l2BlockHash = prover.getTargetBlockHash(input);
    //     assertNotEq(l2BlockHash, bytes32(0));
    // }
}

