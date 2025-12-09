// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";


import { console } from "forge-std/console.sol";
import {  Broadcaster } from "../src/contracts/Broadcaster.sol";
import { Receiver } from "../src/contracts/Receiver.sol";


contract DeployBroadcaster is Script {
    function run() public {
        vm.startBroadcast();
        //Broadcaster broadcaster = new Broadcaster();
        Receiver receiver = new Receiver();
        vm.stopBroadcast();

        //console.log("Broadcaster deployed to:", address(broadcaster));
        console.log("Receiver deployed to:", address(receiver));
    }
}