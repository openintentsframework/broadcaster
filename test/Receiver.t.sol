// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console, Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Receiver} from "../src/contracts/Receiver.sol";
import {IReceiver} from "../src/contracts/interfaces/IReceiver.sol";
import {IStateProver} from "../src/contracts/interfaces/IStateProver.sol";
import {IOutbox} from "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import {IStateProverPointer} from "../src/contracts/interfaces/IStateProverPointer.sol";
import {BLOCK_HASH_PROVER_POINTER_SLOT} from "../src/contracts/StateProverPointer.sol";
import {BlockHeaders} from "./utils/BlockHeaders.sol";
import {IBuffer} from "block-hash-pusher/contracts/interfaces/IBuffer.sol";
import {BufferMock} from "./mocks/BufferMock.sol";

import {ChildToParentProver as ArbChildToParentProver} from "../src/contracts/provers/arbitrum/ChildToParentProver.sol";
import {ParentToChildProver as ArbParentToChildProver} from "../src/contracts/provers/arbitrum/ParentToChildProver.sol";
import {ChildToParentProver as OPChildToParentProver} from "../src/contracts/provers/optimism/ChildToParentProver.sol";
import {ChildToParentProver as LineaChildToParentProver} from "../src/contracts/provers/linea/ChildToParentProver.sol";
import {ParentToChildProver as LineaParentToChildProver} from "../src/contracts/provers/linea/ParentToChildProver.sol";
import {
    ChildToParentProver as ZksyncChildToParentProver
} from "../src/contracts/provers/zksync/ChildToParentProver.sol";
import {
    ChildToParentProver as ScrollChildToParentProver
} from "../src/contracts/provers/scroll/ChildToParentProver.sol";
import {
    ParentToChildProver as ScrollParentToChildProver
} from "../src/contracts/provers/scroll/ParentToChildProver.sol";
import {StateProverPointer} from "../src/contracts/StateProverPointer.sol";
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
    uint256 public ethereumChainId;
    uint256 public arbitrumForkId;
    uint256 public optimismForkId;
    uint256 public lineaForkId;
    uint256 public zksyncForkId;
    uint256 public scrollForkId;

    IOutbox public outbox;

    // On-chain deployed ArbParentToChildProver on Sepolia
    address constant ON_CHAIN_ARB_PROVER = 0x9e8BA3Ce052f2139f824885a78240839749F3370;

    address owner = makeAddr("owner");

    /// @dev Helper to get a copy of the on-chain ArbParentToChildProver with matching bytecode
    function _getOnChainArbProverCopy() internal returns (ArbParentToChildProver) {
        // Save current fork
        uint256 currentFork = vm.activeFork();

        // Switch to Ethereum to get the on-chain bytecode
        vm.selectFork(ethereumForkId);
        bytes memory proverBytecode = ON_CHAIN_ARB_PROVER.code;

        // Switch back to original fork
        vm.selectFork(currentFork);

        // Deploy using vm.etch to get exact same bytecode/codehash
        address proverCopy = makeAddr("arbProverCopy");
        vm.etch(proverCopy, proverBytecode);

        return ArbParentToChildProver(proverCopy);
    }

    function setUp() public {
        ethereumForkId = vm.createFork(vm.envString("ETHEREUM_RPC_URL"));
        arbitrumForkId = vm.createFork(vm.envString("ARBITRUM_RPC_URL"));
        optimismForkId = vm.createFork(vm.envString("OPTIMISM_RPC_URL"));
        lineaForkId = vm.createFork(vm.envString("LINEA_RPC_URL"));
        zksyncForkId = vm.createFork(vm.envString("ZKSYNC_RPC_URL"));
        scrollForkId = vm.createFork(vm.envString("SCROLL_RPC_URL"));

        vm.selectFork(ethereumForkId);
        ethereumChainId = block.chainid;

        vm.selectFork(arbitrumForkId);
        outbox = IOutbox(0x65f07C7D521164a4d5DaC6eB8Fac8DA067A3B78F);
    }

    function test_verifyBroadcastMessage_from_Ethereum_into_Arbitrum() public {
        vm.selectFork(arbitrumForkId);

        receiver = new Receiver();
        ArbChildToParentProver childToParentProver = new ArbChildToParentProver(block.chainid);

        StateProverPointer blockHashProverPointer = new StateProverPointer(owner);

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

        bytes[] memory scpInputs = new bytes[](1);
        scpInputs[0] = abi.encode(blockNumber);

        bytes memory storageProofToLastProver = input;

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, scpInputs: scpInputs, proof: storageProofToLastProver});

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
        ArbParentToChildProver parentToChildProver = _getOnChainArbProverCopy();

        StateProverPointer blockHashProverPointer = new StateProverPointer(owner);

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

        bytes[] memory scpInputs = new bytes[](1);
        scpInputs[0] = abi.encode(sendRoot);

        bytes memory storageProofToLastProver = input;

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, scpInputs: scpInputs, proof: storageProofToLastProver});

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

        StateProverPointer blockHashProverPointer = new StateProverPointer(owner);

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

        bytes[] memory scpInputs = new bytes[](1);
        scpInputs[0] = bytes("");

        bytes memory storageProofToLastProver = input;

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, scpInputs: scpInputs, proof: storageProofToLastProver});

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

    function test_updateStateProverCopy_from_Arbitrum_into_OP() public {
        vm.selectFork(optimismForkId);

        receiver = new Receiver();

        OPChildToParentProver childToParentProver = new OPChildToParentProver(block.chainid);

        StateProverPointer blockHashProverPointer = new StateProverPointer(owner);

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(childToParentProver));

        uint256 expectedSlot = uint256(keccak256("eip7888.pointer.slot")) - 1;

        string memory path = "test/payloads/ethereum/arb_pointer_proof_block_9868604.json";

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

        bytes[] memory scpInputs = new bytes[](1);
        scpInputs[0] = bytes("");

        bytes memory storageProofToLastProver = input;

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, scpInputs: scpInputs, proof: storageProofToLastProver});

        ArbParentToChildProver arbParentToChildProverCopy = _getOnChainArbProverCopy();

        bytes32 bhpPointerId = receiver.updateStateProverCopy(remoteReadArgs, arbParentToChildProverCopy);

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

    function test_updateStateProverCopy_from_Arbitrum_into_OP_reverts_when_different_code_hash() public {
        vm.selectFork(optimismForkId);

        receiver = new Receiver();

        OPChildToParentProver childToParentProver = new OPChildToParentProver(block.chainid);

        StateProverPointer blockHashProverPointer = new StateProverPointer(owner);

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

        bytes[] memory scpInputs = new bytes[](1);
        scpInputs[0] = bytes("");

        bytes memory storageProofToLastProver = input;

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, scpInputs: scpInputs, proof: storageProofToLastProver});

        ArbParentToChildProver arbParentToChildProverCopy = _getOnChainArbProverCopy();

        vm.expectRevert(Receiver.DifferentCodeHash.selector);
        receiver.updateStateProverCopy(remoteReadArgs, arbParentToChildProverCopy);
    }

    function test_verifyBroadcastMessage_from_Arbitrum_into_OP() public {
        vm.selectFork(optimismForkId);

        receiver = new Receiver();

        OPChildToParentProver childToParentProver = new OPChildToParentProver(block.chainid);

        StateProverPointer blockHashProverPointer = new StateProverPointer(owner);

        ArbParentToChildProver arbParentToChildProverCopy = _getOnChainArbProverCopy();

        address arbParentToChildProverPointerAddress;

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(childToParentProver));
        // Update the Arbitrum Prover (ParentToChildProver) copy on OP chain
        {
            uint256 expectedSlot = uint256(keccak256("eip7888.pointer.slot")) - 1;

            string memory path = "test/payloads/ethereum/arb_pointer_proof_block_9868604.json";

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

            bytes[] memory scpInputs = new bytes[](1);
            scpInputs[0] = bytes("");

            bytes memory storageProofToLastProver = inputForOPChildToParentProver;

            IReceiver.RemoteReadArgs memory remoteReadArgs =
                IReceiver.RemoteReadArgs({route: route, scpInputs: scpInputs, proof: storageProofToLastProver});

            bytes32 bhpPointerId = receiver.updateStateProverCopy(remoteReadArgs, arbParentToChildProverCopy);

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
        // We need to construct three inputs: one for OPChildToParentProver getTargetStateCommitment,
        // one for ArbParentToChildProver verifyTargetStateCommitment, and one for ArbParentToChildProver verifyStorageSlot
        // the input to verifyStorageSlot is the proof of the broadcasted message itself.
        // the input for verifyTargetStateCommitment is the storage proof of the slot on the outbox contract.

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

        bytes[] memory scpInputs = new bytes[](2);
        scpInputs[0] = input0;
        scpInputs[1] = input1;

        bytes memory storageProofToLastProver = abi.encode(
            rlpBlockHeaderArbitrum, accountArbitrum, slotArbitrum, rlpAccountProofArbitrum, rlpStorageProofArbitrum
        );

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, scpInputs: scpInputs, proof: storageProofToLastProver});

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

    function test_updateStateProverCopy_from_Arbitrum_into_Zksync() public {
        vm.selectFork(zksyncForkId);

        receiver = new Receiver();

        BufferMock buffer = new BufferMock();

        ZksyncChildToParentProver childToParentProver = new ZksyncChildToParentProver(address(buffer), block.chainid);

        StateProverPointer blockHashProverPointer = new StateProverPointer(owner);

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(childToParentProver));

        uint256 expectedSlot = uint256(keccak256("eip7888.pointer.slot")) - 1;

        string memory path = "test/payloads/ethereum/arb_pointer_proof_block_9868604.json";

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

        bytes[] memory scpInputs = new bytes[](1);
        scpInputs[0] = abi.encode(blockNumber);

        bytes memory storageProofToLastProver = input;

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, scpInputs: scpInputs, proof: storageProofToLastProver});

        ArbParentToChildProver arbParentToChildProverCopy = _getOnChainArbProverCopy();

        bytes32 bhpPointerId = receiver.updateStateProverCopy(remoteReadArgs, arbParentToChildProverCopy);

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

        StateProverPointer blockHashProverPointer = new StateProverPointer(owner);

        ArbParentToChildProver arbParentToChildProverCopy = _getOnChainArbProverCopy();

        address arbParentToChildProverPointerAddress;

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(childToParentProver));
        // Update the Arbitrum Prover (ParentToChildProver) copy on ZKSync chain
        {
            uint256 expectedSlot = uint256(keccak256("eip7888.pointer.slot")) - 1;

            string memory path = "test/payloads/ethereum/arb_pointer_proof_block_9868604.json";

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

            bytes[] memory scpInputs = new bytes[](1);
            scpInputs[0] = abi.encode(blockNumber);

            bytes memory storageProofToLastProver = inputForOPChildToParentProver;

            IReceiver.RemoteReadArgs memory remoteReadArgs =
                IReceiver.RemoteReadArgs({route: route, scpInputs: scpInputs, proof: storageProofToLastProver});

            bytes32 bhpPointerId = receiver.updateStateProverCopy(remoteReadArgs, arbParentToChildProverCopy);

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
        // We need to construct three inputs: one for ZksyncChildToParentProver getTargetStateCommitment,
        // one for ArbParentToChildProver verifyTargetStateCommitment, and one for ArbParentToChildProver verifyStorageSlot
        // the input to verifyStorageSlot is the proof of the broadcasted message itself.
        // the input for verifyTargetStateCommitment is the storage proof of the slot on the outbox contract.

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

        bytes[] memory scpInputs = new bytes[](2);
        scpInputs[0] = input0;
        scpInputs[1] = input1;

        bytes memory storageProofToLastProver = abi.encode(
            rlpBlockHeaderArbitrum, accountArbitrum, slotArbitrum, rlpAccountProofArbitrum, rlpStorageProofArbitrum
        );

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, scpInputs: scpInputs, proof: storageProofToLastProver});

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

    function test_updateStateProverCopy_from_Arbitrum_into_Linea() public {
        vm.selectFork(lineaForkId);

        receiver = new Receiver();

        BufferMock buffer = new BufferMock();

        LineaChildToParentProver childToParentProver = new LineaChildToParentProver(address(buffer), block.chainid);

        StateProverPointer blockHashProverPointer = new StateProverPointer(owner);

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(childToParentProver));

        uint256 expectedSlot = uint256(keccak256("eip7888.pointer.slot")) - 1;

        string memory path = "test/payloads/ethereum/arb_pointer_proof_block_9868604.json";

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

        bytes[] memory scpInputs = new bytes[](1);
        scpInputs[0] = abi.encode(blockNumber);

        bytes memory storageProofToLastProver = input;

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, scpInputs: scpInputs, proof: storageProofToLastProver});

        ArbParentToChildProver arbParentToChildProverCopy = _getOnChainArbProverCopy();

        bytes32 bhpPointerId = receiver.updateStateProverCopy(remoteReadArgs, arbParentToChildProverCopy);

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

    function test_verifyBroadcastMessage_from_Arbitrum_into_Linea() public {
        vm.selectFork(lineaForkId);

        receiver = new Receiver();

        BufferMock buffer = new BufferMock();

        LineaChildToParentProver childToParentProver = new LineaChildToParentProver(address(buffer), block.chainid);

        StateProverPointer blockHashProverPointer = new StateProverPointer(owner);

        ArbParentToChildProver arbParentToChildProverCopy = _getOnChainArbProverCopy();

        address arbParentToChildProverPointerAddress;

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(childToParentProver));
        // Update the Arbitrum Prover (ParentToChildProver) copy on Linea chain
        {
            uint256 expectedSlot = uint256(keccak256("eip7888.pointer.slot")) - 1;

            string memory path = "test/payloads/ethereum/arb_pointer_proof_block_9868604.json";

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

            bytes[] memory scpInputs = new bytes[](1);
            scpInputs[0] = abi.encode(blockNumber);

            bytes memory storageProofToLastProver = inputForOPChildToParentProver;

            IReceiver.RemoteReadArgs memory remoteReadArgs =
                IReceiver.RemoteReadArgs({route: route, scpInputs: scpInputs, proof: storageProofToLastProver});

            bytes32 bhpPointerId = receiver.updateStateProverCopy(remoteReadArgs, arbParentToChildProverCopy);

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

        // Construct the route to verify a message broadcasted on Arbitrum chain in Linea
        // We need to construct three inputs: one for LineaChildToParentProver getTargetStateCommitment,
        // one for ArbParentToChildProver verifyTargetStateCommitment, and one for ArbParentToChildProver verifyStorageSlot
        // the input to verifyStorageSlot is the proof of the broadcasted message itself.
        // the input for verifyTargetStateCommitment is the storage proof of the slot on the outbox contract.

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

        bytes[] memory scpInputs = new bytes[](2);
        scpInputs[0] = input0;
        scpInputs[1] = input1;

        bytes memory storageProofToLastProver = abi.encode(
            rlpBlockHeaderArbitrum, accountArbitrum, slotArbitrum, rlpAccountProofArbitrum, rlpStorageProofArbitrum
        );

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, scpInputs: scpInputs, proof: storageProofToLastProver});

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

    function test_updateStateProverCopy_from_Arbitrum_into_Scroll() public {
        vm.selectFork(scrollForkId);

        receiver = new Receiver();

        BufferMock buffer = new BufferMock();

        ScrollChildToParentProver childToParentProver = new ScrollChildToParentProver(address(buffer), block.chainid);

        StateProverPointer blockHashProverPointer = new StateProverPointer(owner);

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(childToParentProver));

        uint256 expectedSlot = uint256(keccak256("eip7888.pointer.slot")) - 1;

        string memory path = "test/payloads/ethereum/arb_pointer_proof_block_9868604.json";

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

        bytes[] memory scpInputs = new bytes[](1);
        scpInputs[0] = abi.encode(blockNumber);

        bytes memory storageProofToLastProver = input;

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, scpInputs: scpInputs, proof: storageProofToLastProver});

        ArbParentToChildProver arbParentToChildProverCopy = _getOnChainArbProverCopy();

        bytes32 bhpPointerId = receiver.updateStateProverCopy(remoteReadArgs, arbParentToChildProverCopy);

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

    function test_verifyBroadcastMessage_from_Arbitrum_into_Scroll() public {
        vm.selectFork(scrollForkId);

        receiver = new Receiver();

        BufferMock buffer = new BufferMock();

        ScrollChildToParentProver childToParentProver = new ScrollChildToParentProver(address(buffer), block.chainid);

        StateProverPointer blockHashProverPointer = new StateProverPointer(owner);

        ArbParentToChildProver arbParentToChildProverCopy = _getOnChainArbProverCopy();

        address arbParentToChildProverPointerAddress;

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(childToParentProver));
        // Update the Arbitrum Prover (ParentToChildProver) copy on Scroll chain
        {
            uint256 expectedSlot = uint256(keccak256("eip7888.pointer.slot")) - 1;

            string memory path = "test/payloads/ethereum/arb_pointer_proof_block_9868604.json";

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

            bytes[] memory scpInputs = new bytes[](1);
            scpInputs[0] = abi.encode(blockNumber);

            bytes memory storageProofToLastProver = inputForOPChildToParentProver;

            IReceiver.RemoteReadArgs memory remoteReadArgs =
                IReceiver.RemoteReadArgs({route: route, scpInputs: scpInputs, proof: storageProofToLastProver});

            bytes32 bhpPointerId = receiver.updateStateProverCopy(remoteReadArgs, arbParentToChildProverCopy);

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

        // Construct the route to verify a message broadcasted on Arbitrum chain in Scroll
        // We need to construct three inputs: one for ScrollChildToParentProver getTargetStateCommitment,
        // one for ArbParentToChildProver verifyTargetStateCommitment, and one for ArbParentToChildProver verifyStorageSlot
        // the input to verifyStorageSlot is the proof of the broadcasted message itself.
        // the input for verifyTargetStateCommitment is the storage proof of the slot on the outbox contract.

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

        bytes[] memory scpInputs = new bytes[](2);
        scpInputs[0] = input0;
        scpInputs[1] = input1;

        bytes memory storageProofToLastProver = abi.encode(
            rlpBlockHeaderArbitrum, accountArbitrum, slotArbitrum, rlpAccountProofArbitrum, rlpStorageProofArbitrum
        );

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, scpInputs: scpInputs, proof: storageProofToLastProver});

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

    function test_verifyBroadcastMessage_from_Scroll_into_Ethereum() public {
        vm.selectFork(ethereumForkId);

        receiver = new Receiver();

        // ScrollChain contract on Ethereum Sepolia
        address scrollChain = 0x2D567EcE699Eabe5afCd141eDB7A4f2D0D6ce8a0;
        // Storage slot for finalizedStateRoots mapping
        uint256 finalizedStateRootsSlot = 158;
        // L1 chain ID (Ethereum Sepolia)
        uint256 homeChainId = 11155111;

        ScrollParentToChildProver parentToChildProver =
            new ScrollParentToChildProver(scrollChain, finalizedStateRootsSlot, homeChainId);

        StateProverPointer blockHashProverPointer = new StateProverPointer(owner);

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(parentToChildProver));

        // Load the E2E proof data
        string memory path = "test/payloads/scroll/e2e-proof.json";
        string memory json = vm.readFile(path);

        bytes32 message = json.readBytes32(".message");
        address publisher = json.readAddress(".publisher");
        address account = json.readAddress(".broadcaster");
        bytes32 stateRoot = json.readBytes32(".stateRoot");
        uint256 storageSlot = json.readUint(".storageSlot");
        bytes memory rlpAccountProof = json.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = json.readBytes(".rlpStorageProof");

        uint256 expectedSlot = uint256(keccak256(abi.encode(message, publisher)));
        assertEq(expectedSlot, storageSlot, "slot mismatch");

        // For Scroll ParentToChildProver, we mock the state root directly
        // since we're testing the verifyStorageSlot functionality
        // The state root comes from the L2 block, not from ScrollChain's finalizedStateRoots

        // Create the input for verifyStorageSlot
        // Scroll's verifyStorageSlot takes: (address account, uint256 slot, bytes accountProof, bytes storageProof)
        bytes memory storageProofInput = abi.encode(account, storageSlot, rlpAccountProof, rlpStorageProof);

        // For this test, we'll directly test the prover's verifyStorageSlot function
        // since we have the state root from the L2 block
        (address returnedAccount, uint256 returnedSlot, bytes32 value) =
            parentToChildProver.verifyStorageSlot(stateRoot, storageProofInput);

        assertEq(returnedAccount, account, "wrong account");
        assertEq(returnedSlot, storageSlot, "wrong slot");

        // The value should be the timestamp (0x6939e42e = 1765401646)
        uint256 expectedTimestamp = 0x6939e42e;
        assertEq(uint256(value), expectedTimestamp, "wrong timestamp value");
    }

    function test_verifyBroadcastMessage_from_Scroll_into_Ethereum_full_flow() public {
        vm.selectFork(ethereumForkId);

        receiver = new Receiver();

        // ScrollChain contract on Ethereum Sepolia
        address scrollChain = 0x2D567EcE699Eabe5afCd141eDB7A4f2D0D6ce8a0;
        // Storage slot for finalizedStateRoots mapping
        uint256 finalizedStateRootsSlot = 158;
        // L1 chain ID (Ethereum Sepolia)
        uint256 homeChainId = 11155111;

        ScrollParentToChildProver parentToChildProver =
            new ScrollParentToChildProver(scrollChain, finalizedStateRootsSlot, homeChainId);

        StateProverPointer blockHashProverPointer = new StateProverPointer(owner);

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(parentToChildProver));

        // Load the E2E proof data
        string memory path = "test/payloads/scroll/e2e-proof.json";
        string memory json = vm.readFile(path);

        bytes32 message = json.readBytes32(".message");
        address publisher = json.readAddress(".publisher");
        address account = json.readAddress(".broadcaster");
        bytes32 stateRoot = json.readBytes32(".stateRoot");
        uint256 storageSlot = json.readUint(".storageSlot");
        uint256 batchIndex = json.readUint(".batchIndex");
        bytes memory rlpAccountProof = json.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = json.readBytes(".rlpStorageProof");

        uint256 expectedSlot = uint256(keccak256(abi.encode(message, publisher)));
        assertEq(expectedSlot, storageSlot, "slot mismatch");

        // Mock the ScrollChain contract to return the expected state root for the batch index
        // This simulates the finalized state root being stored in ScrollChain
        vm.mockCall(
            scrollChain, abi.encodeWithSignature("finalizedStateRoots(uint256)", batchIndex), abi.encode(stateRoot)
        );

        // Create the input for verifyStorageSlot
        // Scroll's verifyStorageSlot takes: (address account, uint256 slot, bytes accountProof, bytes storageProof)
        bytes memory storageProofInput = abi.encode(account, storageSlot, rlpAccountProof, rlpStorageProof);

        address[] memory route = new address[](1);
        route[0] = address(blockHashProverPointer);

        bytes[] memory scpInputs = new bytes[](1);
        scpInputs[0] = abi.encode(batchIndex);

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, scpInputs: scpInputs, proof: storageProofInput});

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

        // The value should be the timestamp (0x6939e42e = 1765401646)
        uint256 expectedTimestamp = 0x6939e42e;
        assertEq(timestamp, expectedTimestamp, "wrong timestamp");
    }

    /// @notice Test verifying a message broadcasted on Linea L2 from Ethereum L1
    /// @dev Uses Linea's Sparse Merkle Tree (SMT) proofs with MiMC hashing
    function test_verifyBroadcastMessage_from_Linea_into_Ethereum() public {
        vm.selectFork(ethereumForkId);

        receiver = new Receiver();

        // Linea Rollup on Sepolia
        address lineaRollup = 0xB218f8A4Bc926cF1cA7b3423c154a0D627Bdb7E5;
        uint256 stateRootHashesSlot = 282;
        uint256 homeChainId = 11155111; // Sepolia

        LineaParentToChildProver parentToChildProver =
            new LineaParentToChildProver(lineaRollup, stateRootHashesSlot, homeChainId);

        StateProverPointer blockHashProverPointer = new StateProverPointer(owner);

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(parentToChildProver));

        // Read the SMT proof data
        string memory path = "test/payloads/linea/lineaProofL2-smt.json";
        string memory json = vm.readFile(path);

        uint256 l2BlockNumber = json.readUint(".l2BlockNumber");
        bytes32 zkStateRoot = json.readBytes32(".zkStateRoot");
        address account = json.readAddress(".account");
        bytes32 slot = json.readBytes32(".slot");
        bytes32 value = bytes32(json.readUint(".slotValue"));

        // Mock LineaRollup to return the zkStateRoot for this block
        vm.mockCall(
            lineaRollup, abi.encodeWithSignature("stateRootHashes(uint256)", l2BlockNumber), abi.encode(zkStateRoot)
        );

        // Read encoded SMT proof from file
        string memory encodedProofHex = vm.readFile("test/payloads/linea/encoded-smt-proof.txt");
        bytes memory smtProof = vm.parseBytes(encodedProofHex);

        // Construct the route
        address[] memory route = new address[](1);
        route[0] = address(blockHashProverPointer);

        bytes[] memory scpInputs = new bytes[](1);
        scpInputs[0] = abi.encode(l2BlockNumber);

        bytes memory storageProofToLastProver = smtProof;

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, scpInputs: scpInputs, proof: storageProofToLastProver});

        // Calculate expected message hash from the slot
        // The slot is keccak256(abi.encode(message, publisher))
        // We need to find the message that produces this slot
        // For this test, we use the known message from the broadcast
        bytes32 message = 0x7ef698ac3d608dabceaf43d5d1df44247f7f339c28cde2f19ac25a79e2392673;
        address publisher = 0x0d08bae6bAF232EFA1208A6CaC66a389D5c27981;

        // Verify the slot matches
        uint256 expectedSlot = uint256(keccak256(abi.encode(message, publisher)));
        assertEq(expectedSlot, uint256(slot), "slot mismatch");

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
}
