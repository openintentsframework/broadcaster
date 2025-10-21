//SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console, Test} from "forge-std/Test.sol";

import {ParentToChildProver} from "../../../src/contracts/provers/zksync/ParentToChildProver.sol";

contract ZkSyncParentToChildProverTest is Test {
    function setUp() public {
        vm.createSelectFork(vm.envString("ZKSYNC_RPC_URL"));

        bytes memory latestBatch = vm.rpc("zks_L1BatchNumber", "[]");

        uint256 latestBatchNumber =
            abi.decode(abi.encodePacked(new bytes(32 - latestBatch.length), latestBatch), (uint256));

        bytes32[] memory storageKeys = new bytes32[](1);
        storageKeys[0] = 0xed71b28e74e0c345ccea429109d91e298de836bf32290bfda4210d76bb646cd7;

        address account = 0x0000000000000000000000000000000000008003;

        string memory params = string(
            abi.encodePacked(
                "[\"",
                vm.toString(account),
                "\",[\"",
                vm.toString(storageKeys[0]),
                "\"],",
                vm.toString(latestBatchNumber - 150),
                "]"
            )
        );

        console.log("params: ");
        console.log(params);

        bytes memory storageProof = vm.rpc("zks_getProof", params);

        console.log("storageProof: ");
        console.logBytes(storageProof);
    }

    function test_verifyTargetBlockHash() public {}
}
