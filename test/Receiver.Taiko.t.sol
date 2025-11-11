// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console, Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Receiver} from "../src/contracts/Receiver.sol";
import {IReceiver} from "../src/contracts/interfaces/IReceiver.sol";
import {BlockHashProverPointer} from "../src/contracts/BlockHashProverPointer.sol";
import {ParentToChildProver as TaikoParentToChildProver} from "../src/contracts/provers/taiko/ParentToChildProver.sol";
import {ChildToParentProver as TaikoChildToParentProver} from "../src/contracts/provers/taiko/ChildToParentProver.sol";

interface ISignalService {
    struct Checkpoint {
        uint48 blockNumber;
        bytes32 blockHash;
        bytes32 stateRoot;
    }
    
    function getCheckpoint(uint48 _blockNumber) external view returns (Checkpoint memory);
}

contract ReceiverTaikoTest is Test {
    using stdJson for string;

    Receiver public receiver;
    TaikoParentToChildProver public parentToChildProver;
    TaikoChildToParentProver public childToParentProver;
    BlockHashProverPointer public blockHashProverPointer;

    uint256 public ethereumForkId;
    uint256 public taikoL2ForkId;

    address public constant L1_SIGNAL_SERVICE = 0xbB128Fd4942e8143B8dc10f38CCfeADb32544264;
    address public constant L2_SIGNAL_SERVICE = 0x1670010000000000000000000000000000000005;
    uint256 public constant CHECKPOINTS_SLOT = 254;
    uint256 public constant L1_CHAIN_ID = 32382;
    uint256 public constant L2_CHAIN_ID = 167001;

    address owner = makeAddr("owner");

    function setUp() public {
        ethereumForkId = vm.createFork(vm.envString("TAIKO_PARENT_RPC_URL"));
        taikoL2ForkId = vm.createFork(vm.envString("TAIKO_CHILD_RPC_URL"));
    }

    function test_verifyBroadcastMessage_from_TaikoL2_into_Ethereum() public {
        vm.selectFork(ethereumForkId);
        vm.chainId(L1_CHAIN_ID);
        
        receiver = new Receiver();
        parentToChildProver = new TaikoParentToChildProver(L1_SIGNAL_SERVICE, CHECKPOINTS_SLOT, L1_CHAIN_ID);
        blockHashProverPointer = new BlockHashProverPointer(owner);

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(parentToChildProver));

        string memory path = "test/payloads/taiko/taikoProofL2.json";
        string memory json = vm.readFile(path);

        uint256 blockNumber = json.readUint(".blockNumber");
        bytes32 blockHash = json.readBytes32(".blockHash");
        bytes32 stateRoot = json.readBytes32(".stateRoot");
        address account = json.readAddress(".account");
        uint256 slot = json.readUint(".slot");
        bytes memory rlpBlockHeader = json.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProof = json.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = json.readBytes(".rlpStorageProof");

        bytes32 expectedBlockHash = keccak256(rlpBlockHeader);
        assertEq(blockHash, expectedBlockHash, "block hash mismatch");

        uint256 checkpointSlot = uint256(keccak256(abi.encode(uint48(blockNumber), CHECKPOINTS_SLOT)));
        vm.store(L1_SIGNAL_SERVICE, bytes32(checkpointSlot), blockHash);
        vm.store(L1_SIGNAL_SERVICE, bytes32(checkpointSlot + 1), stateRoot);
        
        bytes memory storageProofInput = abi.encode(rlpBlockHeader, account, slot, rlpAccountProof, rlpStorageProof);

        address[] memory route = new address[](1);
        route[0] = address(blockHashProverPointer);

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(uint48(blockNumber));

        IReceiver.RemoteReadArgs memory remoteReadArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProofInput
        });
        
        bytes32 message = 0xd9222d7d84eefb8570069f30ab4a850423ba57a374c593b67a224c430f9736df;
        address publisher = 0x1CBd3b2770909D4e10f157cABC84C7264073C9Ec;

        (bytes32 broadcasterId, uint256 timestamp) = receiver.verifyBroadcastMessage(
            remoteReadArgs,
            message,
            publisher
        );

        assertNotEq(broadcasterId, bytes32(0), "broadcasterId should not be zero");
        assertNotEq(timestamp, 0, "timestamp should not be zero");
        
        console.log("Broadcaster ID:", vm.toString(broadcasterId));
        console.log("Timestamp:", timestamp);
    }

    function test_verifyBroadcastMessage_from_TaikoL2_realMessage() public {
        vm.selectFork(ethereumForkId);
        vm.chainId(L1_CHAIN_ID);
        
        receiver = new Receiver();
        parentToChildProver = new TaikoParentToChildProver(L1_SIGNAL_SERVICE, CHECKPOINTS_SLOT, L1_CHAIN_ID);
        blockHashProverPointer = new BlockHashProverPointer(owner);

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(parentToChildProver));

        string memory path = "test/payloads/taiko/taikoProofL2.json";
        string memory json = vm.readFile(path);

        uint256 blockNumber = json.readUint(".blockNumber");
        bytes32 blockHash = json.readBytes32(".blockHash");
        bytes32 stateRoot = json.readBytes32(".stateRoot");
        address account = json.readAddress(".account");
        uint256 slot = json.readUint(".slot");
        uint256 slotValue = json.readUint(".slotValue");
        bytes memory rlpBlockHeader = json.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProof = json.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = json.readBytes(".rlpStorageProof");

        uint256 checkpointSlot = uint256(keccak256(abi.encode(uint48(blockNumber), CHECKPOINTS_SLOT)));
        vm.store(L1_SIGNAL_SERVICE, bytes32(checkpointSlot), blockHash);
        vm.store(L1_SIGNAL_SERVICE, bytes32(checkpointSlot + 1), stateRoot);
        
        bytes memory storageProofInput = abi.encode(rlpBlockHeader, account, slot, rlpAccountProof, rlpStorageProof);

        address[] memory route = new address[](1);
        route[0] = address(blockHashProverPointer);

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(uint48(blockNumber));

        IReceiver.RemoteReadArgs memory remoteReadArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProofInput
        });

        bytes32 realMessage = 0xd9222d7d84eefb8570069f30ab4a850423ba57a374c593b67a224c430f9736df;
        address realPublisher = 0x1CBd3b2770909D4e10f157cABC84C7264073C9Ec;

        (bytes32 broadcasterId, uint256 timestamp) = receiver.verifyBroadcastMessage(
            remoteReadArgs,
            realMessage,
            realPublisher
        );

        assertNotEq(broadcasterId, bytes32(0), "broadcasterId should not be zero");
        assertNotEq(timestamp, 0, "timestamp should not be zero");
        
        console.log("Real Broadcaster ID:", vm.toString(broadcasterId));
        console.log("Real Timestamp:", timestamp);
    }

    function test_verifyBroadcastMessage_from_Ethereum_into_TaikoL2() public {
        vm.selectFork(taikoL2ForkId);
        vm.chainId(L2_CHAIN_ID);
        
        receiver = new Receiver();
        childToParentProver = new TaikoChildToParentProver(L2_SIGNAL_SERVICE, CHECKPOINTS_SLOT, L2_CHAIN_ID);
        blockHashProverPointer = new BlockHashProverPointer(owner);

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(childToParentProver));

        string memory path = "test/payloads/taiko/taikoProofL1.json";
        string memory json = vm.readFile(path);

        uint256 blockNumber = json.readUint(".blockNumber");
        bytes32 blockHash = json.readBytes32(".blockHash");
        bytes32 stateRoot = json.readBytes32(".stateRoot");
        address account = json.readAddress(".account");
        uint256 slot = json.readUint(".slot");
        bytes memory rlpBlockHeader = json.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProof = json.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = json.readBytes(".rlpStorageProof");

        bytes32 expectedBlockHash = keccak256(rlpBlockHeader);
        assertEq(blockHash, expectedBlockHash, "block hash mismatch");

        uint256 checkpointSlot = uint256(keccak256(abi.encode(uint48(blockNumber), CHECKPOINTS_SLOT)));
        vm.store(L2_SIGNAL_SERVICE, bytes32(checkpointSlot), blockHash);
        vm.store(L2_SIGNAL_SERVICE, bytes32(checkpointSlot + 1), stateRoot);
        
        bytes memory storageProofInput = abi.encode(rlpBlockHeader, account, slot, rlpAccountProof, rlpStorageProof);

        address[] memory route = new address[](1);
        route[0] = address(blockHashProverPointer);

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(uint48(blockNumber));

        IReceiver.RemoteReadArgs memory remoteReadArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProofInput
        });

        bytes32 message = 0x5041a05869f0dc3531761620bdee270a461871b5ff865219005a86fdfa6bf145;
        address publisher = 0x1CBd3b2770909D4e10f157cABC84C7264073C9Ec;

        (bytes32 broadcasterId, uint256 timestamp) = receiver.verifyBroadcastMessage(
            remoteReadArgs,
            message,
            publisher
        );

        assertNotEq(broadcasterId, bytes32(0), "broadcasterId should not be zero");
        assertNotEq(timestamp, 0, "timestamp should not be zero");
        
        console.log("Broadcaster ID from L1:", vm.toString(broadcasterId));
        console.log("Timestamp from L1:", timestamp);
    }
}

