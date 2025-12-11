// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";


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

        string memory path = "test/payloads/ethereum/arb_pointer_proof_block_9747805.json";

        string memory json = vm.readFile(path);
        uint256 blockNumber = json.readUint(".blockNumber");
        bytes32 blockHash = json.readBytes32(".blockHash");
        address account = json.readAddress(".account");
        uint256 slot = json.readUint(".slot");
        bytes32 value = bytes32(json.readUint(".slotValue"));
        bytes memory rlpBlockHeader = json.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProof = json.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = json.readBytes(".rlpStorageProof");

        address blockHashProverPointerAddress = 0x8Dc3812f911383e6320D036e35Db8dF3774C4eE1;

        bytes memory input = abi.encode(rlpBlockHeader, account, slot, rlpAccountProof, rlpStorageProof);

        address[] memory route = new address[](1);
        route[0] = blockHashProverPointerAddress;

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(blockNumber);

        bytes memory storageProofToLastProver = input;

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, bhpInputs: bhpInputs, storageProof: storageProofToLastProver});

        vm.startBroadcast();
        Receiver receiver = Receiver(0xF69a42eFE9d2A3AD87436bD7589F2c497F910cef);
        

        IBlockHashProver arbParentToChildProverCopy = IBlockHashProver(0x871ea89101BbE55C8c3dDbAA0890C128E828A339);

        bytes32 bhpPointerId = receiver.updateBlockHashProverCopy(remoteReadArgs, arbParentToChildProverCopy);

        
        vm.stopBroadcast();
    }
}