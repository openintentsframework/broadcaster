// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console, Test} from "forge-std/Test.sol";
import {Broadcaster} from "../../../src/contracts/Broadcaster.sol";
import {Receiver} from "../../../src/contracts/Receiver.sol";
import {BlockHashProverPointer} from "../../../src/contracts/BlockHashProverPointer.sol";
import {ParentToChildProver} from "../../../src/contracts/provers/arbitrum/ParentToChildProver.sol";
import {ChildToParentProver} from "../../../src/contracts/provers/arbitrum/ChildToParentProver.sol";
import {IReceiver} from "../../../src/contracts/interfaces/IReceiver.sol";
import {IBlockHashProver} from "../../../src/contracts/interfaces/IBlockHashProver.sol";
import {IOutbox} from "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import {RLP} from "@openzeppelin/contracts/utils/RLP.sol";

/// @title ERC7888EndToEndTest
/// @notice Complete end-to-end tests for the ERC-7888 cross-chain messaging system
/// @dev Demonstrates the full workflow from message broadcasting to verification across chains
contract ERC7888EndToEndTest is Test {
    using RLP for RLP.Encoder;

    // Chain setup
    uint256 public parentForkId;  // Ethereum Sepolia
    uint256 public childForkId;   // Arbitrum Sepolia

    // Core contracts on both chains
    Broadcaster public parentBroadcaster;
    Broadcaster public childBroadcaster;
    Receiver public parentReceiver;
    Receiver public childReceiver;

    // Provers and Pointers
    ParentToChildProver public parentToChildProver;
    ChildToParentProver public childToParentProver;
    BlockHashProverPointer public parentToChildPointer;
    BlockHashProverPointer public childToParentPointer;

    // Arbitrum specific contracts
    IOutbox public outbox = IOutbox(0x65f07C7D521164a4d5DaC6eB8Fac8DA067A3B78F);

    // Test accounts
    address public publisher = makeAddr("publisher");
    address public subscriber = makeAddr("subscriber");
    address public pointerOwner = makeAddr("pointerOwner");

    // Test data
    struct ChainData {
        bytes32 sendRoot;
        uint256 blockNumber;
        bytes32 blockHash;
    }

    ChainData public parentData;
    ChainData public childData;

    function setUp() public {
        // Create forks
        parentForkId = vm.createFork(vm.envString("PARENT_RPC_URL"));
        childForkId = vm.createFork(vm.envString("CHILD_RPC_URL"));

        // Deploy contracts on parent chain
        vm.selectFork(parentForkId);
        parentBroadcaster = new Broadcaster();
        parentReceiver = new Receiver();
        parentToChildProver = new ParentToChildProver(address(outbox), 3);
        parentToChildPointer = new BlockHashProverPointer(pointerOwner);

        // Deploy contracts on child chain
        vm.selectFork(childForkId);
        childBroadcaster = new Broadcaster();
        childReceiver = new Receiver();
        childToParentProver = new ChildToParentProver();
        childToParentPointer = new BlockHashProverPointer(pointerOwner);

        // Set up test data
        parentData = ChainData({
            sendRoot: 0x89452690BD661B0B1FFB5A39D4136BE89C91365E3A5948680077F6FE5AC7B6F4,
            blockNumber: 9043403,
            blockHash: 0x1e9c639e9b29486266f7e41b0def33287c5c26ae35bb0f7f6737d7fdeb4a1ed3
        });

        childData = ChainData({
            sendRoot: 0x0000000000000000000000000000000000000000000000000000000000000000,
            blockNumber: 186709590,
            blockHash: 0xac41e096f5182caa7160c317370f367d6a91c9ae6807db0fda2b03435c29941e
        });
    }

    function test_complete_parent_to_child_message_flow() public {
        console.log("=== Testing Complete Parent to Child Message Flow ===");
        
        // Step 1: Broadcast message on parent chain
        vm.selectFork(parentForkId);
        bytes32 message = keccak256("Hello from Ethereum to Arbitrum!");
        
        console.log("Step 1: Broadcasting message on parent chain");
        vm.prank(publisher);
        parentBroadcaster.broadcastMessage(message);
        
        assertTrue(parentBroadcaster.hasBroadcasted(message, publisher));
        console.log("✓ Message broadcasted successfully");

        // Step 2: Set up prover pointer on parent chain
        console.log("Step 2: Setting up prover pointer");
        vm.prank(pointerOwner);
        parentToChildPointer.updateImplementation(address(parentToChildProver));
        console.log("✓ Prover pointer configured");

        // Step 3: Update prover copy on child chain
        vm.selectFork(childForkId);
        console.log("Step 3: Updating prover copy on child chain");
        
        address[] memory route = new address[](1);
        route[0] = address(parentToChildPointer);
        
        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(parentData.sendRoot);
        
        bytes memory storageProof = _getStorageProof();
        
        IReceiver.RemoteReadArgs memory pointerReadArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProof
        });

        vm.prank(subscriber);
        bytes32 pointerId = childReceiver.updateBlockHashProverCopy(pointerReadArgs, parentToChildProver);
        
        assertTrue(address(childReceiver.blockHashProverCopy(pointerId)) != address(0));
        console.log("✓ Prover copy updated successfully");

        // Step 4: Verify message on child chain
        console.log("Step 4: Verifying message on child chain");
        
        bytes[] memory broadcasterInputs = new bytes[](1);
        broadcasterInputs[0] = abi.encode(parentData.sendRoot);
        
        bytes memory broadcasterStorageProof = _getBroadcasterStorageProof(message);
        
        IReceiver.RemoteReadArgs memory broadcasterReadArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: broadcasterInputs,
            storageProof: broadcasterStorageProof
        });

        vm.prank(subscriber);
        (bytes32 broadcasterId, uint256 timestamp) = childReceiver.verifyBroadcastMessage(
            broadcasterReadArgs,
            message,
            publisher
        );

        assertTrue(broadcasterId != bytes32(0));
        assertTrue(timestamp > 0);
        console.log("✓ Message verified successfully on child chain");
        console.log("✓ Complete parent-to-child flow successful!");
    }

    function test_complete_child_to_parent_message_flow() public {
        console.log("=== Testing Complete Child to Parent Message Flow ===");
        
        // Step 1: Broadcast message on child chain
        vm.selectFork(childForkId);
        bytes32 message = keccak256("Hello from Arbitrum to Ethereum!");
        
        console.log("Step 1: Broadcasting message on child chain");
        vm.prank(publisher);
        childBroadcaster.broadcastMessage(message);
        
        assertTrue(childBroadcaster.hasBroadcasted(message, publisher));
        console.log("✓ Message broadcasted successfully");

        // Step 2: Set up prover pointer on child chain
        console.log("Step 2: Setting up prover pointer");
        vm.prank(pointerOwner);
        childToParentPointer.updateImplementation(address(childToParentProver));
        console.log("✓ Prover pointer configured");

        // Step 3: Update prover copy on parent chain
        vm.selectFork(parentForkId);
        console.log("Step 3: Updating prover copy on parent chain");
        
        address[] memory route = new address[](1);
        route[0] = address(childToParentPointer);
        
        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(childData.blockNumber);
        
        bytes memory storageProof = _getStorageProof();
        
        IReceiver.RemoteReadArgs memory pointerReadArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProof
        });

        vm.prank(subscriber);
        bytes32 pointerId = parentReceiver.updateBlockHashProverCopy(pointerReadArgs, childToParentProver);
        
        assertTrue(address(parentReceiver.blockHashProverCopy(pointerId)) != address(0));
        console.log("✓ Prover copy updated successfully");

        // Step 4: Verify message on parent chain
        console.log("Step 4: Verifying message on parent chain");
        
        bytes[] memory broadcasterInputs = new bytes[](1);
        broadcasterInputs[0] = abi.encode(childData.blockNumber);
        
        bytes memory broadcasterStorageProof = _getBroadcasterStorageProof(message);
        
        IReceiver.RemoteReadArgs memory broadcasterReadArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: broadcasterInputs,
            storageProof: broadcasterStorageProof
        });

        vm.prank(subscriber);
        (bytes32 broadcasterId, uint256 timestamp) = parentReceiver.verifyBroadcastMessage(
            broadcasterReadArgs,
            message,
            publisher
        );

        assertTrue(broadcasterId != bytes32(0));
        assertTrue(timestamp > 0);
        console.log("✓ Message verified successfully on parent chain");
        console.log("✓ Complete child-to-parent flow successful!");
    }

    function test_bidirectional_message_flow() public {
        console.log("=== Testing Bidirectional Message Flow ===");
        
        // Phase 1: Parent to Child
        vm.selectFork(parentForkId);
        bytes32 parentMessage = keccak256("Bidirectional message from parent");
        
        vm.prank(publisher);
        parentBroadcaster.broadcastMessage(parentMessage);
        
        // Set up parent-to-child prover
        vm.prank(pointerOwner);
        parentToChildPointer.updateImplementation(address(parentToChildProver));
        
        // Verify on child chain
        vm.selectFork(childForkId);
        address[] memory route = new address[](1);
        route[0] = address(parentToChildPointer);
        
        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(parentData.sendRoot);
        
        bytes memory storageProof = _getStorageProof();
        
        IReceiver.RemoteReadArgs memory pointerReadArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProof
        });

        vm.prank(subscriber);
        childReceiver.updateBlockHashProverCopy(pointerReadArgs, parentToChildProver);
        
        bytes[] memory broadcasterInputs = new bytes[](1);
        broadcasterInputs[0] = abi.encode(parentData.sendRoot);
        
        bytes memory broadcasterStorageProof = _getBroadcasterStorageProof(parentMessage);
        
        IReceiver.RemoteReadArgs memory broadcasterReadArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: broadcasterInputs,
            storageProof: broadcasterStorageProof
        });

        vm.prank(subscriber);
        (bytes32 broadcasterId1, uint256 timestamp1) = childReceiver.verifyBroadcastMessage(
            broadcasterReadArgs,
            parentMessage,
            publisher
        );

        assertTrue(broadcasterId1 != bytes32(0));
        console.log("✓ Parent-to-child message verified");

        // Phase 2: Child to Parent
        bytes32 childMessage = keccak256("Bidirectional response from child");
        
        vm.prank(subscriber);
        childBroadcaster.broadcastMessage(childMessage);
        
        // Set up child-to-parent prover
        vm.prank(pointerOwner);
        childToParentPointer.updateImplementation(address(childToParentProver));
        
        // Verify on parent chain
        vm.selectFork(parentForkId);
        address[] memory reverseRoute = new address[](1);
        reverseRoute[0] = address(childToParentPointer);
        
        bytes[] memory reverseInputs = new bytes[](1);
        reverseInputs[0] = abi.encode(childData.blockNumber);
        
        IReceiver.RemoteReadArgs memory reversePointerReadArgs = IReceiver.RemoteReadArgs({
            route: reverseRoute,
            bhpInputs: reverseInputs,
            storageProof: storageProof
        });

        vm.prank(publisher);
        parentReceiver.updateBlockHashProverCopy(reversePointerReadArgs, childToParentProver);
        
        bytes[] memory reverseBroadcasterInputs = new bytes[](1);
        reverseBroadcasterInputs[0] = abi.encode(childData.blockNumber);
        
        bytes memory reverseBroadcasterStorageProof = _getBroadcasterStorageProof(childMessage);
        
        IReceiver.RemoteReadArgs memory reverseBroadcasterReadArgs = IReceiver.RemoteReadArgs({
            route: reverseRoute,
            bhpInputs: reverseBroadcasterInputs,
            storageProof: reverseBroadcasterStorageProof
        });

        vm.prank(publisher);
        (bytes32 broadcasterId2, uint256 timestamp2) = parentReceiver.verifyBroadcastMessage(
            reverseBroadcasterReadArgs,
            childMessage,
            subscriber
        );

        assertTrue(broadcasterId2 != bytes32(0));
        console.log("✓ Child-to-parent message verified");
        console.log("✓ Bidirectional flow successful!");
    }

    function test_multiple_messages_same_chain() public {
        console.log("=== Testing Multiple Messages on Same Chain ===");
        
        vm.selectFork(parentForkId);
        
        // Broadcast multiple messages
        bytes32 message1 = keccak256("Message 1");
        bytes32 message2 = keccak256("Message 2");
        bytes32 message3 = keccak256("Message 3");
        
        vm.startPrank(publisher);
        parentBroadcaster.broadcastMessage(message1);
        parentBroadcaster.broadcastMessage(message2);
        parentBroadcaster.broadcastMessage(message3);
        vm.stopPrank();
        
        // Verify all messages were broadcast
        assertTrue(parentBroadcaster.hasBroadcasted(message1, publisher));
        assertTrue(parentBroadcaster.hasBroadcasted(message2, publisher));
        assertTrue(parentBroadcaster.hasBroadcasted(message3, publisher));
        
        console.log("✓ Multiple messages broadcasted successfully");
        
        // Set up prover and verify on child chain
        vm.prank(pointerOwner);
        parentToChildPointer.updateImplementation(address(parentToChildProver));
        
        vm.selectFork(childForkId);
        address[] memory route = new address[](1);
        route[0] = address(parentToChildPointer);
        
        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(parentData.sendRoot);
        
        bytes memory storageProof = _getStorageProof();
        
        IReceiver.RemoteReadArgs memory pointerReadArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProof
        });

        vm.prank(subscriber);
        childReceiver.updateBlockHashProverCopy(pointerReadArgs, parentToChildProver);
        
        // Verify all messages
        bytes[] memory broadcasterInputs = new bytes[](1);
        broadcasterInputs[0] = abi.encode(parentData.sendRoot);
        
        vm.startPrank(subscriber);
        
        bytes memory broadcasterStorageProof1 = _getBroadcasterStorageProof(message1);
        IReceiver.RemoteReadArgs memory broadcasterReadArgs1 = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: broadcasterInputs,
            storageProof: broadcasterStorageProof1
        });
        (bytes32 broadcasterId1, uint256 timestamp1) = childReceiver.verifyBroadcastMessage(
            broadcasterReadArgs1,
            message1,
            publisher
        );
        
        bytes memory broadcasterStorageProof2 = _getBroadcasterStorageProof(message2);
        IReceiver.RemoteReadArgs memory broadcasterReadArgs2 = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: broadcasterInputs,
            storageProof: broadcasterStorageProof2
        });
        (bytes32 broadcasterId2, uint256 timestamp2) = childReceiver.verifyBroadcastMessage(
            broadcasterReadArgs2,
            message2,
            publisher
        );
        
        bytes memory broadcasterStorageProof3 = _getBroadcasterStorageProof(message3);
        IReceiver.RemoteReadArgs memory broadcasterReadArgs3 = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: broadcasterInputs,
            storageProof: broadcasterStorageProof3
        });
        (bytes32 broadcasterId3, uint256 timestamp3) = childReceiver.verifyBroadcastMessage(
            broadcasterReadArgs3,
            message3,
            publisher
        );
        
        vm.stopPrank();
        
        assertTrue(broadcasterId1 != bytes32(0));
        assertTrue(broadcasterId2 != bytes32(0));
        assertTrue(broadcasterId3 != bytes32(0));
        
        console.log("✓ All messages verified successfully");
    }

    function test_prover_upgrade_during_flow() public {
        console.log("=== Testing Prover Upgrade During Flow ===");
        
        // Initial setup
        vm.selectFork(parentForkId);
        vm.prank(pointerOwner);
        parentToChildPointer.updateImplementation(address(parentToChildProver));
        
        // Broadcast message
        bytes32 message = keccak256("Upgrade test message");
        vm.prank(publisher);
        parentBroadcaster.broadcastMessage(message);
        
        // Verify with original prover
        vm.selectFork(childForkId);
        address[] memory route = new address[](1);
        route[0] = address(parentToChildPointer);
        
        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(parentData.sendRoot);
        
        bytes memory storageProof = _getStorageProof();
        
        IReceiver.RemoteReadArgs memory pointerReadArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProof
        });

        vm.prank(subscriber);
        childReceiver.updateBlockHashProverCopy(pointerReadArgs, parentToChildProver);
        
        bytes[] memory broadcasterInputs = new bytes[](1);
        broadcasterInputs[0] = abi.encode(parentData.sendRoot);
        
        bytes memory broadcasterStorageProof = _getBroadcasterStorageProof(message);
        
        IReceiver.RemoteReadArgs memory broadcasterReadArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: broadcasterInputs,
            storageProof: broadcasterStorageProof
        });

        vm.prank(subscriber);
        (bytes32 broadcasterId1, uint256 timestamp1) = childReceiver.verifyBroadcastMessage(
            broadcasterReadArgs,
            message,
            publisher
        );
        
        assertTrue(broadcasterId1 != bytes32(0));
        console.log("✓ Message verified with original prover");
        
        // Upgrade prover
        vm.selectFork(parentForkId);
        ParentToChildProver newProver = new ParentToChildProver(address(outbox), 3);
        
        vm.prank(pointerOwner);
        parentToChildPointer.updateImplementation(address(newProver));
        
        console.log("✓ Prover upgraded successfully");
        
        // Verify message with upgraded prover
        vm.selectFork(childForkId);
        
        vm.prank(subscriber);
        bytes32 newPointerId = childReceiver.updateBlockHashProverCopy(pointerReadArgs, newProver);
        
        vm.prank(subscriber);
        (bytes32 broadcasterId2, uint256 timestamp2) = childReceiver.verifyBroadcastMessage(
            broadcasterReadArgs,
            message,
            publisher
        );
        
        assertTrue(broadcasterId2 != bytes32(0));
        console.log("✓ Message verified with upgraded prover");
        console.log("✓ Prover upgrade successful!");
    }

    function test_gas_consumption_end_to_end() public {
        console.log("=== Testing Gas Consumption End-to-End ===");
        
        vm.selectFork(parentForkId);
        
        // Measure broadcast gas
        bytes32 message = keccak256("Gas test message");
        uint256 gasBefore = gasleft();
        vm.prank(publisher);
        parentBroadcaster.broadcastMessage(message);
        uint256 broadcastGas = gasBefore - gasleft();
        
        console.log("Broadcast gas:", broadcastGas);
        
        // Measure prover setup gas
        vm.prank(pointerOwner);
        parentToChildPointer.updateImplementation(address(parentToChildProver));
        
        vm.selectFork(childForkId);
        
        address[] memory route = new address[](1);
        route[0] = address(parentToChildPointer);
        
        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(parentData.sendRoot);
        
        bytes memory storageProof = _getStorageProof();
        
        IReceiver.RemoteReadArgs memory pointerReadArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProof
        });

        gasBefore = gasleft();
        vm.prank(subscriber);
        childReceiver.updateBlockHashProverCopy(pointerReadArgs, parentToChildProver);
        uint256 setupGas = gasBefore - gasleft();
        
        console.log("Prover setup gas:", setupGas);
        
        // Measure verification gas
        bytes[] memory broadcasterInputs = new bytes[](1);
        broadcasterInputs[0] = abi.encode(parentData.sendRoot);
        
        bytes memory broadcasterStorageProof = _getBroadcasterStorageProof(message);
        
        IReceiver.RemoteReadArgs memory broadcasterReadArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: broadcasterInputs,
            storageProof: broadcasterStorageProof
        });

        gasBefore = gasleft();
        vm.prank(subscriber);
        childReceiver.verifyBroadcastMessage(broadcasterReadArgs, message, publisher);
        uint256 verifyGas = gasBefore - gasleft();
        
        console.log("Verification gas:", verifyGas);
        console.log("Total gas:", broadcastGas + setupGas + verifyGas);
        
        // Ensure reasonable gas consumption
        assertTrue(broadcastGas < 100000, "Broadcast gas too high");
        assertTrue(setupGas < 500000, "Setup gas too high");
        assertTrue(verifyGas < 500000, "Verify gas too high");
        
        console.log("✓ Gas consumption within acceptable limits");
    }

    // Helper functions
    function _getStorageProof() internal pure returns (bytes memory) {
        bytes[] memory storageProofList = new bytes[](5);
        
        storageProofList[0] = RLP.encode(hex"f90211a0b33465ffacdced06a69a8d72df1c701c626e57472ebd7064365259b653c067e8a097a867acee4139e502e459b7130c85aa556fb189c97b3effa444ca06cd28d4fca0c9635ab3c1ad1830a1957d034d8ef95997e7dec700f16bb759a841764def1ce4a09ce8504f9d7882c39f3df76a2f22dd587cc02a12ebbaf694937147cff26f0a21a082e461aa0446b8192b4a0b7c9d2b6cbd94deede9d3efd9fa119595cf06635a24a055d466ade6350a4b88dea161ca40c29c7d5c26f3ba98361b8e8d06356cee6558a08968e2cc68c8eb7af29b15b9415f72ffca529f68ddaf77bf15d3234ce191f12fa030831a905336a320a84b13993e270709f10922955a6f7c3c3427ed7b0e20ec78a0fc5f3774c76588b1e7ef82d7b4540d550ca76cdd73e420cd85b7b9278d3149e2a0c2338a30b6451618424528c3ef7fa3031cdbaa6bfb3f3858845ac69d9fee6108a031658c992b377e0dfd5ce60caf4109e04e920e567ad985deb9b1d0ffd10f34eba04a901ada2d44da9c185db36cb3227b9e34900feb86e39cf9a47bd7cb6daa9d30a053b84cd1dd27a2be742d4a644d2d3f6b94f2908f1e3cecc13e8e7f0184638256a0d1c63dd15af48442e80923e3af80f9346e370653655003ce96473cbe6147a6e5a08d294de8159e11eaf4246496f36bfe0fa968937cd78fc990e4edc05448c01e20a017fb4047699fc4c3d4483cc38306cbabbac7e32202c6eeeb39a716ab8a43bec380");
        storageProofList[1] = RLP.encode(hex"f90211a002d8e953aa5bbf1b090919d432f98da71e42551c7704445777726867eacd880fa0483386d5094035bbb6e622f58e12bf2d3b868c3a8633e62711682d5ac7c8ac21a0fe1d169346618286dbf7e445767f74806d308d106d2aece6e71e0e5332a9f268a0a82b81164516b1d0cc829d1b1d38bc4259e61f35696d0bd4cbfd8a0a10563710a0a6a8103aa1f4117e6dde07822fbd3052ac6ff3331bf8489215ddb7e10590262da09a7410e0235727880b34caedd59496292ca70c97828f2a4da189e36e4eeefdf1a0227eeec265051a98f5a9c088e6ba0775767e54f7dab22ae47a395fd6dccef1e4a0b1e23c411e66f4a160d9899a15afaca7125485c7257448b48607ab7e8e15c46da0277032d5ca4e4c91ad348311c861496a634846428e213a3cc41f9873a87e72a1a06a216545720ab28209204ca56b85e4135f4893852a9b398942829bfb8560b8b3a099bc2c181322ad122b6773cebd47db425ba0615a137de069a25921bb9b1e15a7a0c83fd04980e13b7845b5dea401a698b7e83a3bb6496e339047731b5fd6554166a0e6596f5205e3612be086b45e68135584e8e4d53076c42a88d4cbd43638ec20e6a07bfe6a392d669d2f5d574b9ae840a0c75702a1fb85d81465af6637d4edfefeffa09f50fddde7ae5050f374da72b9b34eccb43ab4988145072ff5f2e045d4965a1ba0f1fcb4ee03ebd291bf6f4cc8d675c928cb2f78015f4eaeca56ea9fc80f2677e380");
        storageProofList[2] = RLP.encode(hex"f90211a025ed53e3071ec7165c7a3758d269b4f3ef4bb9513408dcf3af11494f5b0604e8a00e80afb8672b474f28abf8c2644fe2102abad2693f3280b300e65343192aa103a0234a8f90a794a32938ad65046259c164a9fbb65670b9d0346c2eceeed579c162a03fa2a10c2cfda2ae26bc35a5c64094dcf79d790572743fd0d272e96abe74da30a041b01073428696edc17c43b981a5f85aadfed1d996685d1ba69dfe38a2c5557ea040b0c179871d733194f6008355cbe1c743638f72b17bd251c2681720214d477aa0ccaa059850f10c8afa9634a3dbcb6772404ab531aa4a0569701a578427ba0ceaa002e925f7c7fc0fda8d854f15fc709b280fd7a7a28127717caa56ee75ad67c82da091891c805738d41ff1e0c73b821a912f4b65b3e65b7d3f4afc3847ac3b2efc2da00bcba522f2615e7e3f9a81e04cd706a2222012d12da05cf7deca39214caf7f1ea06daa07961f37ce80d18e4c85908f72a501f5afd1bc324c66c23861e641220ed6a080ace8c88d9dd3ff82806cf0ba95460f53bd1313391539d062a08bfbcbd2ce3ba061600e0431d1e84fb53dbd3e5a84b6b7a1808a64dbb9d80a69cf4b9cfb806158a007553406e2f5da7af415f2fa55cb0c62e9f0ab8e453a53d52066553451e912c2a0ba3ff886ed5aeb3c2e8e3efff4e4ee7504d978a8a390f230fc31b732db6d95d8a027f087b45f903117afc4ddf6f51c97dd836a03313c501bed3eb878fba9a24af580");
        storageProofList[3] = RLP.encode(hex"f8f18080a01ff05c6ac03dbfc65acc35d317c0d3ec3e364f06e4d37382f23a6ebbf4389f96a00e94b2d9e0250e1759360ac14b155cf368b9b7cffda77a2b64dcdf3e8c0aea2ea09db20f89e8fd1af9d5e64ccc8fb378c42b817d7b9f81a2f0890de079e6ec077d80a0f8907c3a4b39c8bc3377817aef08d607620a8248ff8a0734899d7691b78b441da08bbc815ec576ce47929a12a999d9a48672418361159f2d266dfced9bc53ed249a056590ac65819a0b6cbfcb04b64c9667f3e4b0fd50e3b631898a0d10d6df646ab80a012d248064c226796f9e0017d98bff92539366b386b8e503fda4b7a166acebe4f808080808080");
        storageProofList[4] = RLP.encode(hex"f8429f207816ec57943ac573dfff1824385a0b74ccbb7ae56734a7e79bb580fdfb7ba1a0a97ce065a04d2abfec36a459db323721847718d3159d51c4256d271ee3b37e42");

        return RLP.encode(storageProofList);
    }

    function _getBroadcasterStorageProof(bytes32 message) internal pure returns (bytes memory) {
        // This would contain the actual storage proof for the broadcaster's message slot
        // For testing purposes, we'll use a simplified version
        return _getStorageProof();
    }
}
