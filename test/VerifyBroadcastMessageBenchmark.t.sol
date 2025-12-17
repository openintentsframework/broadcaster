// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

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
            SCROLL_CHAIN,
            abi.encodeWithSignature("finalizedStateRoots(uint256)", batchIndex),
            abi.encode(stateRoot)
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
            LINEA_ROLLUP,
            abi.encodeWithSignature("stateRootHashes(uint256)", l2BlockNumber),
            abi.encode(zkStateRoot)
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
        bytes memory scrollStorageProof = abi.encode(scrollBroadcaster, scrollStorageSlot, scrollRlpAccountProof, scrollRlpStorageProof);

        // Use startSnapshotGas/stopSnapshotGas to capture combined gas of both operations
        vm.startSnapshotGas("verifyBroadcastMessage", "ScrollToOptimism");

        // First: get Ethereum block hash via OP C2P (simulates first hop verification)
        opC2PProver.getTargetBlockHash(bytes(""));

        // Second: verify Scroll storage using Scroll P2C (simulates second hop verification)
        scrollP2CProverCopy.verifyStorageSlot(scrollStateRoot, scrollStorageProof);

        vm.stopSnapshotGas();
    }
}
