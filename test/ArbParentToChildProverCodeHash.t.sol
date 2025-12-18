// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console, Test} from "forge-std/Test.sol";

import {ParentToChildProver as ArbParentToChildProver} from "../src/contracts/provers/arbitrum/ParentToChildProver.sol";

contract ArbParentToChildProverCodeHashTest is Test {
    function test_codehash_matches_pointer_payload() public {
        address outbox = 0x65f07C7D521164a4d5DaC6eB8Fac8DA067A3B78F;
        uint256 rootsSlot = 3;

        bytes32 expected = 0xbb6c4d52337fbbdf5d35ffcb30100515fe0ce093e23c3de9bac4c3814240380b;

        ArbParentToChildProver proverMainnet = new ArbParentToChildProver(outbox, rootsSlot, 1);
        ArbParentToChildProver proverSepolia = new ArbParentToChildProver(outbox, rootsSlot, 11155111);

        console.logBytes32(address(proverMainnet).codehash);
        console.logBytes32(address(proverSepolia).codehash);

        assertEq(address(proverMainnet).codehash == expected || address(proverSepolia).codehash == expected, true);
    }
}

