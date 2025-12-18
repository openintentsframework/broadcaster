// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ParentToChildProver, ILineaRollup} from
    "../../../src/contracts/provers/linea/ParentToChildProver.sol";
import {stdJson} from "forge-std/StdJson.sol";

/// @notice Mock LineaRollup contract for testing
contract MockLineaRollup {
    mapping(uint256 => bytes32) public stateRootHashes;

    function setStateRootHash(uint256 blockNumber, bytes32 stateRootHash) external {
        stateRootHashes[blockNumber] = stateRootHash;
    }
}

contract ParentToChildProverTest is Test {
    using stdJson for string;

    ParentToChildProver public prover;
    MockLineaRollup public mockLineaRollup;

    // Linea addresses (for reference)
    address public constant LINEA_ROLLUP_MAINNET = 0xd19d4B5d358258f05D7B411E21A1460D11B0876F;
    address public constant LINEA_ROLLUP_SEPOLIA = 0xB218f8A4Bc926cF1cA7b3423c154a0D627Bdb7E5;

    // Chain IDs
    uint256 public constant ETH_MAINNET_CHAIN_ID = 1;
    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant LINEA_MAINNET_CHAIN_ID = 59144;
    uint256 public constant LINEA_SEPOLIA_CHAIN_ID = 59141;

    // Storage slot for stateRootHashes mapping in LineaRollup contract
    // Verified: mapping(uint256 blockNumber => bytes32 stateRootHash) at slot 282
    uint256 public constant STATE_ROOT_HASHES_SLOT = 282;

    // Test data - these would come from a real proof in production
    uint256 public constant L2_BLOCK_NUMBER = 26504504;
    bytes32 public constant L2_STATE_ROOT = 0x0d396375de9659f80ce8f3675609d20caaebd9bb76e90b4dbefd51399064a979;
    address public constant L2_BROADCASTER = 0x6BdBb69660E6849b98e8C524d266a0005D3655F7;

    function setUp() public {
        // Deploy mock LineaRollup
        mockLineaRollup = new MockLineaRollup();

        // Deploy prover with mock LineaRollup, pointing to L1 (home chain)
        prover = new ParentToChildProver(
            address(mockLineaRollup),
            STATE_ROOT_HASHES_SLOT,
            ETH_MAINNET_CHAIN_ID
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Constructor Tests
    // ═══════════════════════════════════════════════════════════════════════════

    function test_constructor() public view {
        assertEq(prover.lineaRollup(), address(mockLineaRollup));
        assertEq(prover.stateRootHashesSlot(), STATE_ROOT_HASHES_SLOT);
        assertEq(prover.homeChainId(), ETH_MAINNET_CHAIN_ID);
    }

    function test_constructor_differentParameters() public {
        ParentToChildProver newProver = new ParentToChildProver(
            address(0x123),
            99,
            12345
        );
        assertEq(newProver.lineaRollup(), address(0x123));
        assertEq(newProver.stateRootHashesSlot(), 99);
        assertEq(newProver.homeChainId(), 12345);
    }

    function testFuzz_constructor_acceptsAnyParameters(
        address _lineaRollup,
        uint256 _slot,
        uint256 _chainId
    ) public {
        ParentToChildProver newProver = new ParentToChildProver(
            _lineaRollup,
            _slot,
            _chainId
        );
        assertEq(newProver.lineaRollup(), _lineaRollup);
        assertEq(newProver.stateRootHashesSlot(), _slot);
        assertEq(newProver.homeChainId(), _chainId);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getTargetBlockHash Tests (Home Chain - L1)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_getTargetBlockHash_success() public {
        // Set up mock to return a state root
        mockLineaRollup.setStateRootHash(L2_BLOCK_NUMBER, L2_STATE_ROOT);

        // We're on L1 (home chain) by default in tests
        vm.chainId(ETH_MAINNET_CHAIN_ID);

        bytes32 stateRoot = prover.getTargetBlockHash(abi.encode(L2_BLOCK_NUMBER));

        assertEq(stateRoot, L2_STATE_ROOT);
    }

    function test_getTargetBlockHash_revertsWhenNotFound() public {
        // State root not set (returns bytes32(0))
        vm.chainId(ETH_MAINNET_CHAIN_ID);

        vm.expectRevert(ParentToChildProver.TargetStateRootNotFound.selector);
        prover.getTargetBlockHash(abi.encode(L2_BLOCK_NUMBER));
    }

    function test_getTargetBlockHash_revertsOffHomeChain() public {
        // Switch to Linea L2 (not home chain)
        vm.chainId(LINEA_MAINNET_CHAIN_ID);

        vm.expectRevert(ParentToChildProver.CallNotOnHomeChain.selector);
        prover.getTargetBlockHash(abi.encode(L2_BLOCK_NUMBER));
    }

    function test_getTargetBlockHash_zeroBlockNumber() public {
        mockLineaRollup.setStateRootHash(0, L2_STATE_ROOT);
        vm.chainId(ETH_MAINNET_CHAIN_ID);

        bytes32 stateRoot = prover.getTargetBlockHash(abi.encode(uint256(0)));
        assertEq(stateRoot, L2_STATE_ROOT);
    }

    function testFuzz_getTargetBlockHash_revertsOnUnknownBlock(uint48 blockNumber) public {
        // Don't set any state root
        vm.chainId(ETH_MAINNET_CHAIN_ID);

        vm.expectRevert(ParentToChildProver.TargetStateRootNotFound.selector);
        prover.getTargetBlockHash(abi.encode(uint256(blockNumber)));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // verifyTargetBlockHash Tests (Non-Home Chain)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_verifyTargetBlockHash_revertsOnHomeChain() public {
        // On L1 (home chain), verifyTargetBlockHash should revert
        vm.chainId(ETH_MAINNET_CHAIN_ID);

        vm.expectRevert(ParentToChildProver.CallOnHomeChain.selector);
        prover.verifyTargetBlockHash(bytes32(0), bytes(""));
    }

    /// @dev This test requires a real storage proof from L1 LineaRollup
    ///      For now, we test that the function reverts with invalid proofs
    function test_verifyTargetBlockHash_revertsWithInvalidProof() public {
        vm.chainId(LINEA_MAINNET_CHAIN_ID);

        bytes memory input = abi.encode(
            bytes("invalid header"), // rlpBlockHeader
            L2_BLOCK_NUMBER, // l2BlockNumber
            bytes("invalid account proof"), // accountProof
            bytes("invalid storage proof") // storageProof
        );

        // Should revert due to invalid proof
        vm.expectRevert();
        prover.verifyTargetBlockHash(bytes32(uint256(1)), input);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // verifyStorageSlot Tests (SMT Proof Format)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev verifyStorageSlot is pure and works on any chain
    ///      For Linea, it uses Sparse Merkle Tree (SMT) proofs with MiMC hashing
    ///      Input format: (address, uint256, uint256, bytes[], uint256, bytes[], bytes32)
    ///      Proofs must be generated using linea_getProof RPC method
    function test_verifyStorageSlot_revertsWithInvalidProof() public {
        // Create empty proof arrays (will fail verification)
        bytes[] memory emptyAccountProof = new bytes[](0);
        bytes[] memory emptyStorageProof = new bytes[](0);

        bytes memory input = abi.encode(
            address(0x123), // account
            uint256(0), // slot
            uint256(0), // accountLeafIndex
            emptyAccountProof, // accountProof (SMT format)
            uint256(0), // storageLeafIndex
            emptyStorageProof, // storageProof (SMT format)
            bytes32(0) // claimedStorageValue
        );

        // Should revert due to invalid proof (wrong proof length)
        vm.expectRevert();
        prover.verifyStorageSlot(L2_STATE_ROOT, input);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Version Tests
    // ═══════════════════════════════════════════════════════════════════════════

    function test_version() public view {
        assertEq(prover.version(), 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Integration Tests (require real SMT proofs from linea_getProof)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Integration test for L2→L1 verification using Sparse Merkle Tree proofs
    /// @dev This test requires proof data from linea_getProof RPC method
    ///      The proof file should be generated using the linea_getProof API
    ///      File format: test/payloads/linea/lineaProofL2-smt.json
    function test_integration_L2ToL1_verification_SMT() public {
        // Check if encoded proof file exists
        string memory proofPath = "test/payloads/linea/encoded-smt-proof.txt";
        try vm.readFile(proofPath) returns (string memory encodedProofHex) {
            console.log("Found encoded SMT proof file, running integration test...");

            // Expected values from the JSON file
            bytes32 zkStateRoot = 0x0b9797153d1cef2b38f6e87d2c225791b74107ae7ce28e60bf498b9d1c094f14;
            address expectedAccount = 0x20728d202A12f8306d01D0E54aE99885AfA31d83;
            uint256 expectedSlot = 0xc7f3206d60205e1634924ee1e67de7607b9a5991744aaf3526fde997abcc5170;
            bytes32 expectedValue = 0x000000000000000000000000000000000000000000000000000000006938964b;

            // Convert hex string to bytes
            bytes memory encodedProof = vm.parseBytes(encodedProofHex);

            console.log("ZK State Root:", vm.toString(zkStateRoot));
            console.log("Encoded proof length:", encodedProof.length);

            // Call verifyStorageSlot with the SMT proof
            (address account, uint256 slot, bytes32 value) = prover.verifyStorageSlot(zkStateRoot, encodedProof);

            console.log("Verified Account:", account);
            console.log("Verified Slot:", slot);
            console.log("Verified Value:", vm.toString(value));

            // Verify the results match expected values
            assertEq(account, expectedAccount, "Account mismatch");
            assertEq(slot, expectedSlot, "Slot mismatch");
            assertEq(value, expectedValue, "Value mismatch");

            console.log("SMT proof verification SUCCESS!");
        } catch {
            // Proof file doesn't exist, skip test
            console.log("Skipping SMT integration test - encoded proof file not found");
            console.log("Generate proof using: node scripts/linea/encode-smt-proof.js");
        }
    }

    /// @notice Legacy test that documents the old MPT format is no longer supported
    /// @dev Linea uses SMT (Sparse Merkle Tree), not MPT (Merkle-Patricia Trie)
    ///      The stateRootHashes on L1 store SMT roots, not MPT roots
    function test_legacy_MPT_format_not_supported() public pure {
        // This test documents that:
        // 1. Linea L2 blocks have an MPT stateRoot in the header
        // 2. BUT LineaRollup on L1 stores a DIFFERENT ZK SMT stateRoot
        // 3. Therefore eth_getProof (MPT) proofs cannot verify against L1's stateRootHashes
        // 4. Must use linea_getProof (SMT) proofs instead
        //
        // Example:
        // L2 Block stateRoot (MPT): 0xa8cd77482ddd4b54e678023293190493c9d9d50e094e1402b4d044f153e7bc46
        // L1 stateRootHashes (SMT): 0x0b9797153d1cef2b38f6e87d2c225791b74107ae7ce28e60bf498b9d1c094f14
        // These are DIFFERENT values!
    }
}
