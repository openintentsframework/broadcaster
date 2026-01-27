// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { DeployBase } from "./DeployBase.s.sol";

import { console } from "forge-std/console.sol";
import {  Broadcaster } from "src/contracts/Broadcaster.sol";
import { ZkSyncBroadcaster } from "src/contracts/ZkSyncBroadcaster.sol";
import { Receiver } from "src/contracts/Receiver.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";


contract Deploy is DeployBase {

    // See https://github.com/Arachnid/deterministic-deployment-proxy
    // According to this research: https://ethereum-magicians.org/t/eip-7997-deterministic-factory-predeploy/24998/15
    // the Arachnid deployment proxy is the widest proxy available and its adoption suggests that a
    // more effect approach to support deterministic addresses is to enshrine it as a predeployed contract
    // through proposals like [RIP-7740](https://github.com/ethereum/RIPs/blob/master/RIPS/rip-7740.md).
    address public constant DEPLOYMENT_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

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