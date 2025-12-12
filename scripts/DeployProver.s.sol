// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";


import { console } from "forge-std/console.sol";
import { ParentToChildProver as ArbParentToChildProver } from "../src/contracts/provers/arbitrum/ParentToChildProver.sol";
import { BlockHashProverPointer } from "../src/contracts/BlockHashProverPointer.sol";


contract DeployBroadcaster is Script {
    function run() public {
        vm.startBroadcast();
        address outbox = 0x65f07C7D521164a4d5DaC6eB8Fac8DA067A3B78F;
        uint256 rootsSlot = 3;

        address owner = 0x9a56fFd72F4B526c523C733F1F74197A51c495E1;

        ArbParentToChildProver parentToChildProver = new ArbParentToChildProver(outbox, rootsSlot);
        BlockHashProverPointer blockHashProverPointer = new BlockHashProverPointer(owner);

        blockHashProverPointer.setImplementationAddress(address(parentToChildProver));

        vm.stopBroadcast();

        console.log("ParentToChildProver deployed to:", address(parentToChildProver));
        console.log("BlockHashProverPointer deployed to:", address(blockHashProverPointer));
    }
}