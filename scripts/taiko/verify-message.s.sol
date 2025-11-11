// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { Receiver } from "../../src/contracts/Receiver.sol";
import { IReceiver } from "../../src/contracts/interfaces/IReceiver.sol";

contract VerifyMessage is Script {
    using stdJson for string;

    function run() public view {
        address receiverAddress = vm.envAddress("L1_RECEIVER");
        address proverPointerAddress = vm.envAddress("L1_PROVER_POINTER");
        
        string memory path = "test/payloads/taiko/taikoProofL2.json";
        string memory json = vm.readFile(path);

        uint256 blockNumber = json.readUint(".blockNumber");
        address account = json.readAddress(".account");
        uint256 slot = json.readUint(".slot");
        bytes memory rlpBlockHeader = json.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProof = json.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = json.readBytes(".rlpStorageProof");

        bytes memory storageProofInput = abi.encode(rlpBlockHeader, account, slot, rlpAccountProof, rlpStorageProof);

        address[] memory route = new address[](1);
        route[0] = proverPointerAddress;

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(uint48(blockNumber));

        IReceiver.RemoteReadArgs memory remoteReadArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProofInput
        });
        
        bytes32 message = 0xd9222d7d84eefb8570069f30ab4a850423ba57a374c593b67a224c430f9736df;
        address publisher = 0x1CBd3b2770909D4e10f157cABC84C7264073C9Ec;

        console.log("=== Verifying Message from Taiko L2 ===");
        console.log("Receiver:       ", receiverAddress);
        console.log("ProverPointer:  ", proverPointerAddress);
        console.log("L2 Block:       ", blockNumber);
        console.log("Publisher:      ", publisher);
        console.log("Message:");
        console.logBytes32(message);
        console.log("");

        (bytes32 broadcasterId, uint256 timestamp) = Receiver(receiverAddress).verifyBroadcastMessage(
            remoteReadArgs,
            message,
            publisher
        );

        console.log("=== Verification Success ===");
        console.log("Broadcaster ID: ", vm.toString(broadcasterId));
        console.log("Timestamp:      ", timestamp);
    }
}

