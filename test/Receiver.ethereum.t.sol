// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

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
import {ChildToParentProver as LineaChildToParentProver} from "../src/contracts/provers/linea/ChildToParentProver.sol";
import {ParentToChildProver as LineaParentToChildProver} from "../src/contracts/provers/linea/ParentToChildProver.sol";
import {
    ParentToChildProver as ZksyncParentToChildProver,
    ZkSyncProof,
    L2Message
} from "../src/contracts/provers/zksync/ParentToChildProver.sol";
import {
    ChildToParentProver as ZksyncChildToParentProver
} from "../src/contracts/provers/zksync/ChildToParentProver.sol";
import {
    ChildToParentProver as ScrollChildToParentProver
} from "../src/contracts/provers/scroll/ChildToParentProver.sol";
import {
    ParentToChildProver as ScrollParentToChildProver
} from "../src/contracts/provers/scroll/ParentToChildProver.sol";
import {BlockHashProverPointer} from "../src/contracts/BlockHashProverPointer.sol";
import {RLP} from "@openzeppelin/contracts/utils/RLP.sol";

import {MockZkChain} from "./provers/zksync/ParentChildToProver.t.sol";

contract ReceiverTest is Test {
    using stdJson for string;

    Receiver public receiver;

    uint256 public ethereumForkId;
    uint256 public arbitrumForkId;
    uint256 public optimismForkId;
    uint256 public lineaForkId;
    uint256 public zksyncForkId;
    uint256 public scrollForkId;

    IOutbox public outbox;

    address owner = makeAddr("owner");

    function setUp() public {
        ethereumForkId = vm.createFork(vm.envString("ETHEREUM_RPC_URL"));
        arbitrumForkId = vm.createFork(vm.envString("ARBITRUM_RPC_URL"));
        optimismForkId = vm.createFork(vm.envString("OPTIMISM_RPC_URL"));
        lineaForkId = vm.createFork(vm.envString("LINEA_RPC_URL"));
        zksyncForkId = vm.createFork(vm.envString("ZKSYNC_RPC_URL"));
        scrollForkId = vm.createFork(vm.envString("SCROLL_RPC_URL"));

        vm.selectFork(arbitrumForkId);
        outbox = IOutbox(0x65f07C7D521164a4d5DaC6eB8Fac8DA067A3B78F);
    }

    function getZkSyncProof() public pure returns (ZkSyncProof memory) {
        // transaction hash: 0x6ae69e72d45d219609f24e4e7c7711245ac61b7b0fdd872aae39c0d167ee4ed7

        bytes32[] memory logProof = new bytes32[](36);
        logProof[0] = 0x010f0c0000000000000000000000000000000000000000000000000000000000;
        logProof[1] = 0xd3eef36d4c28d71c8783d3da0246085b59cc8b18dc6f461ec9a5c96619470cb4;
        logProof[2] = 0xe985c25f5b4aa7ea1cf6549f4f04efb26565a596f63c12690bf154a78bc92352;
        logProof[3] = 0xc525bbdf0eea2b39ca66a33fddd45db0cbda11005a223aba0cfaefc2087d5693;
        logProof[4] = 0xa7b9990d6d3f3338089d524b50e61d01394430a481d666f500d008ed2f8a00fd;
        logProof[5] = 0x029159cbc7628e45c5fcf3ef93c8f43b7c90dca84ec3a249c0d913bbd24e7c84;
        logProof[6] = 0x1798a1fd9c8fbb818c98cff190daa7cc10b6e5ac9716b4a2649f7c2ebcef2272;
        logProof[7] = 0x66d7c5983afe44cf15ea8cf565b34c6c31ff0cb4dd744524f7842b942d08770d;
        logProof[8] = 0xb04e5ee349086985f74b73971ce9dfe76bbed95c84906c5dffd96504e1e5396c;
        logProof[9] = 0xac506ecb5465659b3a927143f6d724f91d8d9c4bdb2463aee111d9aa869874db;
        logProof[10] = 0x124b05ec272cecd7538fdafe53b6628d31188ffb6f345139aac3c3c1fd2e470f;
        logProof[11] = 0xc3be9cbd19304d84cca3d045e06b8db3acd68c304fc9cd4cbffe6d18036cb13f;
        logProof[12] = 0xfef7bd9f889811e59e4076a0174087135f080177302763019adaf531257e3a87;
        logProof[13] = 0xa707d1c62d8be699d34cb74804fdd7b4c568b6c1a821066f126c680d4b83e00b;
        logProof[14] = 0xf6e093070e0389d2e529d60fadb855fdded54976ec50ac709e3a36ceaa64c291;
        logProof[15] = 0xf7dee40f4d8b94f983076f3435067adec0f689c15b952eee60ccc7c5675f9b93;
        logProof[16] = 0x000000000000000000000000000000000000000000000000000000000000082c;
        logProof[17] = 0x46700b4d40ac5c35af2c22dda2787a91eb567b06c924a8fb8ae9a05b20c08c21;
        logProof[18] = 0xcc4c41edb0c2031348b292b768e9bac1ee8c92c09ef8a3277c2ece409c12d86a;
        logProof[19] = 0x06b8a6a9ca6ae750b7dfbf358b73dad2c3ef1eb24e6148f90d7684a19656be12;
        logProof[20] = 0xf2b243df8439a2e9b1505b5bbc95bd9d49e474bb866e6d33df4ba93c7f8469bf;
        logProof[21] = 0x3c60f99ddd7a9f5367800cdab608028381c110604670200e21c159d163fc46cc;
        logProof[22] = 0x0b2cfe0910f7baebb89fd511510915797640d00cf742260684f6dbff4fbae786;
        logProof[23] = 0x1dfbe77401207dce60055614f80a946ccc2c4e679c08c608370362c6279ae2f1;
        logProof[24] = 0xf3096113152fab0a26666e9cd9519b711bd0a7c01c2d4c2eebed9a03d0b4c1f1;
        logProof[25] = 0x1b10d93c70611fb12dc351df7ce060c9bfcd2eb9d75d6cdb1af3bf3092f3f31d;
        logProof[26] = 0x8df5379fefae4adff70d71fd9e0f53a86f81b3e3a07c326468505b7a09d7521f;
        logProof[27] = 0xda185173bf3eb691ad5a68eaab1484df2d96b8c5d29f75d5f65ac6b28ee39f5a;
        logProof[28] = 0xa8a8e91b6bea9d7b61eaa7fd548b03445766c75c2aee6608d7c1b162ed032a0d;
        logProof[29] = 0x0000000000000000000000000000abd000000000000000000000000000000009;
        logProof[30] = 0x0000000000000000000000000000000000000000000000000000000000007f91;
        logProof[31] = 0x0104000100000000000000000000000000000000000000000000000000000000;
        logProof[32] = 0x356b32c2191984a81ffe9ed1daf0faebbc83cd5471ed49760de4077c0e055e97;
        logProof[33] = 0x785bf8f7e4bc75f517029427d12ae762ad0138db2ff4e42f83c48af7a2679ea8;
        logProof[34] = 0x2907adf087da79137e9c8c39eaee670d2dd9c9c33d1ca008b2005e20f3ef1e34;
        logProof[35] = 0xe967b8563e5fbe7583f84e0cb30139ddca2c4a10a4899115f7abb601a4061c6b;

        ZkSyncProof memory proof = ZkSyncProof({
            batchNumber: 18645,
            index: 27,
            message: L2Message({
                txNumberInBatch: 576,
                sender: 0xAb23DF3fd78F45E54466d08926c3A886211aC5A1,
                data: hex"0000000000000000000000000000000000000000000000000000000068fa57d80000000000000000000000000000000000000000000000000000000069332a4a"
            }),
            proof: logProof
        });
        return proof;
    }

    function test_verifyBroadcastMessage_from_ZkSync_into_Ethereum() public {
        vm.selectFork(ethereumForkId);

        MockZkChain mockZkChain = new MockZkChain();
        mockZkChain.setL2LogsRootHash(43984, 0x4cbeceb2a95a01369ab104ec6a305e37cb22d3717abb91da6880e038c3160470);

        receiver = new Receiver();
        ZksyncParentToChildProver parentToChildProver =
            new ZksyncParentToChildProver(address(mockZkChain), 0, 300, 32657, block.chainid);

        BlockHashProverPointer blockHashProverPointer = new BlockHashProverPointer(owner);

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(parentToChildProver));

        bytes32 message = 0x0000000000000000000000000000000000000000000000000000000068fa57d8; // "test"
        address publisher = 0xAb23DF3fd78F45E54466d08926c3A886211aC5A1;

        uint256 expectedSlot = uint256(keccak256(abi.encode(message, publisher)));

        ZkSyncProof memory proof = getZkSyncProof();

        bytes memory input = abi.encode(proof);

        address[] memory route = new address[](1);
        route[0] = address(blockHashProverPointer);

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(43984);

        bytes memory storageProofToLastProver = input;

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, bhpInputs: bhpInputs, storageProof: storageProofToLastProver});

        (bytes32 broadcasterId, uint256 timestamp) = receiver.verifyBroadcastMessage(remoteReadArgs, message, publisher);

        (bytes32 messageSent, bytes32 expectedValue) = abi.decode(proof.message.data, (bytes32, bytes32));

        address expectedAccount = proof.message.sender;

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
                    expectedAccount
                )
            ),
            "wrong broadcasterId"
        );
        assertEq(timestamp, uint256(expectedValue), "wrong timestamp");
    }

    function test_verifyBroadcastMessage_from_ZkSync_into_Ethereum_wrong_message() public {
        vm.selectFork(ethereumForkId);

        MockZkChain mockZkChain = new MockZkChain();
        mockZkChain.setL2LogsRootHash(43984, 0x4cbeceb2a95a01369ab104ec6a305e37cb22d3717abb91da6880e038c3160470);

        receiver = new Receiver();
        ZksyncParentToChildProver parentToChildProver =
            new ZksyncParentToChildProver(address(mockZkChain), 0, 300, 32657, block.chainid);

        BlockHashProverPointer blockHashProverPointer = new BlockHashProverPointer(owner);

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(parentToChildProver));

        bytes32 message = 0x0000000000000000000000000000000000000000000000000000000000000000;
        address publisher = 0xAb23DF3fd78F45E54466d08926c3A886211aC5A1;

        uint256 expectedSlot = uint256(keccak256(abi.encode(message, publisher)));

        ZkSyncProof memory proof = getZkSyncProof();

        bytes memory input = abi.encode(proof);

        address[] memory route = new address[](1);
        route[0] = address(blockHashProverPointer);

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(43984);

        bytes memory storageProofToLastProver = input;

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, bhpInputs: bhpInputs, storageProof: storageProofToLastProver});

        vm.expectRevert(Receiver.WrongMessageSlot.selector);
        receiver.verifyBroadcastMessage(remoteReadArgs, message, publisher);
    }
}

