// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Broadcaster } from "../../src/contracts/Broadcaster.sol";

/// @notice Broadcast a message on L2 (Taiko Child Chain)
/// @dev This script broadcasts a message using the Broadcaster contract on L2
contract BroadcastL2Message is Script {
    function run() public {
        // L2 Broadcaster address
        address broadcasterAddress = 0x6BdBb69660E6849b98e8C524d266a0005D3655F7;
        
        // Define your message here - change this to your desired message
        bytes32 message = keccak256("Hello from Taiko L2!");
        
        vm.startBroadcast();
        
        // Broadcast the message
        Broadcaster broadcaster = Broadcaster(broadcasterAddress);
        broadcaster.broadcastMessage(message);
        
        vm.stopBroadcast();

        console.log("=== L2 Message Broadcast Complete ===");
        console.log("Broadcaster address:", broadcasterAddress);
        console.log("Message hash:");
        console.logBytes32(message);
        console.log("Publisher:", msg.sender);
    }
}

