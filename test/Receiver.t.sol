// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console, Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Receiver} from "../src/contracts/Receiver.sol";
import {IReceiver} from "../src/contracts/interfaces/IReceiver.sol";
import {IBlockHashProver} from "../src/contracts/interfaces/IBlockHashProver.sol";
import {IOutbox} from "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import {IBlockHashProverPointer} from "../src/contracts/interfaces/IBlockHashProverPointer.sol";
import {BLOCK_HASH_PROVER_POINTER_SLOT} from "../src/contracts/BlockHashProverPointer.sol";
import {BlockHeaders} from "./utils/BlockHeaders.sol";
import {IBuffer} from "block-hash-pusher/contracts/interfaces/IBuffer.sol";
import {BufferMock} from "./mocks/BufferMock.sol";

import {ChildToParentProver as ArbChildToParentProver} from "../src/contracts/provers/arbitrum/ChildToParentProver.sol";
import {ParentToChildProver as ArbParentToChildProver} from "../src/contracts/provers/arbitrum/ParentToChildProver.sol";
import {ChildToParentProver as OPChildToParentProver} from "../src/contracts/provers/optimism/ChildToParentProver.sol";
import {
    ChildToParentProver as ZksyncChildToParentProver
} from "../src/contracts/provers/zksync/ChildToParentProver.sol";
import {BlockHashProverPointer} from "../src/contracts/BlockHashProverPointer.sol";
import {RLP} from "@openzeppelin/contracts/utils/RLP.sol";

interface IL1Block {
    function hash() external view returns (bytes32);
    function DEPOSITOR_ACCOUNT() external view returns (address);
    function setL1BlockValues(
        uint64 _number,
        uint64 _timestamp,
        uint256 _basefee,
        bytes32 _hash,
        uint64 _sequenceNumber,
        bytes32 _batcherHash,
        uint256 _l1FeeOverhead,
        uint256 _l1FeeScalar
    ) external;
}

