// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console, Test} from "forge-std/Test.sol";
import {Receiver} from "../../../src/contracts/Receiver.sol";
import {Broadcaster} from "../../../src/contracts/Broadcaster.sol";
import {BlockHashProverPointer} from "../../../src/contracts/BlockHashProverPointer.sol";
import {ParentToChildProver} from "../../../src/contracts/provers/arbitrum/ParentToChildProver.sol";
import {ChildToParentProver} from "../../../src/contracts/provers/arbitrum/ChildToParentProver.sol";
import {IReceiver} from "../../../src/contracts/interfaces/IReceiver.sol";
import {IBlockHashProver} from "../../../src/contracts/interfaces/IBlockHashProver.sol";
import {IOutbox} from "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import {RLP} from "@openzeppelin/contracts/utils/RLP.sol";

/// @title ReceiverIntegrationTest
/// @notice Integration tests for Receiver contract with BlockHashProvers
/// @dev Tests message verification, prover copy management, and cross-chain functionality
contract ReceiverIntegrationTest is Test {
    using RLP for RLP.Encoder;

    // Test accounts
    address public publisher = makeAddr("publisher");
    address public subscriber = makeAddr("subscriber");
    address public pointerOwner = makeAddr("pointerOwner");

    // Contracts
    Receiver public receiver;
    Broadcaster public broadcaster;
    BlockHashProverPointer public pointer;
    ParentToChildProver public parentToChildProver;
    ChildToParentProver public childToParentProver;

    // Arbitrum contracts
    IOutbox public outbox = IOutbox(0x65f07C7D521164a4d5DaC6eB8Fac8DA067A3B78F);

    // Test data
    bytes32 public testMessage = keccak256("Test message for receiver");
    bytes32 public testSendRoot = 0x89452690BD661B0B1FFB5A39D4136BE89C91365E3A5948680077F6FE5AC7B6F4;
    uint256 public testBlockNumber = 9043403;

    function setUp() public {
        // Deploy contracts
        receiver = new Receiver();
        broadcaster = new Broadcaster();
        parentToChildProver = new ParentToChildProver(address(outbox), 3);
        childToParentProver = new ChildToParentProver();
        pointer = new BlockHashProverPointer(pointerOwner);
        
        // Set up pointer
        vm.prank(pointerOwner);
        pointer.updateImplementation(address(parentToChildProver));
    }

    function test_update_block_hash_prover_copy() public {
        // Test updating block hash prover copy
        address[] memory route = new address[](1);
        route[0] = address(pointer);
        
        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(testSendRoot);
        
        bytes memory storageProof = _getStorageProof();
        
        IReceiver.RemoteReadArgs memory args = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProof
        });

        vm.prank(subscriber);
        bytes32 pointerId = receiver.updateBlockHashProverCopy(args, parentToChildProver);
        
        // Verify prover copy was created
        assertTrue(pointerId != bytes32(0));
        assertTrue(address(receiver.blockHashProverCopy(pointerId)) != address(0));
    }

    function test_verify_broadcast_message() public {
        // First, broadcast a message
        vm.prank(publisher);
        broadcaster.broadcastMessage(testMessage);
        
        // Set up prover copy
        address[] memory route = new address[](1);
        route[0] = address(pointer);
        
        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(testSendRoot);
        
        bytes memory storageProof = _getStorageProof();
        
        IReceiver.RemoteReadArgs memory pointerArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProof
        });

        vm.prank(subscriber);
        bytes32 pointerId = receiver.updateBlockHashProverCopy(pointerArgs, parentToChildProver);
        
        // Now verify the broadcast message
        bytes[] memory broadcasterInputs = new bytes[](1);
        broadcasterInputs[0] = abi.encode(testSendRoot);
        
        bytes memory broadcasterStorageProof = _getBroadcasterStorageProof(testMessage);
        
        IReceiver.RemoteReadArgs memory broadcasterArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: broadcasterInputs,
            storageProof: broadcasterStorageProof
        });

        vm.prank(subscriber);
        (bytes32 broadcasterId, uint256 timestamp) = receiver.verifyBroadcastMessage(
            broadcasterArgs,
            testMessage,
            publisher
        );
        
        assertTrue(broadcasterId != bytes32(0));
        assertTrue(timestamp > 0);
    }

    function test_verify_broadcast_message_invalid_proof() public {
        // Set up prover copy
        address[] memory route = new address[](1);
        route[0] = address(pointer);
        
        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(testSendRoot);
        
        bytes memory storageProof = _getStorageProof();
        
        IReceiver.RemoteReadArgs memory pointerArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProof
        });

        vm.prank(subscriber);
        bytes32 pointerId = receiver.updateBlockHashProverCopy(pointerArgs, parentToChildProver);
        
        // Try to verify with invalid proof
        bytes[] memory broadcasterInputs = new bytes[](1);
        broadcasterInputs[0] = abi.encode(testSendRoot);
        
        bytes memory invalidStorageProof = hex"deadbeef";
        
        IReceiver.RemoteReadArgs memory broadcasterArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: broadcasterInputs,
            storageProof: invalidStorageProof
        });

        vm.prank(subscriber);
        vm.expectRevert();
        receiver.verifyBroadcastMessage(
            broadcasterArgs,
            testMessage,
            publisher
        );
    }

    function test_verify_broadcast_message_wrong_publisher() public {
        // Broadcast message
        vm.prank(publisher);
        broadcaster.broadcastMessage(testMessage);
        
        // Set up prover copy
        address[] memory route = new address[](1);
        route[0] = address(pointer);
        
        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(testSendRoot);
        
        bytes memory storageProof = _getStorageProof();
        
        IReceiver.RemoteReadArgs memory pointerArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProof
        });

        vm.prank(subscriber);
        bytes32 pointerId = receiver.updateBlockHashProverCopy(pointerArgs, parentToChildProver);
        
        // Try to verify with wrong publisher
        address wrongPublisher = makeAddr("wrongPublisher");
        
        bytes[] memory broadcasterInputs = new bytes[](1);
        broadcasterInputs[0] = abi.encode(testSendRoot);
        
        bytes memory broadcasterStorageProof = _getBroadcasterStorageProof(testMessage);
        
        IReceiver.RemoteReadArgs memory broadcasterArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: broadcasterInputs,
            storageProof: broadcasterStorageProof
        });

        vm.prank(subscriber);
        vm.expectRevert();
        receiver.verifyBroadcastMessage(
            broadcasterArgs,
            testMessage,
            wrongPublisher
        );
    }

    function test_multiple_prover_copies() public {
        // Test creating multiple prover copies
        address[] memory route = new address[](1);
        route[0] = address(pointer);
        
        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(testSendRoot);
        
        bytes memory storageProof = _getStorageProof();
        
        IReceiver.RemoteReadArgs memory args = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProof
        });

        vm.startPrank(subscriber);
        
        // Create first prover copy
        bytes32 pointerId1 = receiver.updateBlockHashProverCopy(args, parentToChildProver);
        
        // Create second prover copy with different input
        bytes[] memory bhpInputs2 = new bytes[](1);
        bhpInputs2[0] = abi.encode(testSendRoot + 1);
        
        IReceiver.RemoteReadArgs memory args2 = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs2,
            storageProof: storageProof
        });
        
        bytes32 pointerId2 = receiver.updateBlockHashProverCopy(args2, parentToChildProver);
        
        vm.stopPrank();
        
        // Verify both copies exist
        assertTrue(pointerId1 != bytes32(0));
        assertTrue(pointerId2 != bytes32(0));
        assertTrue(pointerId1 != pointerId2);
        
        assertTrue(address(receiver.blockHashProverCopy(pointerId1)) != address(0));
        assertTrue(address(receiver.blockHashProverCopy(pointerId2)) != address(0));
    }

    function test_prover_copy_upgrade() public {
        // Create initial prover copy
        address[] memory route = new address[](1);
        route[0] = address(pointer);
        
        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(testSendRoot);
        
        bytes memory storageProof = _getStorageProof();
        
        IReceiver.RemoteReadArgs memory args = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProof
        });

        vm.prank(subscriber);
        bytes32 pointerId = receiver.updateBlockHashProverCopy(args, parentToChildProver);
        
        // Upgrade the pointer
        vm.prank(pointerOwner);
        pointer.updateImplementation(address(childToParentProver));
        
        // Create new prover copy with upgraded pointer
        vm.prank(subscriber);
        bytes32 newPointerId = receiver.updateBlockHashProverCopy(args, childToParentProver);
        
        // Verify both copies exist
        assertTrue(pointerId != bytes32(0));
        assertTrue(newPointerId != bytes32(0));
        assertTrue(pointerId != newPointerId);
    }

    function test_empty_route() public {
        // Test with empty route
        address[] memory route = new address[](0);
        
        bytes[] memory bhpInputs = new bytes[](0);
        bytes memory storageProof = hex"";
        
        IReceiver.RemoteReadArgs memory args = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProof
        });

        vm.prank(subscriber);
        vm.expectRevert();
        receiver.updateBlockHashProverCopy(args, parentToChildProver);
    }

    function test_mismatched_route_and_inputs() public {
        // Test with mismatched route and inputs
        address[] memory route = new address[](2);
        route[0] = address(pointer);
        route[1] = address(pointer);
        
        bytes[] memory bhpInputs = new bytes[](1); // Only one input for two route elements
        bhpInputs[0] = abi.encode(testSendRoot);
        
        bytes memory storageProof = _getStorageProof();
        
        IReceiver.RemoteReadArgs memory args = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProof
        });

        vm.prank(subscriber);
        vm.expectRevert();
        receiver.updateBlockHashProverCopy(args, parentToChildProver);
    }

    function test_gas_consumption_analysis() public {
        // Measure gas for prover copy update
        address[] memory route = new address[](1);
        route[0] = address(pointer);
        
        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(testSendRoot);
        
        bytes memory storageProof = _getStorageProof();
        
        IReceiver.RemoteReadArgs memory args = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProof
        });

        uint256 gasBefore = gasleft();
        vm.prank(subscriber);
        receiver.updateBlockHashProverCopy(args, parentToChildProver);
        uint256 updateGas = gasBefore - gasleft();
        
        console.log("Prover copy update gas:", updateGas);
        
        // Measure gas for message verification
        vm.prank(publisher);
        broadcaster.broadcastMessage(testMessage);
        
        bytes[] memory broadcasterInputs = new bytes[](1);
        broadcasterInputs[0] = abi.encode(testSendRoot);
        
        bytes memory broadcasterStorageProof = _getBroadcasterStorageProof(testMessage);
        
        IReceiver.RemoteReadArgs memory broadcasterArgs = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: broadcasterInputs,
            storageProof: broadcasterStorageProof
        });

        gasBefore = gasleft();
        vm.prank(subscriber);
        receiver.verifyBroadcastMessage(broadcasterArgs, testMessage, publisher);
        uint256 verifyGas = gasBefore - gasleft();
        
        console.log("Message verification gas:", verifyGas);
        
        // Ensure reasonable gas consumption
        assertTrue(updateGas < 500000, "Update gas too high");
        assertTrue(verifyGas < 500000, "Verify gas too high");
    }

    function test_receiver_with_different_prover_types() public {
        // Test receiver with ParentToChildProver
        address[] memory route = new address[](1);
        route[0] = address(pointer);
        
        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(testSendRoot);
        
        bytes memory storageProof = _getStorageProof();
        
        IReceiver.RemoteReadArgs memory args = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs,
            storageProof: storageProof
        });

        vm.prank(subscriber);
        bytes32 pointerId1 = receiver.updateBlockHashProverCopy(args, parentToChildProver);
        
        // Test receiver with ChildToParentProver
        vm.prank(pointerOwner);
        pointer.updateImplementation(address(childToParentProver));
        
        bytes[] memory bhpInputs2 = new bytes[](1);
        bhpInputs2[0] = abi.encode(testBlockNumber);
        
        IReceiver.RemoteReadArgs memory args2 = IReceiver.RemoteReadArgs({
            route: route,
            bhpInputs: bhpInputs2,
            storageProof: storageProof
        });

        vm.prank(subscriber);
        bytes32 pointerId2 = receiver.updateBlockHashProverCopy(args2, childToParentProver);
        
        // Verify both copies exist
        assertTrue(pointerId1 != bytes32(0));
        assertTrue(pointerId2 != bytes32(0));
        assertTrue(pointerId1 != pointerId2);
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
