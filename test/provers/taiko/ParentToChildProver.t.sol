// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ParentToChildProver} from "../../../src/contracts/provers/taiko/ParentToChildProver.sol";

/// @notice Mock SignalService for testing getTargetStateCommitment
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

/// @title ParentToChildProver Tests
/// @notice Tests for the Taiko ParentToChildProver (L1 → L2 verification)
/// @dev Home chain: L1 (Ethereum). Target chain: L2 (Taiko).
///      - getTargetStateCommitment: Called on L1 to read L2 block hash from L1's SignalService
///      - verifyTargetStateCommitment: Called on L2 to verify L2 block hash via storage proof
///      - verifyStorageSlot: Verifies storage slots against a trusted block hash
contract TaikoParentToChildProverTest is Test {
    using stdJson for string;

    ParentToChildProver public prover;
    MockSignalService public mockSignalService;

    // Taiko Testnet addresses (for reference)
    address public constant L1_SIGNAL_SERVICE_ADDR = 0x53789e39E3310737E8C8cED483032AAc25B39ded;
    uint256 public constant CHECKPOINTS_SLOT = 254;
    uint256 public constant L1_CHAIN_ID = 32382; // Taiko Testnet L1
    uint256 public constant L2_CHAIN_ID = 167001; // Taiko Testnet L2

    // Test data from taikoProofL2.json (L2 proof for L2→L1 verification)
    // This proof is used to verify storage on L2 from L1's perspective
    uint256 public constant L2_BLOCK_NUMBER = 0x62d; // 1581
    bytes32 public constant L2_BLOCK_HASH = 0xb859c7813278100c2f3534eafb86fd13b4ef36bd1f5edb03dc635a87d41db6c4;
    bytes32 public constant L2_STATE_ROOT = 0x8652ba175668dfcac7ecbdafa1fa852bb48c61c8bc972f05b9fd9c0090e3c0ac;
    address public constant L2_BROADCASTER = 0x6BdBb69660E6849b98e8C524d266a0005D3655F7;
    uint256 public constant L2_STORAGE_SLOT = 0xda4c7a797a4637b5fae314d1baf6d995c386ddc64cc60315cded0efdeb9f0e15;
    bytes32 public constant L2_SLOT_VALUE = 0x0000000000000000000000000000000000000000000000000000000069385d14;

    function setUp() public {
        // Deploy mock SignalService
        mockSignalService = new MockSignalService();
        // Deploy prover with mock SignalService
        prover = new ParentToChildProver(address(mockSignalService), CHECKPOINTS_SLOT, L1_CHAIN_ID);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Constructor Tests
    // ═══════════════════════════════════════════════════════════════════════════

    function test_constructor() public view {
        assertEq(prover.signalService(), address(mockSignalService), "signalService mismatch");
        assertEq(prover.checkpointsSlot(), CHECKPOINTS_SLOT, "checkpointsSlot mismatch");
        assertEq(prover.homeChainId(), L1_CHAIN_ID, "homeChainId mismatch");
    }

    function test_version() public view {
        assertEq(prover.version(), 1, "version should be 1");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Chain ID Validation Tests
    // ═══════════════════════════════════════════════════════════════════════════

    function test_verifyTargetStateCommitment_revertsOnHomeChain() public {
        vm.chainId(L1_CHAIN_ID);

        bytes memory input = abi.encode(bytes(""), uint48(0), bytes(""), bytes(""));

        vm.expectRevert(ParentToChildProver.CallOnHomeChain.selector);
        prover.verifyTargetStateCommitment(bytes32(0), input);
    }

    function test_getTargetStateCommitment_revertsOffHomeChain() public {
        vm.chainId(L2_CHAIN_ID);

        bytes memory input = abi.encode(uint48(0));

        vm.expectRevert(ParentToChildProver.CallNotOnHomeChain.selector);
        prover.getTargetStateCommitment(input);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getTargetStateCommitment Tests (Called on L1 to read L2 block hash)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_getTargetStateCommitment_success() public {
        vm.chainId(L1_CHAIN_ID);

        // Set checkpoint in mock SignalService
        mockSignalService.setCheckpoint(uint48(L2_BLOCK_NUMBER), L2_BLOCK_HASH, L2_STATE_ROOT);

        bytes memory input = abi.encode(uint48(L2_BLOCK_NUMBER));
        bytes32 targetStateCommitment = prover.getTargetStateCommitment(input);

        assertEq(targetStateCommitment, L2_BLOCK_HASH, "targetStateCommitment mismatch");
    }

    function test_getTargetStateCommitment_revertsWhenNotFound() public {
        vm.chainId(L1_CHAIN_ID);

        // Don't set any checkpoint - it doesn't exist
        bytes memory input = abi.encode(uint48(99999));

        // Reverts with SignalService's SS_CHECKPOINT_NOT_FOUND error
        vm.expectRevert(MockSignalService.SS_CHECKPOINT_NOT_FOUND.selector);
        prover.getTargetStateCommitment(input);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // verifyStorageSlot Tests
    // ═══════════════════════════════════════════════════════════════════════════

    function test_verifyStorageSlot_success() public {
        // Load proof data from JSON
        string memory proofJson = vm.readFile("test/payloads/taiko/taikoProofL2.json");

        bytes memory rlpBlockHeader = proofJson.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProof = proofJson.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = proofJson.readBytes(".rlpStorageProof");

        // Verify the block header hashes to the expected block hash
        bytes32 computedBlockHash = keccak256(rlpBlockHeader);
        assertEq(computedBlockHash, L2_BLOCK_HASH, "rlpBlockHeader hash mismatch");

        // Encode storage proof input
        bytes memory storageProofInput =
            abi.encode(rlpBlockHeader, L2_BROADCASTER, L2_STORAGE_SLOT, rlpAccountProof, rlpStorageProof);

        // Call verifyStorageSlot with the trusted block hash
        (address account, uint256 slot, bytes32 value) = prover.verifyStorageSlot(L2_BLOCK_HASH, storageProofInput);

        assertEq(account, L2_BROADCASTER, "account mismatch");
        assertEq(slot, L2_STORAGE_SLOT, "slot mismatch");
        assertEq(value, L2_SLOT_VALUE, "value mismatch");
    }

    function test_verifyStorageSlot_revertsWithWrongBlockHash() public {
        // Load proof data
        string memory proofJson = vm.readFile("test/payloads/taiko/taikoProofL2.json");

        bytes memory rlpBlockHeader = proofJson.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProof = proofJson.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = proofJson.readBytes(".rlpStorageProof");

        bytes memory storageProofInput =
            abi.encode(rlpBlockHeader, L2_BROADCASTER, L2_STORAGE_SLOT, rlpAccountProof, rlpStorageProof);

        // Use wrong block hash - should revert
        bytes32 wrongBlockHash = bytes32(uint256(1));

        vm.expectRevert();
        prover.verifyStorageSlot(wrongBlockHash, storageProofInput);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // verifyTargetStateCommitment Tests (Called on L2 to verify via storage proof)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test verifyTargetStateCommitment with mocked L1 state
    /// @dev This simulates being on L2 and verifying that L1's SignalService
    ///      contains a checkpoint for a specific L2 block
    function test_verifyTargetStateCommitment_withMockedProof() public {
        // Simulate being on L2 (not home chain)
        vm.chainId(L2_CHAIN_ID);

        // For verifyTargetStateCommitment, we need:
        // 1. An L1 block hash (homeStateCommitment) - the trusted anchor
        // 2. Proof that L1's SignalService contains the L2 checkpoint

        // This is a simplified test - in production you'd need actual L1 proofs
        // For now, we test the chain ID check and basic flow

        // Create mock input (would need real L1 proofs for full test)
        bytes memory mockRlpHeader = hex"f90200"; // Minimal RLP (will fail proof verification)
        bytes memory input = abi.encode(
            mockRlpHeader,
            uint48(L2_BLOCK_NUMBER),
            bytes(""), // accountProof
            bytes("") // storageProof
        );

        // This will revert because the proof is invalid, but it proves we're past chain ID check
        vm.expectRevert(); // Will revert on invalid RLP/proof
        prover.verifyTargetStateCommitment(bytes32(uint256(1)), input);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Integration Test with Full Proof Data
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Full integration test simulating the complete L2→L1 verification flow
    /// @dev This test:
    ///      1. Deploys the prover configured for L1 as home chain
    ///      2. Sets L1's SignalService with an L2 checkpoint
    ///      3. Uses getTargetStateCommitment (on L1) to get L2 block hash
    ///      4. Uses verifyStorageSlot to verify L2 Broadcaster storage
    function test_integration_L2ToL1_verification() public {
        // Step 1: Configure chain as L1 (home chain)
        vm.chainId(L1_CHAIN_ID);

        // Step 2: Set L1's SignalService checkpoint for L2 block
        mockSignalService.setCheckpoint(uint48(L2_BLOCK_NUMBER), L2_BLOCK_HASH, L2_STATE_ROOT);

        // Step 3: Get L2 block hash from L1's SignalService
        bytes memory getInput = abi.encode(uint48(L2_BLOCK_NUMBER));
        bytes32 l2BlockHash = prover.getTargetStateCommitment(getInput);
        assertEq(l2BlockHash, L2_BLOCK_HASH, "L2 block hash mismatch");

        // Step 4: Load proof data and verify L2 storage
        string memory proofJson = vm.readFile("test/payloads/taiko/taikoProofL2.json");
        bytes memory rlpBlockHeader = proofJson.readBytes(".rlpBlockHeader");
        bytes memory rlpAccountProof = proofJson.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = proofJson.readBytes(".rlpStorageProof");

        bytes memory storageProofInput =
            abi.encode(rlpBlockHeader, L2_BROADCASTER, L2_STORAGE_SLOT, rlpAccountProof, rlpStorageProof);

        (address account, uint256 slot, bytes32 value) = prover.verifyStorageSlot(l2BlockHash, storageProofInput);

        assertEq(account, L2_BROADCASTER, "Broadcaster address mismatch");
        assertEq(slot, L2_STORAGE_SLOT, "Storage slot mismatch");
        assertNotEq(value, bytes32(0), "Value should not be zero (timestamp)");

        console.log("Integration test passed!");
        console.log("Verified L2 Broadcaster storage from L1");
        console.log("L2 Block:", L2_BLOCK_NUMBER);
        console.log("Storage Value (timestamp):", uint256(value));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Edge Case Tests
    // ═══════════════════════════════════════════════════════════════════════════

    function test_getTargetStateCommitment_zeroBlockNumber() public {
        vm.chainId(L1_CHAIN_ID);

        // Block 0 with no checkpoint should revert
        bytes memory input = abi.encode(uint48(0));

        // Reverts with SignalService's SS_CHECKPOINT_NOT_FOUND error
        vm.expectRevert(MockSignalService.SS_CHECKPOINT_NOT_FOUND.selector);
        prover.getTargetStateCommitment(input);
    }

    function test_constructor_differentParameters() public {
        address customSignalService = address(0x5678);
        uint256 customSlot = 200;
        uint256 customChainId = 888;

        ParentToChildProver customProver = new ParentToChildProver(customSignalService, customSlot, customChainId);

        assertEq(customProver.signalService(), customSignalService);
        assertEq(customProver.checkpointsSlot(), customSlot);
        assertEq(customProver.homeChainId(), customChainId);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Fuzz Tests
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_getTargetStateCommitment_revertsOnUnknownBlock(uint48 blockNumber) public {
        vm.chainId(L1_CHAIN_ID);

        // Any block number without a mocked checkpoint should revert
        bytes memory input = abi.encode(blockNumber);

        // Reverts with SignalService's SS_CHECKPOINT_NOT_FOUND error
        vm.expectRevert(MockSignalService.SS_CHECKPOINT_NOT_FOUND.selector);
        prover.getTargetStateCommitment(input);
    }

    function testFuzz_constructor_acceptsAnyParameters(address signalService, uint256 slot, uint256 chainId) public {
        vm.assume(signalService != address(0));

        ParentToChildProver fuzzProver = new ParentToChildProver(signalService, slot, chainId);

        assertEq(fuzzProver.signalService(), signalService);
        assertEq(fuzzProver.checkpointsSlot(), slot);
        assertEq(fuzzProver.homeChainId(), chainId);
    }
}
