// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";


import { console } from "forge-std/console.sol";
import { BufferMock } from "../../test/mocks/BufferMock.sol";
import { Receiver } from "../../src/contracts/Receiver.sol";
import { BlockHashProverPointer } from "../../src/contracts/BlockHashProverPointer.sol";
import { ChildToParentProver as ZksyncChildToParentProver } from "../../src/contracts/provers/zksync/ChildToParentProver.sol";
import {ChildToParentProver as LineaChildToParentProver} from "../../src/contracts/provers/linea/ChildToParentProver.sol";
import {ChildToParentProver as ScrollChildToParentProver} from "../../src/contracts/provers/scroll/ChildToParentProver.sol";
import {IBlockHashProver} from "../../src/contracts/interfaces/IBlockHashProver.sol";
import {IReceiver} from "../../src/contracts/interfaces/IReceiver.sol";

contract Deploy is Script {
    using stdJson for string;
    function run() public {

        string memory pathPointer = "test/payloads/ethereum/arb_pointer_proof_block_9747805.json";
        string memory jsonPointer = vm.readFile(pathPointer);

        address arbParentToChildProverPointerAddress = jsonPointer.readAddress(".account");

        console.log("Arb Parent to Child Prover Pointer Address:");
        console.logAddress(arbParentToChildProverPointerAddress);

        string memory pathEthereum = "test/payloads/ethereum/output_storage_proof_block_9567705.json";

        string memory jsonEthereum = vm.readFile(pathEthereum);
        uint256 blockNumberEthereum = jsonEthereum.readUint(".blockNumber");
        bytes32 blockHashEthereum = jsonEthereum.readBytes32(".blockHash");
        bytes memory rlpBlockHeaderEthereum = jsonEthereum.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProofEthereum = jsonEthereum.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProofEthereum = jsonEthereum.readBytes(".rlpStorageProof");

        string memory pathArb = "test/payloads/arbitrum/broadcast_proof_block_207673361.json";

        string memory jsonArbitrum = vm.readFile(pathArb);
        address accountArbitrum = jsonArbitrum.readAddress(".account");
        uint256 slotArbitrum = jsonArbitrum.readUint(".slot");
        bytes32 valueArbitrum = bytes32(jsonArbitrum.readUint(".slotValue"));
        bytes32 sendRootArbitrum = jsonArbitrum.readBytes32(".sendRoot");
        bytes memory rlpBlockHeaderArbitrum = jsonArbitrum.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProofArbitrum = jsonArbitrum.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProofArbitrum = jsonArbitrum.readBytes(".rlpStorageProof");

        address blockHashProverPointerAddress = 0x8Dc3812f911383e6320D036e35Db8dF3774C4eE1;

        address[] memory route = new address[](2);
        route[0] = blockHashProverPointerAddress;
        route[1] = arbParentToChildProverPointerAddress;

        bytes memory input0 = abi.encode(blockNumberEthereum);
        bytes memory input1 =
            abi.encode(rlpBlockHeaderEthereum, sendRootArbitrum, rlpAccountProofEthereum, rlpStorageProofEthereum);

        bytes[] memory bhpInputs = new bytes[](2);
        bhpInputs[0] = input0;
        bhpInputs[1] = input1;

        bytes memory storageProofToLastProver = abi.encode(
            rlpBlockHeaderArbitrum, accountArbitrum, slotArbitrum, rlpAccountProofArbitrum, rlpStorageProofArbitrum
        );

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, bhpInputs: bhpInputs, storageProof: storageProofToLastProver});

        vm.startBroadcast();
        Receiver receiver = Receiver(0xF69a42eFE9d2A3AD87436bD7589F2c497F910cef);
        

        bytes32 message = 0x0000000000000000000000000000000000000000000000000000000074657374; // "test"
        address publisher = 0x9a56fFd72F4B526c523C733F1F74197A51c495E1;

        (bytes32 broadcasterId, uint256 timestamp) = receiver.verifyBroadcastMessage(remoteReadArgs, message, publisher);

        console.log("Broadcaster ID:");
        console.logBytes32(broadcasterId);
        console.log("Timestamp:", timestamp);

        
        vm.stopBroadcast();
    }
}