// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Broadcaster } from "../../src/contracts/Broadcaster.sol";

/// @notice Broadcast a message on L2 (Taiko Child Chain)
/// @dev This script broadcasts a message using the Broadcaster contract on L2
contract BroadcastL2Message is Script {
    function run() public {
        address broadcasterAddress = vm.envAddress("L2_BROADCASTER");
        bytes32 message = keccak256(abi.encodePacked("Message", block.timestamp, msg.sender));
        
        vm.startBroadcast();
        Broadcaster(broadcasterAddress).broadcastMessage(message);
        vm.stopBroadcast();

        console.log("Broadcaster:", broadcasterAddress);
        console.logBytes32(message);
    }
}

