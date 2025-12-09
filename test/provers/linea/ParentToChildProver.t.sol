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
    // verifyStorageSlot Tests
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev verifyStorageSlot is pure and works on any chain
    ///      For Linea, it takes the state root directly (not block hash)
    ///      This test requires a real storage proof from Linea L2
    function test_verifyStorageSlot_revertsWithInvalidProof() public {
        bytes memory input = abi.encode(
            address(0x123), // account
            uint256(0), // slot
            bytes("invalid account proof"), // accountProof
            bytes("invalid storage proof") // storageProof
        );

        // Should revert due to invalid proof
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
    // Integration Tests (require real proofs)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Integration test for L2→L1 verification
    /// @dev This test is skipped until we have real proof data
    ///      To enable: generate proof using scripts/generate-linea-proof.ts
    function test_integration_L2ToL1_verification() public {
        // Check if proof file exists
        string memory proofPath = "test/payloads/linea/lineaProofL2.json";
        try vm.readFile(proofPath) returns (string memory json) {
            // Parse proof data
            uint256 l2BlockNumber = json.readUint(".l2BlockNumber");
            bytes32 l2StateRoot = json.readBytes32(".l2StateRoot");
            address account = json.readAddress(".account");
            uint256 slot = json.readUint(".slot");
            bytes32 expectedValue = json.readBytes32(".slotValue");
            bytes memory accountProof = json.readBytes(".rlpAccountProof");
            bytes memory storageProof = json.readBytes(".rlpStorageProof");

            // Set up mock
            mockLineaRollup.setStateRootHash(l2BlockNumber, l2StateRoot);
            vm.chainId(ETH_MAINNET_CHAIN_ID);

            // Step 1: Get L2 state root from L1's LineaRollup
            bytes32 stateRoot = prover.getTargetBlockHash(abi.encode(l2BlockNumber));
            assertEq(stateRoot, l2StateRoot, "State root mismatch");

            // Step 2: Verify storage slot on L2 (using state root directly)
            bytes memory storageInput = abi.encode(
                account,
                slot,
                accountProof,
                storageProof
            );

            (address returnedAccount, uint256 returnedSlot, bytes32 value) =
                prover.verifyStorageSlot(stateRoot, storageInput);

            // Step 3: Verify results
            assertEq(returnedAccount, account, "Account mismatch");
            assertEq(returnedSlot, slot, "Slot mismatch");
            assertEq(value, expectedValue, "Value mismatch");

            console.log("Integration test passed!");
            console.log("Verified Linea L2 storage from L1");
            console.log("L2 Block:", l2BlockNumber);
            console.log("Storage Value (timestamp):", uint256(value));
        } catch {
            // Proof file doesn't exist, skip test
            console.log("Skipping integration test - proof file not found");
            console.log("Generate proof using: npm run generate-linea-proof");
        }
    }
}
