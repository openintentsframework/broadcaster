// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Broadcaster } from "../../src/contracts/Broadcaster.sol";

/// @notice Broadcast a message on L1 (Taiko Parent Chain)
/// @dev This script broadcasts a message using the Broadcaster contract on L1
contract BroadcastL1Message is Script {
    function run() public {
        // L1 Broadcaster address
        address broadcasterAddress = 0x6BdBb69660E6849b98e8C524d266a0005D3655F7;
        
        // Define your message here - change this to your desired message
        bytes32 message = keccak256("Hello from Taiko L1!");
        
        vm.startBroadcast();
        
        // Broadcast the message
        Broadcaster broadcaster = Broadcaster(broadcasterAddress);
        broadcaster.broadcastMessage(message);
        
        vm.stopBroadcast();

        console.log("=== L1 Message Broadcast Complete ===");
        console.log("Broadcaster address:", broadcasterAddress);
        console.log("Message hash:");
        console.logBytes32(message);
        console.log("Publisher:", msg.sender);
    }
}

