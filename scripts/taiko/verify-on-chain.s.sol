// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IReceiver} from "../../src/contracts/interfaces/IReceiver.sol";

/// @notice Script to verify a broadcast message on-chain using the deployed Receiver contract
contract VerifyOnChain is Script {
    using stdJson for string;

    // Deployed contract addresses (from addresses.sh)
    address constant L1_RECEIVER = 0x9B06D17ce54B06dF4A644900492036E3AC384517;
    address constant L2_RECEIVER = 0x9B06D17ce54B06dF4A644900492036E3AC384517;
    // Use ProverPointer (initialized) instead of BlockHashProverPointer (not initialized)
    address constant L1_PROVER_POINTER = 0x5E81a027E3128876A666A42aBA6f6E38b20B4F2c;
    address constant L2_PROVER_POINTER = 0x5E81a027E3128876A666A42aBA6f6E38b20B4F2c;

    /// @notice Verify L1 message on L2 (L1 → L2 flow)
    function verifyL1MessageOnL2() public view {
        // Read proof data
        string memory proofPath = "test/payloads/taiko/taikoProofL1.json";
        string memory proofJson = vm.readFile(proofPath);

        uint256 blockNumber = proofJson.readUint(".blockNumber");
        address account = proofJson.readAddress(".account");
        uint256 slot = proofJson.readUint(".slot");
        bytes memory rlpBlockHeader = proofJson.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProof = proofJson.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = proofJson.readBytes(".rlpStorageProof");

        // Read message info
        string memory infoPath = "test/payloads/taiko/taikoProofL1-info.json";
        string memory infoJson = vm.readFile(infoPath);
        bytes32 message = infoJson.readBytes32(".message");
        address publisher = infoJson.readAddress(".publisher");

        console.log("=== Verifying L1 Message on L2 ===");
        console.log("Message:", vm.toString(message));
        console.log("Publisher:", publisher);
        console.log("Block Number:", blockNumber);

        // Construct RemoteReadArgs
        bytes memory storageProofInput = abi.encode(rlpBlockHeader, account, slot, rlpAccountProof, rlpStorageProof);

        address[] memory route = new address[](1);
        route[0] = L2_PROVER_POINTER;

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(uint48(blockNumber));

        IReceiver.RemoteReadArgs memory remoteReadArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProofInput
        });

        // Call the deployed Receiver contract
        (bytes32 broadcasterId, uint256 timestamp) = IReceiver(L2_RECEIVER).verifyBroadcastMessage(
            remoteReadArgs,
            message,
            publisher
        );

        console.log("");
        console.log("=== VERIFICATION SUCCESSFUL ===");
        console.log("Broadcaster ID:", vm.toString(broadcasterId));
        console.log("Timestamp:", timestamp);
    }

    /// @notice Verify L2 message on L1 (L2 → L1 flow)
    function verifyL2MessageOnL1() public view {
        // Read proof data
        string memory proofPath = "test/payloads/taiko/taikoProofL2.json";
        string memory proofJson = vm.readFile(proofPath);

        uint256 blockNumber = proofJson.readUint(".blockNumber");
        address account = proofJson.readAddress(".account");
        uint256 slot = proofJson.readUint(".slot");
        bytes memory rlpBlockHeader = proofJson.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProof = proofJson.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = proofJson.readBytes(".rlpStorageProof");

        // Read message info
        string memory infoPath = "test/payloads/taiko/taikoProofL2-info.json";
        string memory infoJson = vm.readFile(infoPath);
        bytes32 message = infoJson.readBytes32(".message");
        address publisher = infoJson.readAddress(".publisher");

        console.log("=== Verifying L2 Message on L1 ===");
        console.log("Message:", vm.toString(message));
        console.log("Publisher:", publisher);
        console.log("Block Number:", blockNumber);

        // Construct RemoteReadArgs
        bytes memory storageProofInput = abi.encode(rlpBlockHeader, account, slot, rlpAccountProof, rlpStorageProof);

        address[] memory route = new address[](1);
        route[0] = L1_PROVER_POINTER;

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(uint48(blockNumber));

        IReceiver.RemoteReadArgs memory remoteReadArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProofInput
        });

        // Call the deployed Receiver contract
        (bytes32 broadcasterId, uint256 timestamp) = IReceiver(L1_RECEIVER).verifyBroadcastMessage(
            remoteReadArgs,
            message,
            publisher
        );

        console.log("");
        console.log("=== VERIFICATION SUCCESSFUL ===");
        console.log("Broadcaster ID:", vm.toString(broadcasterId));
        console.log("Timestamp:", timestamp);
    }
}
