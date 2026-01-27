// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { DeployBase } from "./DeployBase.s.sol";


import { console } from "forge-std/console.sol";
import {  Broadcaster } from "src/contracts/Broadcaster.sol";
import { ZkSyncBroadcaster } from "src/contracts/ZkSyncBroadcaster.sol";
import { Receiver } from "src/contracts/Receiver.sol";


contract Deploy is DeployBase {
    function run() public {


        string memory chainType = vm.envString("CHAIN_TYPE");

        address broadcasterAddress;

        vm.startBroadcast();

        if(chainType == "zksync") {
            address l1Messenger = 0x0000000000000000000000000000000000008008;

            broadcasterAddress = address(new ZkSyncBroadcaster(l1Messenger));

        }

        broadcasterAddress = address(new Broadcaster());
        Receiver receiver = new Receiver();
        vm.stopBroadcast();
        
        _writeContract("broadcaster", broadcasterAddress);
        _writeContract("receiver", address(receiver));
        
    }
}