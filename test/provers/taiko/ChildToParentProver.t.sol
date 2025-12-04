// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ChildToParentProver} from "../../../src/contracts/provers/taiko/ChildToParentProver.sol";

/// @notice Mock SignalService for testing getTargetBlockHash
contract MockSignalService {
    struct Checkpoint {
        uint48 blockNumber;
        bytes32 blockHash;
        bytes32 stateRoot;
    }

    mapping(uint48 => Checkpoint) private _checkpoints;

    error SS_CHECKPOINT_NOT_FOUND();

    function setCheckpoint(uint48 blockNumber, bytes32 blockHash, bytes32 stateRoot) external {
        _checkpoints[blockNumber] = Checkpoint(blockNumber, blockHash, stateRoot);
    }

    function getCheckpoint(uint48 blockNumber) external view returns (Checkpoint memory) {
        Checkpoint memory cp = _checkpoints[blockNumber];
        if (cp.blockHash == bytes32(0)) revert SS_CHECKPOINT_NOT_FOUND();
        return cp;
    }
}

/// @title ChildToParentProver Tests
/// @notice Tests for the Taiko ChildToParentProver (L2 → L1 verification)
/// @dev Home chain: L2 (Taiko). Target chain: L1 (Ethereum).
///      - getTargetBlockHash: Called on L2 to read L1 block hash from L2's SignalService
///      - verifyTargetBlockHash: Called on L1 to verify L1 block hash via storage proof
///      - verifyStorageSlot: Verifies storage slots against a trusted block hash
contract ChildToParentProverTest is Test {
    using stdJson for string;

    ChildToParentProver public prover;
    MockSignalService public mockSignalService;

    // Taiko Testnet addresses (for reference)
    address public constant L2_SIGNAL_SERVICE_ADDR = 0x1670010000000000000000000000000000000005;
    uint256 public constant CHECKPOINTS_SLOT = 254;
    uint256 public constant L2_CHAIN_ID = 167001; // Taiko Testnet L2
    uint256 public constant L1_CHAIN_ID = 32382; // Taiko Testnet L1

    // Test data from taikoProofL1.json (L1 proof for L1→L2 verification)
    // This proof is used to verify storage on L1 from L2's perspective
    uint256 public constant L1_BLOCK_NUMBER = 0x1240e; // 74766
    bytes32 public constant L1_BLOCK_HASH = 0xa20a4e4c6975d1dca32b6f918b3fa6e6e34f91e5c05f58452e0df971c61eedb4;
    bytes32 public constant L1_STATE_ROOT = 0x931492d632445e093fd2d11c0f805b84240b2dc0d4b6bf9755052989cb4a836d;
    address public constant L1_BROADCASTER = 0x6BdBb69660E6849b98e8C524d266a0005D3655F7;
    uint256 public constant L1_STORAGE_SLOT = 0x6ab5708884ce7bb97ad17ef43f5008d5fd794387f75759d864911479a6cc1e0f;
    bytes32 public constant L1_SLOT_VALUE = 0x00000000000000000000000000000000000000000000000000000000692f3ed4;

    function setUp() public {
        // Deploy mock SignalService
        mockSignalService = new MockSignalService();
        // Deploy prover with mock SignalService
        prover = new ChildToParentProver(address(mockSignalService), CHECKPOINTS_SLOT, L2_CHAIN_ID);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Constructor Tests
    // ═══════════════════════════════════════════════════════════════════════════

    function test_constructor() public view {
        assertEq(prover.signalService(), address(mockSignalService), "signalService mismatch");
        assertEq(prover.checkpointsSlot(), CHECKPOINTS_SLOT, "checkpointsSlot mismatch");
        assertEq(prover.homeChainId(), L2_CHAIN_ID, "homeChainId mismatch");
    }

    function test_version() public view {
        assertEq(prover.version(), 1, "version should be 1");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Chain ID Validation Tests
    // ═══════════════════════════════════════════════════════════════════════════

    function test_verifyTargetBlockHash_revertsOnHomeChain() public {
        vm.chainId(L2_CHAIN_ID);

        bytes memory input = abi.encode(bytes(""), uint48(0), bytes(""), bytes(""));

        vm.expectRevert(ChildToParentProver.CallOnHomeChain.selector);
        prover.verifyTargetBlockHash(bytes32(0), input);
    }

    function test_getTargetBlockHash_revertsOffHomeChain() public {
        vm.chainId(L1_CHAIN_ID);

        bytes memory input = abi.encode(uint48(0));

        vm.expectRevert(ChildToParentProver.CallNotOnHomeChain.selector);
        prover.getTargetBlockHash(input);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getTargetBlockHash Tests (Called on L2 to read L1 block hash)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_getTargetBlockHash_success() public {
        vm.chainId(L2_CHAIN_ID);

        // Set checkpoint in mock SignalService
        mockSignalService.setCheckpoint(uint48(L1_BLOCK_NUMBER), L1_BLOCK_HASH, L1_STATE_ROOT);

        bytes memory input = abi.encode(uint48(L1_BLOCK_NUMBER));
        bytes32 targetBlockHash = prover.getTargetBlockHash(input);

        assertEq(targetBlockHash, L1_BLOCK_HASH, "targetBlockHash mismatch");
    }

    function test_getTargetBlockHash_revertsWhenNotFound() public {
        vm.chainId(L2_CHAIN_ID);

        // Don't set any checkpoint - it doesn't exist
        bytes memory input = abi.encode(uint48(99999));

        // Reverts with SignalService's SS_CHECKPOINT_NOT_FOUND error
        vm.expectRevert(MockSignalService.SS_CHECKPOINT_NOT_FOUND.selector);
        prover.getTargetBlockHash(input);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // verifyStorageSlot Tests
    // ═══════════════════════════════════════════════════════════════════════════

    function test_verifyStorageSlot_success() public {
        // Load proof data from JSON
        string memory proofJson = vm.readFile("test/payloads/taiko/taikoProofL1.json");

        bytes memory rlpBlockHeader = proofJson.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProof = proofJson.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = proofJson.readBytes(".rlpStorageProof");

        // Verify the block header hashes to the expected block hash
        bytes32 computedBlockHash = keccak256(rlpBlockHeader);
        assertEq(computedBlockHash, L1_BLOCK_HASH, "rlpBlockHeader hash mismatch");

        // Encode storage proof input
        bytes memory storageProofInput = abi.encode(
            rlpBlockHeader,
            L1_BROADCASTER,
            L1_STORAGE_SLOT,
            rlpAccountProof,
            rlpStorageProof
        );

        // Call verifyStorageSlot with the trusted block hash
        (address account, uint256 slot, bytes32 value) = prover.verifyStorageSlot(L1_BLOCK_HASH, storageProofInput);

        assertEq(account, L1_BROADCASTER, "account mismatch");
        assertEq(slot, L1_STORAGE_SLOT, "slot mismatch");
        assertEq(value, L1_SLOT_VALUE, "value mismatch");
    }

    function test_verifyStorageSlot_revertsWithWrongBlockHash() public {
        // Load proof data
        string memory proofJson = vm.readFile("test/payloads/taiko/taikoProofL1.json");

        bytes memory rlpBlockHeader = proofJson.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProof = proofJson.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = proofJson.readBytes(".rlpStorageProof");

        bytes memory storageProofInput = abi.encode(
            rlpBlockHeader,
            L1_BROADCASTER,
            L1_STORAGE_SLOT,
            rlpAccountProof,
            rlpStorageProof
        );

        // Use wrong block hash - should revert
        bytes32 wrongBlockHash = bytes32(uint256(1));

        vm.expectRevert();
        prover.verifyStorageSlot(wrongBlockHash, storageProofInput);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // verifyTargetBlockHash Tests (Called on L1 to verify via storage proof)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test verifyTargetBlockHash with mocked L2 state
    /// @dev This simulates being on L1 and verifying that L2's SignalService
    ///      contains a checkpoint for a specific L1 block
    function test_verifyTargetBlockHash_withMockedProof() public {
        // Simulate being on L1 (not home chain)
        vm.chainId(L1_CHAIN_ID);

        // For verifyTargetBlockHash, we need:
        // 1. An L2 block hash (homeBlockHash) - the trusted anchor
        // 2. Proof that L2's SignalService contains the L1 checkpoint

        // This is a simplified test - in production you'd need actual L2 proofs
        // For now, we test the chain ID check and basic flow

        // Create mock input (would need real L2 proofs for full test)
        bytes memory mockRlpHeader = hex"f90200"; // Minimal RLP (will fail proof verification)
        bytes memory input = abi.encode(
            mockRlpHeader,
            uint48(L1_BLOCK_NUMBER),
            bytes(""), // accountProof
            bytes("") // storageProof
        );

        // This will revert because the proof is invalid, but it proves we're past chain ID check
        vm.expectRevert(); // Will revert on invalid RLP/proof
        prover.verifyTargetBlockHash(bytes32(uint256(1)), input);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Integration Test with Full Proof Data
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Full integration test simulating the complete L1→L2 verification flow
    /// @dev This test:
    ///      1. Deploys the prover configured for L2 as home chain
    ///      2. Sets L2's SignalService with an L1 checkpoint
    ///      3. Uses getTargetBlockHash (on L2) to get L1 block hash
    ///      4. Uses verifyStorageSlot to verify L1 Broadcaster storage
    function test_integration_L1ToL2_verification() public {
        // Step 1: Configure chain as L2 (home chain)
        vm.chainId(L2_CHAIN_ID);

        // Step 2: Set L2's SignalService checkpoint for L1 block
        mockSignalService.setCheckpoint(uint48(L1_BLOCK_NUMBER), L1_BLOCK_HASH, L1_STATE_ROOT);

        // Step 3: Get L1 block hash from L2's SignalService
        bytes memory getInput = abi.encode(uint48(L1_BLOCK_NUMBER));
        bytes32 l1BlockHash = prover.getTargetBlockHash(getInput);
        assertEq(l1BlockHash, L1_BLOCK_HASH, "L1 block hash mismatch");

        // Step 4: Load proof data and verify L1 storage
        string memory proofJson = vm.readFile("test/payloads/taiko/taikoProofL1.json");
        bytes memory rlpBlockHeader = proofJson.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProof = proofJson.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = proofJson.readBytes(".rlpStorageProof");

        bytes memory storageProofInput = abi.encode(
            rlpBlockHeader,
            L1_BROADCASTER,
            L1_STORAGE_SLOT,
            rlpAccountProof,
            rlpStorageProof
        );

        (address account, uint256 slot, bytes32 value) = prover.verifyStorageSlot(l1BlockHash, storageProofInput);

        assertEq(account, L1_BROADCASTER, "Broadcaster address mismatch");
        assertEq(slot, L1_STORAGE_SLOT, "Storage slot mismatch");
        assertNotEq(value, bytes32(0), "Value should not be zero (timestamp)");

        console.log("Integration test passed!");
        console.log("Verified L1 Broadcaster storage from L2");
        console.log("L1 Block:", L1_BLOCK_NUMBER);
        console.log("Storage Value (timestamp):", uint256(value));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Edge Case Tests
    // ═══════════════════════════════════════════════════════════════════════════

    function test_getTargetBlockHash_zeroBlockNumber() public {
        vm.chainId(L2_CHAIN_ID);

        // Block 0 with no checkpoint should revert
        bytes memory input = abi.encode(uint48(0));

        // Reverts with SignalService's SS_CHECKPOINT_NOT_FOUND error
        vm.expectRevert(MockSignalService.SS_CHECKPOINT_NOT_FOUND.selector);
        prover.getTargetBlockHash(input);
    }

    function test_constructor_differentParameters() public {
        address customSignalService = address(0x1234);
        uint256 customSlot = 100;
        uint256 customChainId = 999;

        ChildToParentProver customProver = new ChildToParentProver(
            customSignalService,
            customSlot,
            customChainId
        );

        assertEq(customProver.signalService(), customSignalService);
        assertEq(customProver.checkpointsSlot(), customSlot);
        assertEq(customProver.homeChainId(), customChainId);
    }
}
