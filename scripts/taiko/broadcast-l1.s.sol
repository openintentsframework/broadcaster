// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Broadcaster } from "../../src/contracts/Broadcaster.sol";

/// @notice Broadcast a message on L1 (Taiko Parent Chain)
/// @dev This script broadcasts a message using the Broadcaster contract on L1
contract BroadcastL1Message is Script {
    function run() public {
        address broadcasterAddress = vm.envAddress("L1_BROADCASTER");
        bytes32 message = keccak256(abi.encodePacked("Message", block.timestamp, msg.sender));
        
        vm.startBroadcast();
        Broadcaster(broadcasterAddress).broadcastMessage(message);
        vm.stopBroadcast();

        console.log("Broadcaster:", broadcasterAddress);
        console.logBytes32(message);
    }
}

