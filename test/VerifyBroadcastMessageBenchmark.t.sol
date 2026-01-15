// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Receiver} from "../src/contracts/Receiver.sol";
import {IReceiver} from "../src/contracts/interfaces/IReceiver.sol";
import {BlockHashProverPointer} from "../src/contracts/BlockHashProverPointer.sol";

// Provers
import {ParentToChildProver as TaikoP2C} from "../src/contracts/provers/taiko/ParentToChildProver.sol";
import {ChildToParentProver as TaikoC2P} from "../src/contracts/provers/taiko/ChildToParentProver.sol";
import {ParentToChildProver as ScrollP2C} from "../src/contracts/provers/scroll/ParentToChildProver.sol";
import {ParentToChildProver as LineaP2C} from "../src/contracts/provers/linea/ParentToChildProver.sol";
import {ChildToParentProver as OptimismC2P} from "../src/contracts/provers/optimism/ChildToParentProver.sol";
import {
    ParentToChildProver as ZksyncP2C,
    ZkSyncProof,
    L2Message
} from "../src/contracts/provers/zksync/ParentToChildProver.sol";

import {MockZkChain} from "./provers/zksync/ParentChildToProver.t.sol";

/**
 * @title verifyBroadcastMessage Gas Benchmarks
 * @notice Measures the gas cost of verifyBroadcastMessage for different L2 routes
 * @dev Uses vm.snapshotGasLastCall to automatically generate snapshots/verifyBroadcastMessage.json
 *
 * Run with: forge test --match-contract VerifyBroadcastMessageBenchmark -vv
 * Generate snapshots: forge test --match-contract VerifyBroadcastMessageBenchmark --isolate
 */
