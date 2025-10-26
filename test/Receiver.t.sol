// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Receiver} from "../src/contracts/Receiver.sol";
import {IReceiver} from "../src/contracts/interfaces/IReceiver.sol";
import {IBlockHashProver} from "../src/contracts/interfaces/IBlockHashProver.sol";
import {IBlockHashProverPointer} from "../src/contracts/interfaces/IBlockHashProverPointer.sol";
import {BLOCK_HASH_PROVER_POINTER_SLOT} from "../src/contracts/BlockHashProverPointer.sol";

contract ReceiverTest is Test {
    Receiver public receiver;

    address public publisher = makeAddr("publisher");

    function setUp() public {
        receiver = new Receiver();
    }

    function test_verifyBroadcastMessage() public {
        bytes32 message = "test";
    }
}