contract ReceiverTest is Test {
    using stdJson for string;

    Receiver public receiver;

    uint256 public ethereumForkId;
    uint256 public arbitrumForkId;
    uint256 public optimismForkId;
    uint256 public zksyncForkId;

    IOutbox public outbox;

    address owner = makeAddr("owner");

    function setUp() public {
        ethereumForkId = vm.createFork(vm.envString("ETHEREUM_RPC_URL"));
        arbitrumForkId = vm.createFork(vm.envString("ARBITRUM_RPC_URL"));
        optimismForkId = vm.createFork(vm.envString("OPTIMISM_RPC_URL"));
        zksyncForkId = vm.createFork(vm.envString("ZKSYNC_RPC_URL"));

        vm.selectFork(arbitrumForkId);
        outbox = IOutbox(0x65f07C7D521164a4d5DaC6eB8Fac8DA067A3B78F);
    }

    function test_verifyBroadcastMessage_from_Ethereum_into_Arbitrum() public {
        vm.selectFork(arbitrumForkId);

        receiver = new Receiver();
        ArbChildToParentProver childToParentProver = new ArbChildToParentProver(block.chainid);

        BlockHashProverPointer blockHashProverPointer = new BlockHashProverPointer(owner);

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(childToParentProver));

        bytes32 message = 0x0000000000000000000000000000000000000000000000000000000074657374; // "test"
        address publisher = 0x9a56fFd72F4B526c523C733F1F74197A51c495E1;

        uint256 expectedSlot = uint256(keccak256(abi.encode(message, publisher)));

        string memory path = "test/payloads/ethereum/broadcast_proof_block_9496454.json";

        string memory json = vm.readFile(path);
        uint256 blockNumber = json.readUint(".blockNumber");
        bytes32 blockHash = json.readBytes32(".blockHash");
        address account = json.readAddress(".account");
        uint256 slot = json.readUint(".slot");
        bytes32 value = bytes32(json.readUint(".slotValue"));
        bytes memory rlpBlockHeader = json.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProof = json.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = json.readBytes(".rlpStorageProof");

        assertEq(expectedSlot, slot, "slot mismatch");

        bytes32 expectedBlockHash = keccak256(rlpBlockHeader);

        assertEq(blockHash, expectedBlockHash);

        IBuffer buffer = IBuffer(0x0000000048C4Ed10cF14A02B9E0AbDDA5227b071);

        address aliasedPusher = 0x6B6D4f3d0f0eFAeED2aeC9B59b67Ec62a4667e99;
        bytes32[] memory blockHashes = new bytes32[](1);
        blockHashes[0] = blockHash;

        vm.prank(aliasedPusher);
        buffer.receiveHashes(blockNumber, blockHashes);

        bytes memory input = abi.encode(rlpBlockHeader, account, expectedSlot, rlpAccountProof, rlpStorageProof);

        address[] memory route = new address[](1);
        route[0] = address(blockHashProverPointer);

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(blockNumber);

        bytes memory storageProofToLastProver = input;

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, bhpInputs: bhpInputs, storageProof: storageProofToLastProver});

        (bytes32 broadcasterId, uint256 timestamp) = receiver.verifyBroadcastMessage(remoteReadArgs, message, publisher);

        assertEq(
            broadcasterId,
            keccak256(
                abi.encode(
                    keccak256(
                        abi.encode(
                            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
                            address(blockHashProverPointer)
                        )
                    ),
                    account
                )
            ),
            "wrong broadcasterId"
        );
        assertEq(timestamp, uint256(value), "wrong timestamp");
    }

    function test_verifyBroadcastMessage_from_Arbitrum_into_Ethereum() public {
        vm.selectFork(ethereumForkId);

        receiver = new Receiver();
        ArbParentToChildProver parentToChildProver = new ArbParentToChildProver(address(outbox), 3);

        BlockHashProverPointer blockHashProverPointer = new BlockHashProverPointer(owner);

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(parentToChildProver));

        bytes32 message = 0x0000000000000000000000000000000000000000000000000000000074657374; // "test"
        address publisher = 0x9a56fFd72F4B526c523C733F1F74197A51c495E1;

        uint256 expectedSlot = uint256(keccak256(abi.encode(message, publisher)));

        string memory path = "test/payloads/arbitrum/broadcast_proof_block_208802827.json";

        string memory json = vm.readFile(path);
        bytes32 blockHash = json.readBytes32(".blockHash");
        address account = json.readAddress(".account");
        uint256 slot = json.readUint(".slot");
        bytes32 value = bytes32(json.readUint(".slotValue"));
        bytes memory rlpBlockHeader = json.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProof = json.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = json.readBytes(".rlpStorageProof");
        bytes32 sendRoot = json.readBytes32(".sendRoot");

        assertEq(expectedSlot, slot, "slot mismatch");

        bytes32 expectedBlockHash = keccak256(rlpBlockHeader);

        assertEq(blockHash, expectedBlockHash);

        bytes memory input = abi.encode(rlpBlockHeader, account, expectedSlot, rlpAccountProof, rlpStorageProof);

        address rollup = 0x042B2E6C5E99d4c521bd49beeD5E99651D9B0Cf4;

        vm.prank(rollup);
        outbox.updateSendRoot(sendRoot, blockHash);

        address[] memory route = new address[](1);
        route[0] = address(blockHashProverPointer);

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(sendRoot);

        bytes memory storageProofToLastProver = input;

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, bhpInputs: bhpInputs, storageProof: storageProofToLastProver});

        (bytes32 broadcasterId, uint256 timestamp) = receiver.verifyBroadcastMessage(remoteReadArgs, message, publisher);

        assertEq(
            broadcasterId,
            keccak256(
                abi.encode(
                    keccak256(
                        abi.encode(
                            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
                            address(blockHashProverPointer)
                        )
                    ),
                    account
                )
            ),
            "wrong broadcasterId"
        );
        assertEq(timestamp, uint256(value), "wrong timestamp");
    }

    function test_verifyBroadcastMessage_from_Ethereum_into_Optimism() public {
        vm.selectFork(optimismForkId);
        receiver = new Receiver();

        OPChildToParentProver childToParentProver = new OPChildToParentProver(block.chainid);

        BlockHashProverPointer blockHashProverPointer = new BlockHashProverPointer(owner);

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(childToParentProver));

        bytes32 message = 0x0000000000000000000000000000000000000000000000000000000074657374; // "test"
        address publisher = 0x9a56fFd72F4B526c523C733F1F74197A51c495E1;

        uint256 expectedSlot = uint256(keccak256(abi.encode(message, publisher)));

        string memory path = "test/payloads/ethereum/broadcast_proof_block_9496454.json";

        string memory json = vm.readFile(path);
        uint256 blockNumber = json.readUint(".blockNumber");
        bytes32 blockHash = json.readBytes32(".blockHash");
        address account = json.readAddress(".account");
        uint256 slot = json.readUint(".slot");
        bytes32 value = bytes32(json.readUint(".slotValue"));
        bytes memory rlpBlockHeader = json.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProof = json.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = json.readBytes(".rlpStorageProof");

        assertEq(expectedSlot, slot, "slot mismatch");

        bytes32 expectedBlockHash = keccak256(rlpBlockHeader);

        assertEq(blockHash, expectedBlockHash);
        bytes memory input = abi.encode(rlpBlockHeader, account, slot, rlpAccountProof, rlpStorageProof);

        IL1Block l1Block = IL1Block(childToParentProver.l1BlockPredeploy());

        vm.prank(l1Block.DEPOSITOR_ACCOUNT());
        l1Block.setL1BlockValues(
            uint64(blockNumber), uint64(block.timestamp), block.basefee, blockHash, 0, bytes32(0), 0, 0
        );

        address[] memory route = new address[](1);
        route[0] = address(blockHashProverPointer);

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = bytes("");

        bytes memory storageProofToLastProver = input;

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, bhpInputs: bhpInputs, storageProof: storageProofToLastProver});

        (bytes32 broadcasterId, uint256 timestamp) = receiver.verifyBroadcastMessage(remoteReadArgs, message, publisher);

        assertEq(
            broadcasterId,
            keccak256(
                abi.encode(
                    keccak256(
                        abi.encode(
                            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
                            address(blockHashProverPointer)
                        )
                    ),
                    account
                )
            ),
            "wrong broadcasterId"
        );
        assertEq(timestamp, uint256(value), "wrong timestamp");
    }

    function test_updateBlockHashProverCopy_from_Arbitrum_into_OP() public {
        vm.selectFork(optimismForkId);

        receiver = new Receiver();

        OPChildToParentProver childToParentProver = new OPChildToParentProver(block.chainid);

        BlockHashProverPointer blockHashProverPointer = new BlockHashProverPointer(owner);

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(childToParentProver));

        uint256 expectedSlot = uint256(keccak256("eip7888.pointer.slot")) - 1;

        string memory path = "test/payloads/ethereum/arb_pointer_proof_block_9574620.json";

        string memory json = vm.readFile(path);
        uint256 blockNumber = json.readUint(".blockNumber");
        bytes32 blockHash = json.readBytes32(".blockHash");
        address account = json.readAddress(".account");
        uint256 slot = json.readUint(".slot");
        bytes32 value = bytes32(json.readUint(".slotValue"));
        bytes memory rlpBlockHeader = json.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProof = json.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = json.readBytes(".rlpStorageProof");

        assertEq(expectedSlot, slot, "slot mismatch");

        bytes32 expectedBlockHash = keccak256(rlpBlockHeader);

        assertEq(blockHash, expectedBlockHash);
        bytes memory input = abi.encode(rlpBlockHeader, account, slot, rlpAccountProof, rlpStorageProof);

        IL1Block l1Block = IL1Block(childToParentProver.l1BlockPredeploy());

        vm.prank(l1Block.DEPOSITOR_ACCOUNT());
        l1Block.setL1BlockValues(
            uint64(blockNumber), uint64(block.timestamp), block.basefee, blockHash, 0, bytes32(0), 0, 0
        );

        address[] memory route = new address[](1);
        route[0] = address(blockHashProverPointer);

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = bytes("");

        bytes memory storageProofToLastProver = input;

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, bhpInputs: bhpInputs, storageProof: storageProofToLastProver});

        ArbParentToChildProver arbParentToChildProverCopy = new ArbParentToChildProver(address(outbox), 3);

        bytes32 bhpPointerId = receiver.updateBlockHashProverCopy(remoteReadArgs, arbParentToChildProverCopy);

        assertEq(
            bhpPointerId,
            keccak256(
                abi.encode(
                    keccak256(
                        abi.encode(
                            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
                            address(blockHashProverPointer)
                        )
                    ),
                    account
                )
            ),
            "wrong broadcasterId"
        );
        assertEq(address(arbParentToChildProverCopy).codehash, value, "wrong storage slot value");
    }

    function test_verifyBroadcastMessage_from_Arbitrum_into_OP() public {
        vm.selectFork(optimismForkId);

        receiver = new Receiver();

        OPChildToParentProver childToParentProver = new OPChildToParentProver(block.chainid);

        BlockHashProverPointer blockHashProverPointer = new BlockHashProverPointer(owner);

        ArbParentToChildProver arbParentToChildProverCopy = new ArbParentToChildProver(address(outbox), 3);

        address arbParentToChildProverPointerAddress;

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(childToParentProver));
        // Update the Arbitrum Prover (ParentToChildProver) copy on OP chain
        {
            uint256 expectedSlot = uint256(keccak256("eip7888.pointer.slot")) - 1;

            string memory path = "test/payloads/ethereum/arb_pointer_proof_block_9574620.json";

            string memory json = vm.readFile(path);
            uint256 blockNumber = json.readUint(".blockNumber");
            bytes32 blockHash = json.readBytes32(".blockHash");
            address account = json.readAddress(".account");
            uint256 slot = json.readUint(".slot");
            bytes32 value = bytes32(json.readUint(".slotValue"));
            bytes memory rlpBlockHeader = json.readBytes(".rlpBlockHeader");
            bytes memory rlpAccountProof = json.readBytes(".rlpAccountProof");
            bytes memory rlpStorageProof = json.readBytes(".rlpStorageProof");

            arbParentToChildProverPointerAddress = account;

            assertEq(expectedSlot, slot, "slot mismatch");

            bytes32 expectedBlockHash = keccak256(rlpBlockHeader);

            assertEq(blockHash, expectedBlockHash);
            bytes memory inputForOPChildToParentProver =
                abi.encode(rlpBlockHeader, account, slot, rlpAccountProof, rlpStorageProof);

            IL1Block l1Block = IL1Block(childToParentProver.l1BlockPredeploy());

            vm.prank(l1Block.DEPOSITOR_ACCOUNT());
            l1Block.setL1BlockValues(
                uint64(blockNumber), uint64(block.timestamp), block.basefee, blockHash, 0, bytes32(0), 0, 0
            );

            address[] memory route = new address[](1);
            route[0] = address(blockHashProverPointer);

            bytes[] memory bhpInputs = new bytes[](1);
            bhpInputs[0] = bytes("");

            bytes memory storageProofToLastProver = inputForOPChildToParentProver;

            IReceiver.RemoteReadArgs memory remoteReadArgs =
                IReceiver.RemoteReadArgs({route: route, bhpInputs: bhpInputs, storageProof: storageProofToLastProver});

            bytes32 bhpPointerId = receiver.updateBlockHashProverCopy(remoteReadArgs, arbParentToChildProverCopy);

            assertEq(
                bhpPointerId,
                keccak256(
                    abi.encode(
                        keccak256(
                            abi.encode(
                                bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
                                address(blockHashProverPointer)
                            )
                        ),
                        account
                    )
                ),
                "wrong broadcasterId"
            );
            assertEq(address(arbParentToChildProverCopy).codehash, value, "wrong storage slot value");
        }

        // Construct the route to verify a message broadcasted on Arbitrum chain in OP
        // We need to construct three inputs: one for OPChildToParentProver getTargetBlockHash,
        // one for ArbParentToChildProver verifyTargetBlockHash, and one for ArbParentToChildProver verifyStorageSlot
        // the input to verifyStorageSlot is the proof of the broadcasted message itself.
        // the input for verifyTargetBlockHash is the storage proof of the slot on the outbox contract.

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

        IL1Block l1Block = IL1Block(childToParentProver.l1BlockPredeploy());

        vm.prank(l1Block.DEPOSITOR_ACCOUNT());
        l1Block.setL1BlockValues(
            uint64(blockNumberEthereum), uint64(block.timestamp), block.basefee, blockHashEthereum, 0, bytes32(0), 0, 0
        );

        address[] memory route = new address[](2);
        route[0] = address(blockHashProverPointer);
        route[1] = arbParentToChildProverPointerAddress;

        bytes memory input0 = bytes("");
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

        bytes32 message = 0x0000000000000000000000000000000000000000000000000000000074657374; // "test"
        address publisher = 0x9a56fFd72F4B526c523C733F1F74197A51c495E1;

        (bytes32 broadcasterId, uint256 timestamp) = receiver.verifyBroadcastMessage(remoteReadArgs, message, publisher);

        bytes32 expectedBroadcasterId = keccak256(
            abi.encode(
                keccak256(
                    abi.encode(
                        keccak256(
                            abi.encode(
                                bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
                                address(blockHashProverPointer)
                            )
                        ),
                        arbParentToChildProverPointerAddress
                    )
                ),
                accountArbitrum
            )
        );

        assertEq(broadcasterId, expectedBroadcasterId, "wrong broadcasterId");
        assertEq(timestamp, uint256(valueArbitrum), "wrong timestamp");
    }

    function test_updateBlockHashProverCopy_from_Arbitrum_into_Zksync() public {
        vm.selectFork(zksyncForkId);

        receiver = new Receiver();

        BufferMock buffer = new BufferMock();

        ZksyncChildToParentProver childToParentProver = new ZksyncChildToParentProver(address(buffer), block.chainid);

        BlockHashProverPointer blockHashProverPointer = new BlockHashProverPointer(owner);

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(childToParentProver));

        uint256 expectedSlot = uint256(keccak256("eip7888.pointer.slot")) - 1;

        string memory path = "test/payloads/ethereum/arb_pointer_proof_block_9574620.json";

        string memory json = vm.readFile(path);
        uint256 blockNumber = json.readUint(".blockNumber");
        bytes32 blockHash = json.readBytes32(".blockHash");
        address account = json.readAddress(".account");
        uint256 slot = json.readUint(".slot");
        bytes32 value = bytes32(json.readUint(".slotValue"));
        bytes memory rlpBlockHeader = json.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProof = json.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = json.readBytes(".rlpStorageProof");

        assertEq(expectedSlot, slot, "slot mismatch");

        bytes32 expectedBlockHash = keccak256(rlpBlockHeader);

        assertEq(blockHash, expectedBlockHash);
        bytes memory input = abi.encode(rlpBlockHeader, account, slot, rlpAccountProof, rlpStorageProof);

        bytes32[] memory blockHashes = new bytes32[](1);
        blockHashes[0] = blockHash;

        buffer.receiveHashes(blockNumber, blockHashes);

        address[] memory route = new address[](1);
        route[0] = address(blockHashProverPointer);

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(blockNumber);

        bytes memory storageProofToLastProver = input;

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, bhpInputs: bhpInputs, storageProof: storageProofToLastProver});

        ArbParentToChildProver arbParentToChildProverCopy = new ArbParentToChildProver(address(outbox), 3);

        bytes32 bhpPointerId = receiver.updateBlockHashProverCopy(remoteReadArgs, arbParentToChildProverCopy);

        assertEq(
            bhpPointerId,
            keccak256(
                abi.encode(
                    keccak256(
                        abi.encode(
                            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
                            address(blockHashProverPointer)
                        )
                    ),
                    account
                )
            ),
            "wrong broadcasterId"
        );
        assertEq(address(arbParentToChildProverCopy).codehash, value, "wrong storage slot value");
    }

    function test_verifyBroadcastMessage_from_Arbitrum_into_ZkSync() public {
        vm.selectFork(zksyncForkId);

        receiver = new Receiver();

        BufferMock buffer = new BufferMock();

        ZksyncChildToParentProver childToParentProver = new ZksyncChildToParentProver(address(buffer), block.chainid);

        BlockHashProverPointer blockHashProverPointer = new BlockHashProverPointer(owner);

        ArbParentToChildProver arbParentToChildProverCopy = new ArbParentToChildProver(address(outbox), 3);

        address arbParentToChildProverPointerAddress;

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(childToParentProver));
        // Update the Arbitrum Prover (ParentToChildProver) copy on ZKSync chain
        {
            uint256 expectedSlot = uint256(keccak256("eip7888.pointer.slot")) - 1;

            string memory path = "test/payloads/ethereum/arb_pointer_proof_block_9574620.json";

            string memory json = vm.readFile(path);
            uint256 blockNumber = json.readUint(".blockNumber");
            bytes32 blockHash = json.readBytes32(".blockHash");
            address account = json.readAddress(".account");
            uint256 slot = json.readUint(".slot");
            bytes32 value = bytes32(json.readUint(".slotValue"));
            bytes memory rlpBlockHeader = json.readBytes(".rlpBlockHeader");
            bytes memory rlpAccountProof = json.readBytes(".rlpAccountProof");
            bytes memory rlpStorageProof = json.readBytes(".rlpStorageProof");

            arbParentToChildProverPointerAddress = account;

            assertEq(expectedSlot, slot, "slot mismatch");

            bytes32 expectedBlockHash = keccak256(rlpBlockHeader);

            assertEq(blockHash, expectedBlockHash);
            bytes memory inputForOPChildToParentProver =
                abi.encode(rlpBlockHeader, account, slot, rlpAccountProof, rlpStorageProof);

            bytes32[] memory blockHashes = new bytes32[](1);
            blockHashes[0] = blockHash;

            buffer.receiveHashes(blockNumber, blockHashes);

            address[] memory route = new address[](1);
            route[0] = address(blockHashProverPointer);

            bytes[] memory bhpInputs = new bytes[](1);
            bhpInputs[0] = abi.encode(blockNumber);

            bytes memory storageProofToLastProver = inputForOPChildToParentProver;

            IReceiver.RemoteReadArgs memory remoteReadArgs =
                IReceiver.RemoteReadArgs({route: route, bhpInputs: bhpInputs, storageProof: storageProofToLastProver});

            bytes32 bhpPointerId = receiver.updateBlockHashProverCopy(remoteReadArgs, arbParentToChildProverCopy);

            assertEq(
                bhpPointerId,
                keccak256(
                    abi.encode(
                        keccak256(
                            abi.encode(
                                bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
                                address(blockHashProverPointer)
                            )
                        ),
                        account
                    )
                ),
                "wrong broadcasterId"
            );
            assertEq(address(arbParentToChildProverCopy).codehash, value, "wrong storage slot value");
        }

        // Construct the route to verify a message broadcasted on Arbitrum chain in ZkSync
        // We need to construct three inputs: one for ZksyncChildToParentProver getTargetBlockHash,
        // one for ArbParentToChildProver verifyTargetBlockHash, and one for ArbParentToChildProver verifyStorageSlot
        // the input to verifyStorageSlot is the proof of the broadcasted message itself.
        // the input for verifyTargetBlockHash is the storage proof of the slot on the outbox contract.

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

        bytes32[] memory blockHashes = new bytes32[](1);
        blockHashes[0] = blockHashEthereum;

        buffer.receiveHashes(blockNumberEthereum, blockHashes);

        address[] memory route = new address[](2);
        route[0] = address(blockHashProverPointer);
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

        bytes32 message = 0x0000000000000000000000000000000000000000000000000000000074657374; // "test"
        address publisher = 0x9a56fFd72F4B526c523C733F1F74197A51c495E1;

        (bytes32 broadcasterId, uint256 timestamp) = receiver.verifyBroadcastMessage(remoteReadArgs, message, publisher);

        bytes32 expectedBroadcasterId = keccak256(
            abi.encode(
                keccak256(
                    abi.encode(
                        keccak256(
                            abi.encode(
                                bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
                                address(blockHashProverPointer)
                            )
                        ),
                        arbParentToChildProverPointerAddress
                    )
                ),
                accountArbitrum
            )
        );

        assertEq(broadcasterId, expectedBroadcasterId, "wrong broadcasterId");
        assertEq(timestamp, uint256(valueArbitrum), "wrong timestamp");
    }
}