contract VerifyBroadcastMessageBenchmark is Test {
    using stdJson for string;

    Receiver public receiver;
    address owner = makeAddr("owner");

    // ========================================================================
    // L2 → L1 BENCHMARKS (ParentToChild Provers)
    // ========================================================================

    /// @notice Benchmark: Taiko L2 → Ethereum L1 (MPT Proof)
    /// forge-config: default.isolate = true
    function test_benchmark_Taiko_L2_to_L1() public {
        uint256 L1_CHAIN_ID = 32382;
        uint256 SIGNAL_SERVICE = uint256(uint160(0x53789e39E3310737E8C8cED483032AAc25B39ded));
        uint256 CHECKPOINTS_SLOT = 254;

        vm.chainId(L1_CHAIN_ID);

        receiver = new Receiver();
        TaikoP2C prover = new TaikoP2C(address(uint160(SIGNAL_SERVICE)), CHECKPOINTS_SLOT, L1_CHAIN_ID);
        BlockHashProverPointer pointer = new BlockHashProverPointer(owner);

        vm.prank(owner);
        pointer.setImplementationAddress(address(prover));

        // Load proof data
        string memory proofJson = vm.readFile("test/payloads/taiko/taikoProofL2.json");
        string memory infoJson = vm.readFile("test/payloads/taiko/taikoProofL2-info.json");

        uint256 blockNumber = proofJson.readUint(".blockNumber");
        bytes32 blockHash = proofJson.readBytes32(".blockHash");
        bytes32 stateRoot = proofJson.readBytes32(".stateRoot");
        address account = proofJson.readAddress(".account");
        uint256 slot = proofJson.readUint(".slot");
        bytes memory rlpBlockHeader = proofJson.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProof = proofJson.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = proofJson.readBytes(".rlpStorageProof");

        bytes32 message = infoJson.readBytes32(".message");
        address publisher = infoJson.readAddress(".publisher");

        // Mock SignalService checkpoint
        vm.mockCall(
            address(uint160(SIGNAL_SERVICE)),
            abi.encodeWithSignature("getCheckpoint(uint48)", uint48(blockNumber)),
            abi.encode(uint48(blockNumber), blockHash, stateRoot)
        );

        bytes memory storageProof = abi.encode(rlpBlockHeader, account, slot, rlpAccountProof, rlpStorageProof);

        address[] memory route = new address[](1);
        route[0] = address(pointer);

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(uint48(blockNumber));

        IReceiver.RemoteReadArgs memory args =
            IReceiver.RemoteReadArgs({route: route, bhpInputs: bhpInputs, storageProof: storageProof});

        // Call and snapshot
        receiver.verifyBroadcastMessage(args, message, publisher);
        vm.snapshotGasLastCall("verifyBroadcastMessage", "TaikoL2ToEthereum");
    }

    /// @notice Benchmark: Scroll L2 → Ethereum L1 (MPT Proof)
    /// forge-config: default.isolate = true
    function test_benchmark_Scroll_L2_to_L1() public {
        uint256 HOME_CHAIN_ID = 11155111;
        address SCROLL_CHAIN = 0x2D567EcE699Eabe5afCd141eDB7A4f2D0D6ce8a0;
        uint256 STATE_ROOTS_SLOT = 158;

        vm.chainId(HOME_CHAIN_ID);

        receiver = new Receiver();
        ScrollP2C prover = new ScrollP2C(SCROLL_CHAIN, STATE_ROOTS_SLOT, HOME_CHAIN_ID);
        BlockHashProverPointer pointer = new BlockHashProverPointer(owner);

        vm.prank(owner);
        pointer.setImplementationAddress(address(prover));

        // Load proof data
        string memory json = vm.readFile("test/payloads/scroll/e2e-proof.json");

        bytes32 message = json.readBytes32(".message");
        address publisher = json.readAddress(".publisher");
        address account = json.readAddress(".broadcaster");
        bytes32 stateRoot = json.readBytes32(".stateRoot");
        uint256 storageSlot = json.readUint(".storageSlot");
        uint256 batchIndex = json.readUint(".batchIndex");
        bytes memory rlpAccountProof = json.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = json.readBytes(".rlpStorageProof");

        // Mock ScrollChain state root
        vm.mockCall(
            SCROLL_CHAIN, abi.encodeWithSignature("finalizedStateRoots(uint256)", batchIndex), abi.encode(stateRoot)
        );

        bytes memory storageProof = abi.encode(account, storageSlot, rlpAccountProof, rlpStorageProof);

        address[] memory route = new address[](1);
        route[0] = address(pointer);

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(batchIndex);

        IReceiver.RemoteReadArgs memory args =
            IReceiver.RemoteReadArgs({route: route, bhpInputs: bhpInputs, storageProof: storageProof});

        // Call and snapshot
        receiver.verifyBroadcastMessage(args, message, publisher);
        vm.snapshotGasLastCall("verifyBroadcastMessage", "ScrollL2ToEthereum");
    }

    /// @notice Benchmark: Linea L2 → Ethereum L1 (SMT/MiMC Proof)
    /// forge-config: default.isolate = true
    function test_benchmark_Linea_L2_to_L1() public {
        uint256 HOME_CHAIN_ID = 11155111;
        address LINEA_ROLLUP = 0xB218f8A4Bc926cF1cA7b3423c154a0D627Bdb7E5;
        uint256 STATE_ROOT_SLOT = 282;

        vm.chainId(HOME_CHAIN_ID);

        receiver = new Receiver();
        LineaP2C prover = new LineaP2C(LINEA_ROLLUP, STATE_ROOT_SLOT, HOME_CHAIN_ID);
        BlockHashProverPointer pointer = new BlockHashProverPointer(owner);

        vm.prank(owner);
        pointer.setImplementationAddress(address(prover));

        // Load proof data
        string memory json = vm.readFile("test/payloads/linea/lineaProofL2-smt.json");

        uint256 l2BlockNumber = json.readUint(".l2BlockNumber");
        bytes32 zkStateRoot = json.readBytes32(".zkStateRoot");

        // Mock LineaRollup state root
        vm.mockCall(
            LINEA_ROLLUP, abi.encodeWithSignature("stateRootHashes(uint256)", l2BlockNumber), abi.encode(zkStateRoot)
        );

        // Load encoded SMT proof
        string memory encodedProofHex = vm.readFile("test/payloads/linea/encoded-smt-proof.txt");
        bytes memory smtProof = vm.parseBytes(encodedProofHex);

        bytes32 message = 0x7ef698ac3d608dabceaf43d5d1df44247f7f339c28cde2f19ac25a79e2392673;
        address publisher = 0x0d08bae6bAF232EFA1208A6CaC66a389D5c27981;

        address[] memory route = new address[](1);
        route[0] = address(pointer);

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(l2BlockNumber);

        IReceiver.RemoteReadArgs memory args =
            IReceiver.RemoteReadArgs({route: route, bhpInputs: bhpInputs, storageProof: smtProof});

        // Call and snapshot
        receiver.verifyBroadcastMessage(args, message, publisher);
        vm.snapshotGasLastCall("verifyBroadcastMessage", "LineaL2ToEthereum");
    }

    /// @notice Benchmark: ZkSync L2 → Ethereum L1 (ZkChain Proof)
    /// forge-config: default.isolate = true
    function test_benchmark_ZkSync_L2_to_L1() public {
        uint256 HOME_CHAIN_ID = 11155111;
        uint256 STATE_ROOT_SLOT = 14;

        bytes32[] memory logProof = new bytes32[](36);
        logProof[0] = 0x010f0c0000000000000000000000000000000000000000000000000000000000;
        logProof[1] = 0xba721d8eb9acfdb6c9d126c73e753e704ed1ad03f5ae1e780a42b804a358289b;
        logProof[2] = 0x74fc01d158bebe1c78b66fb1c1f3243757aa7d7fd7c4dbf369c82a0b1985a81b;
        logProof[3] = 0x046ae899999754d50cb8837f25819fb1c89a1b6c5369e31919adf67bd9d16387;
        logProof[4] = 0xa786531a2f80df5b45f2278522956d4eec91639ce8e7c801e8a4777532dbafae;
        logProof[5] = 0x171acb5a7ac6bd565ac058b86eeb91ee9fec31b6bc63191c7319859ad517ea73;
        logProof[6] = 0xd1524dec2cb2f9fe4c6a65df20fd00bd127cb264c63b57cdbdbff9220e1979c3;
        logProof[7] = 0x66d7c5983afe44cf15ea8cf565b34c6c31ff0cb4dd744524f7842b942d08770d;
        logProof[8] = 0xb04e5ee349086985f74b73971ce9dfe76bbed95c84906c5dffd96504e1e5396c;
        logProof[9] = 0xac506ecb5465659b3a927143f6d724f91d8d9c4bdb2463aee111d9aa869874db;
        logProof[10] = 0x124b05ec272cecd7538fdafe53b6628d31188ffb6f345139aac3c3c1fd2e470f;
        logProof[11] = 0xc3be9cbd19304d84cca3d045e06b8db3acd68c304fc9cd4cbffe6d18036cb13f;
        logProof[12] = 0xfef7bd9f889811e59e4076a0174087135f080177302763019adaf531257e3a87;
        logProof[13] = 0xa707d1c62d8be699d34cb74804fdd7b4c568b6c1a821066f126c680d4b83e00b;
        logProof[14] = 0xf6e093070e0389d2e529d60fadb855fdded54976ec50ac709e3a36ceaa64c291;
        logProof[15] = 0xf7dee40f4d8b94f983076f3435067adec0f689c15b952eee60ccc7c5675f9b93;
        logProof[16] = 0x00000000000000000000000000000000000000000000000000000000000008d5;
        logProof[17] = 0x5f211cf8b014ea89ea6d8cd9fc5393a45b6a74b87ca155ba1b1c53090d5122a5;
        logProof[18] = 0xcc4c41edb0c2031348b292b768e9bac1ee8c92c09ef8a3277c2ece409c12d86a;
        logProof[19] = 0x52835f0f403fdc787f71794f03efff1105b0018d1feaa142bbb69d5ffd5686d7;
        logProof[20] = 0x4cd95f8962e2e3b5f525a0f4fdfbbf0667990c7159528a008057f3592bcb2c06;
        logProof[21] = 0x925e89147bb260c790628bdc8cab999454777f68dfa02514d69cd1745ae0797d;
        logProof[22] = 0xb5db2d4fe1e6b767734341bf876a562e0735721094f7d5221211eb089f79ab36;
        logProof[23] = 0x0a5f6c41e4aaebbcc906e88d076babe06188c00d48d7fec6e7913c684a991eb4;
        logProof[24] = 0xf82bdab99278345624d897be8747618882c3773507551b19f7781d1b1a6105c1;
        logProof[25] = 0x1b10d93c70611fb12dc351df7ce060c9bfcd2eb9d75d6cdb1af3bf3092f3f31d;
        logProof[26] = 0x8df5379fefae4adff70d71fd9e0f53a86f81b3e3a07c326468505b7a09d7521f;
        logProof[27] = 0xda185173bf3eb691ad5a68eaab1484df2d96b8c5d29f75d5f65ac6b28ee39f5a;
        logProof[28] = 0xa8a8e91b6bea9d7b61eaa7fd548b03445766c75c2aee6608d7c1b162ed032a0d;
        logProof[29] = 0x0000000000000000000000000000b99200000000000000000000000000000009;
        logProof[30] = 0x0000000000000000000000000000000000000000000000000000000000007f91;
        logProof[31] = 0x0104000100000000000000000000000000000000000000000000000000000000;
        logProof[32] = 0x356b32c2191984a81ffe9ed1daf0faebbc83cd5471ed49760de4077c0e055e97;
        logProof[33] = 0x41dfba0e4dd6b5e91fac4ff1de2bcff9b4435885d5330ecd4c6cc26e0447d38d;
        logProof[34] = 0xe07654c6d0b385cd0c9f20c213dee9e5502137a7b6a05e350b8ced1b94a9eed9;
        logProof[35] = 0x487867999683a00a7de702d49133af0a15785c25ed48dcc72cf71ea4bd862516;

        ZkSyncProof memory proof = ZkSyncProof({
            batchNumber: 18814,
            index: 4,
            message: L2Message({
                txNumberInBatch: 91,
                sender: 0x51665298A7Ce1781aD2CB50B1E512322A6B12458,
                data: hex"4d2f31e8578316b1eee225feb6442c49f42083864fa317ea81928e275ad2e3660000000000000000000000000000000000000000000000000000000069459b52"
            }),
            proof: logProof
        });

        vm.chainId(HOME_CHAIN_ID);

        MockZkChain mockZkChain = new MockZkChain();
        mockZkChain.setL2LogsRootHash(47506, 0xc445ecf161f26c39cde0fe9a0db973d3d5193951d55c5d60f224cb0579370003);

        receiver = new Receiver();
        ZksyncP2C parentToChildProver = new ZksyncP2C(address(mockZkChain), 0, 300, 32657, block.chainid);

        BlockHashProverPointer blockHashProverPointer = new BlockHashProverPointer(owner);

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(parentToChildProver));

        bytes32 message = 0x0000000000000000000000000000000000000000000000000000000074657374; // "test"
        address publisher = 0x9a56fFd72F4B526c523C733F1F74197A51c495E1;

        uint256 expectedSlot = uint256(keccak256(abi.encode(message, publisher)));

        bytes memory input = abi.encode(proof, publisher, message);

        address[] memory route = new address[](1);
        route[0] = address(blockHashProverPointer);

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(47506);

        bytes memory storageProofToLastProver = input;

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, bhpInputs: bhpInputs, storageProof: storageProofToLastProver});

        receiver.verifyBroadcastMessage(remoteReadArgs, message, publisher);
        vm.snapshotGasLastCall("verifyBroadcastMessage", "ZkSyncL2ToEthereum");
    }

    // ========================================================================
    // L1 → L2 BENCHMARKS (ChildToParent Provers)
    // ========================================================================

    /// @notice Benchmark: Ethereum L1 → Taiko L2 (MPT Proof)
    /// forge-config: default.isolate = true
    function test_benchmark_Ethereum_L1_to_Taiko_L2() public {
        uint256 L2_CHAIN_ID = 167000;
        uint256 SIGNAL_SERVICE = uint256(uint160(0x53789e39E3310737E8C8cED483032AAc25B39ded));
        uint256 CHECKPOINTS_SLOT = 254;

        vm.chainId(L2_CHAIN_ID);

        receiver = new Receiver();
        TaikoC2P prover = new TaikoC2P(address(uint160(SIGNAL_SERVICE)), CHECKPOINTS_SLOT, L2_CHAIN_ID);
        BlockHashProverPointer pointer = new BlockHashProverPointer(owner);

        vm.prank(owner);
        pointer.setImplementationAddress(address(prover));

        // Load L1 proof data
        string memory proofJson = vm.readFile("test/payloads/taiko/taikoProofL1.json");
        string memory infoJson = vm.readFile("test/payloads/taiko/taikoProofL1-info.json");

        uint256 blockNumber = proofJson.readUint(".blockNumber");
        bytes32 blockHash = proofJson.readBytes32(".blockHash");
        bytes32 stateRoot = proofJson.readBytes32(".stateRoot");
        address account = proofJson.readAddress(".account");
        uint256 slot = proofJson.readUint(".slot");
        bytes memory rlpBlockHeader = proofJson.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProof = proofJson.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = proofJson.readBytes(".rlpStorageProof");

        bytes32 message = infoJson.readBytes32(".message");
        address publisher = infoJson.readAddress(".publisher");

        // Mock SignalService checkpoint
        vm.mockCall(
            address(uint160(SIGNAL_SERVICE)),
            abi.encodeWithSignature("getCheckpoint(uint48)", uint48(blockNumber)),
            abi.encode(uint48(blockNumber), blockHash, stateRoot)
        );

        bytes memory storageProof = abi.encode(rlpBlockHeader, account, slot, rlpAccountProof, rlpStorageProof);

        address[] memory route = new address[](1);
        route[0] = address(pointer);

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(uint48(blockNumber));

        IReceiver.RemoteReadArgs memory args =
            IReceiver.RemoteReadArgs({route: route, bhpInputs: bhpInputs, storageProof: storageProof});

        // Call and snapshot
        receiver.verifyBroadcastMessage(args, message, publisher);
        vm.snapshotGasLastCall("verifyBroadcastMessage", "EthereumToTaikoL2");
    }

    /// @notice Benchmark: Ethereum L1 → Optimism L2 (MPT Proof)
    /// forge-config: default.isolate = true
    function test_benchmark_Ethereum_L1_to_Optimism_L2() public {
        uint256 L2_CHAIN_ID = 11155420;

        vm.chainId(L2_CHAIN_ID);

        receiver = new Receiver();
        OptimismC2P prover = new OptimismC2P(L2_CHAIN_ID);
        BlockHashProverPointer pointer = new BlockHashProverPointer(owner);

        vm.prank(owner);
        pointer.setImplementationAddress(address(prover));

        // Load Ethereum proof data
        string memory json = vm.readFile("test/payloads/ethereum/broadcast_proof_block_9496454.json");

        uint256 blockNumber = json.readUint(".blockNumber");
        bytes32 blockHash = json.readBytes32(".blockHash");
        address account = json.readAddress(".account");
        uint256 slot = json.readUint(".slot");
        bytes memory rlpBlockHeader = json.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProof = json.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = json.readBytes(".rlpStorageProof");

        bytes32 message = 0x0000000000000000000000000000000000000000000000000000000074657374;
        address publisher = 0x9a56fFd72F4B526c523C733F1F74197A51c495E1;

        // Mock L1Block predeploy
        address l1Block = prover.l1BlockPredeploy();
        vm.mockCall(l1Block, abi.encodeWithSignature("hash()"), abi.encode(blockHash));
        vm.mockCall(l1Block, abi.encodeWithSignature("number()"), abi.encode(blockNumber));

        bytes memory storageProof = abi.encode(rlpBlockHeader, account, slot, rlpAccountProof, rlpStorageProof);

        address[] memory route = new address[](1);
        route[0] = address(pointer);

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = bytes("");

        IReceiver.RemoteReadArgs memory args =
            IReceiver.RemoteReadArgs({route: route, bhpInputs: bhpInputs, storageProof: storageProof});

        // Call and snapshot
        receiver.verifyBroadcastMessage(args, message, publisher);
        vm.snapshotGasLastCall("verifyBroadcastMessage", "EthereumToOptimism");
    }

    // ========================================================================
    // L2 → L2 BENCHMARKS (Multi-hop via Ethereum)
    // ========================================================================

    /// @notice Benchmark: Scroll L2 → Optimism L2 (2-hop: OP-C2P + Scroll-P2C)
    /// @dev On Optimism L2, verify message from Scroll L2 via Ethereum
    ///      Route: [OP-C2P-Pointer, Scroll-P2C-Copy]
    ///      Hop 1: OP-C2P gets Ethereum block hash from L1Block predeploy
    ///      Hop 2: Scroll-P2C verifies Scroll storage against state root
    /// forge-config: default.isolate = true
    function test_benchmark_from_Scroll_into_Optimism() public {
        // We're on Optimism L2 (destination), verifying message from Scroll L2 (source)
        uint256 OP_L2_CHAIN_ID = 11155420;

        vm.chainId(OP_L2_CHAIN_ID);

        receiver = new Receiver();

        // First hop prover: Optimism C2P (gets Ethereum block hash on OP L2)
        OptimismC2P opC2PProver = new OptimismC2P(OP_L2_CHAIN_ID);
        BlockHashProverPointer opPointer = new BlockHashProverPointer(owner);

        vm.prank(owner);
        opPointer.setImplementationAddress(address(opC2PProver));

        // Second hop prover: Scroll P2C copy (verifies Scroll state from Ethereum)
        address SCROLL_CHAIN = 0x2D567EcE699Eabe5afCd141eDB7A4f2D0D6ce8a0;
        uint256 STATE_ROOTS_SLOT = 158;
        ScrollP2C scrollP2CProverCopy = new ScrollP2C(SCROLL_CHAIN, STATE_ROOTS_SLOT, 11155111);

        // Address that represents the Scroll P2C pointer on Ethereum
        address scrollPointerAddress = makeAddr("scrollPointerOnEthereum");

        // Register the Scroll prover copy in receiver's mapping
        bytes32 acc1 = keccak256(abi.encode(bytes32(0), address(opPointer)));
        bytes32 bhpPointerId = keccak256(abi.encode(acc1, scrollPointerAddress));

        bytes32 mappingSlot = keccak256(abi.encode(bhpPointerId, uint256(0)));
        vm.store(address(receiver), mappingSlot, bytes32(uint256(uint160(address(scrollP2CProverCopy)))));

        // Load Ethereum proof for first hop
        string memory ethJson = vm.readFile("test/payloads/ethereum/broadcast_proof_block_9496454.json");
        uint256 ethBlockNumber = ethJson.readUint(".blockNumber");
        bytes32 ethBlockHash = ethJson.readBytes32(".blockHash");

        // Mock L1Block predeploy for first hop
        address l1Block = opC2PProver.l1BlockPredeploy();
        vm.mockCall(l1Block, abi.encodeWithSignature("hash()"), abi.encode(ethBlockHash));
        vm.mockCall(l1Block, abi.encodeWithSignature("number()"), abi.encode(ethBlockNumber));

        // Load Scroll proof for second hop
        string memory scrollJson = vm.readFile("test/payloads/scroll/e2e-proof.json");
        address scrollBroadcaster = scrollJson.readAddress(".broadcaster");
        bytes32 scrollStateRoot = scrollJson.readBytes32(".stateRoot");
        uint256 scrollStorageSlot = scrollJson.readUint(".storageSlot");
        uint256 scrollBatchIndex = scrollJson.readUint(".batchIndex");
        bytes memory scrollRlpAccountProof = scrollJson.readBytes(".rlpAccountProof");
        bytes memory scrollRlpStorageProof = scrollJson.readBytes(".rlpStorageProof");

        // Mock ScrollChain.finalizedStateRoots on Ethereum
        vm.mockCall(
            SCROLL_CHAIN,
            abi.encodeWithSignature("finalizedStateRoots(uint256)", scrollBatchIndex),
            abi.encode(scrollStateRoot)
        );

        // For L2→L2, we measure the combined cost by calling both verifications
        bytes memory scrollStorageProof =
            abi.encode(scrollBroadcaster, scrollStorageSlot, scrollRlpAccountProof, scrollRlpStorageProof);

        // Use startSnapshotGas/stopSnapshotGas to capture combined gas of both operations
        vm.startSnapshotGas("verifyBroadcastMessage", "ScrollToOptimism");

        // First: get Ethereum block hash via OP C2P (simulates first hop verification)
        opC2PProver.getTargetBlockHash(bytes(""));

        // Second: verify Scroll storage using Scroll P2C (simulates second hop verification)
        scrollP2CProverCopy.verifyStorageSlot(scrollStateRoot, scrollStorageProof);

        vm.stopSnapshotGas();
    }
}
