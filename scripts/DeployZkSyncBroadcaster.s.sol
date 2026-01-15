// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script } from "forge-std/Script.sol";


import { console } from "forge-std/console.sol";
import {  ZkSyncBroadcaster } from "../src/contracts/ZkSyncBroadcaster.sol";
import { Receiver } from "../src/contracts/Receiver.sol";


contract DeployBroadcaster is Script {
    function run() public {
        vm.startBroadcast();
        ZkSyncBroadcaster broadcaster = new ZkSyncBroadcaster(0x0000000000000000000000000000000000008008);
        //Receiver receiver = new Receiver();
        vm.stopBroadcast();

        console.log("ZkSyncBroadcaster deployed to:", address(broadcaster));
        //console.log("Receiver deployed to:", address(receiver));
    }
}