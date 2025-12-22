// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { DeployBase } from "./DeployBase.s.sol";


import { console } from "forge-std/console.sol";
import {  Broadcaster } from "src/contracts/Broadcaster.sol";
import { Receiver } from "src/contracts/Receiver.sol";


contract Deploy is DeployBase {
    function run() public {
        vm.startBroadcast();
        Broadcaster broadcaster = new Broadcaster();
        Receiver receiver = new Receiver();
        vm.stopBroadcast();
        
        _writeContract("broadcaster", address(broadcaster));
        _writeContract("receiver", address(receiver));
        
    }
}