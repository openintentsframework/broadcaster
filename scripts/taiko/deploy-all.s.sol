// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Broadcaster } from "../../src/contracts/Broadcaster.sol";
import { Receiver } from "../../src/contracts/Receiver.sol";
import { BlockHashProverPointer } from "../../src/contracts/BlockHashProverPointer.sol";

contract DeployAll is Script {
    function run() public {
        address owner = vm.envAddress("TAIKO_DEPLOYER_ADDRESS");
        
        vm.startBroadcast();
        
        Broadcaster broadcaster = new Broadcaster();
        Receiver receiver = new Receiver();
        BlockHashProverPointer pointer = new BlockHashProverPointer(owner);
        
        vm.stopBroadcast();

        console.log("Broadcaster:", address(broadcaster));
        console.log("Receiver:", address(receiver));
        console.log("BlockHashProverPointer:", address(pointer));
    }
}

