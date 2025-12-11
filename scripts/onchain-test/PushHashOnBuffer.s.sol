// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";


import { console } from "forge-std/console.sol";
import { BufferMock } from "../../test/mocks/BufferMock.sol";

contract Deploy is Script {
    function run() public {
        address bufferAddress = 0x40F58Bd4616a6E76021F1481154DB829953BF01B;

        bytes32[] memory blockHashes = new bytes32[](1);
        blockHashes[0] = bytes32(0x0f5aa3affcc16f8b83665f602d9497dff5fbd7b104e45136df7aa578cd9455ce);

        vm.startBroadcast();
        BufferMock buffer = BufferMock(bufferAddress);
        buffer.receiveHashes(0x91fdd9, blockHashes);
        vm.stopBroadcast();
    }
}