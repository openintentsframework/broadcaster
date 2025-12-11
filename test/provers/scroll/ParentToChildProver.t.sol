// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console, Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ParentToChildProver, IScrollChain} from "../../../src/contracts/provers/scroll/ParentToChildProver.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {RLP} from "@openzeppelin/contracts/utils/RLP.sol";

/// @notice Mock ScrollChain contract for testing
contract ScrollChainMock is IScrollChain {
    mapping(uint256 => bytes32) public override finalizedStateRoots;
    mapping(uint256 => bool) private _isBatchFinalized;

    function setFinalizedStateRoot(uint256 batchIndex, bytes32 stateRoot) external {
        finalizedStateRoots[batchIndex] = stateRoot;
        _isBatchFinalized[batchIndex] = true;
    }

    function isBatchFinalized(uint256 batchIndex) external view override returns (bool) {
        return _isBatchFinalized[batchIndex];
    }
}

contract ScrollParentToChildProverTest is Test {
    using stdJson for string;
    using RLP for RLP.Encoder;
    using Bytes for bytes;

    uint256 public l1ForkId;
    uint256 public l2ForkId;

    // The finalizedStateRoots mapping slot in ScrollChain
    // Determined empirically from ScrollChain on Sepolia: 0x2D567EcE699Eabe5afCd141eDB7A4f2D0D6ce8a0
    uint256 public constant FINALIZED_STATE_ROOTS_SLOT = 158;

    ParentToChildProver public parentToChildProver;
    ScrollChainMock public scrollChainMock;

    uint256 l1ChainId;
    uint256 l2ChainId;

    function setUp() public {
        // Create fork for L1 (Ethereum)
        l1ForkId = vm.createFork(vm.envString("ETHEREUM_RPC_URL"));

        vm.selectFork(l1ForkId);
        l1ChainId = block.chainid;

        // Deploy mock ScrollChain
        scrollChainMock = new ScrollChainMock();

        // Deploy ParentToChildProver
        parentToChildProver = new ParentToChildProver(
            address(scrollChainMock),
            FINALIZED_STATE_ROOTS_SLOT,
            l1ChainId
        );

        // For L2 tests, we'll use vm.chainId() to simulate being on Scroll
        l2ChainId = 534352; // Scroll mainnet chain ID
    }

    /// @notice Test getTargetBlockHash returns state root when called on home chain
    function test_getTargetBlockHash_success() public {
        vm.selectFork(l1ForkId);

        uint256 batchIndex = 12345;
        bytes32 expectedStateRoot = bytes32(uint256(0xabcdef123456));

        // Set up the mock
        scrollChainMock.setFinalizedStateRoot(batchIndex, expectedStateRoot);

        // Call getTargetBlockHash
        bytes memory input = abi.encode(batchIndex);
        bytes32 stateRoot = parentToChildProver.getTargetBlockHash(input);

        assertEq(stateRoot, expectedStateRoot, "State root mismatch");
    }

    /// @notice Test getTargetBlockHash reverts when batch is not finalized
    function test_getTargetBlockHash_stateRootNotFound() public {
        vm.selectFork(l1ForkId);

        uint256 batchIndex = 99999; // Non-existent batch

        bytes memory input = abi.encode(batchIndex);

        vm.expectRevert(ParentToChildProver.StateRootNotFound.selector);
        parentToChildProver.getTargetBlockHash(input);
    }

    /// @notice Test getTargetBlockHash reverts when not on home chain
    function test_getTargetBlockHash_notOnHomeChain() public {
        // Simulate being on a different chain (Scroll L2)
        vm.chainId(l2ChainId);

        uint256 batchIndex = 12345;
        bytes memory input = abi.encode(batchIndex);

        vm.expectRevert(ParentToChildProver.CallNotOnHomeChain.selector);
        parentToChildProver.getTargetBlockHash(input);
    }

    /// @notice Test verifyStorageSlot with real proof data
    /// @dev Uses Ethereum proof data since Scroll (post-Euclid) uses standard MPT
    function test_verifyStorageSlot_success() public {
        vm.selectFork(l1ForkId);

        bytes32 message = 0x0000000000000000000000000000000000000000000000000000000074657374; // "test"
        address publisher = 0x9a56fFd72F4B526c523C733F1F74197A51c495E1;

        uint256 expectedSlot = uint256(keccak256(abi.encode(message, publisher)));

        string memory path = "test/payloads/ethereum/broadcast_proof_block_9496454.json";

        string memory json = vm.readFile(path);
        bytes32 stateRoot = json.readBytes32(".stateRoot");
        address account = json.readAddress(".account");
        uint256 slot = json.readUint(".slot");
        bytes32 value = bytes32(json.readUint(".slotValue"));
        bytes memory rlpAccountProof = json.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = json.readBytes(".rlpStorageProof");

        assertEq(expectedSlot, slot, "slot mismatch");

        // For Scroll ParentToChildProver, the input is different - no block header needed!
        // Input: abi.encode(address account, uint256 slot, bytes accountProof, bytes storageProof)
        bytes memory input = abi.encode(account, slot, rlpAccountProof, rlpStorageProof);

        // The "targetBlockHash" for Scroll is actually the state root
        (address actualAccount, uint256 actualSlot, bytes32 actualValue) =
            parentToChildProver.verifyStorageSlot(stateRoot, input);

        assertEq(actualAccount, account, "account mismatch");
        assertEq(actualSlot, slot, "slot mismatch");
        assertEq(actualValue, value, "value mismatch");
    }

    /// @notice Test verifyStorageSlot works from non-home chain too (it's pure function)
    function test_verifyStorageSlot_fromL2() public {
        // Simulate being on Scroll L2
        vm.chainId(l2ChainId);

        string memory path = "test/payloads/ethereum/broadcast_proof_block_9496454.json";

        string memory json = vm.readFile(path);
        bytes32 stateRoot = json.readBytes32(".stateRoot");
        address account = json.readAddress(".account");
        uint256 slot = json.readUint(".slot");
        bytes32 value = bytes32(json.readUint(".slotValue"));
        bytes memory rlpAccountProof = json.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = json.readBytes(".rlpStorageProof");

        bytes memory input = abi.encode(account, slot, rlpAccountProof, rlpStorageProof);

        (address actualAccount, uint256 actualSlot, bytes32 actualValue) =
            parentToChildProver.verifyStorageSlot(stateRoot, input);

        assertEq(actualAccount, account, "account mismatch");
        assertEq(actualSlot, slot, "slot mismatch");
        assertEq(actualValue, value, "value mismatch");
    }

    /// @notice Test the full flow: get state root on L1, then verify storage
    function test_fullFlow_getAndVerify() public {
        vm.selectFork(l1ForkId);

        string memory path = "test/payloads/ethereum/broadcast_proof_block_9496454.json";
        string memory json = vm.readFile(path);

        bytes32 stateRoot = json.readBytes32(".stateRoot");
        address account = json.readAddress(".account");
        uint256 slot = json.readUint(".slot");
        bytes32 expectedValue = bytes32(json.readUint(".slotValue"));
        bytes memory rlpAccountProof = json.readBytes(".rlpAccountProof");
        bytes memory rlpStorageProof = json.readBytes(".rlpStorageProof");

        // Step 1: Set up the mock with the state root
        uint256 batchIndex = 100;
        scrollChainMock.setFinalizedStateRoot(batchIndex, stateRoot);

        // Step 2: Get the state root (simulating what happens on L1)
        bytes memory getInput = abi.encode(batchIndex);
        bytes32 retrievedStateRoot = parentToChildProver.getTargetBlockHash(getInput);

        assertEq(retrievedStateRoot, stateRoot, "Retrieved state root should match");

        // Step 3: Verify storage slot against the state root
        bytes memory verifyInput = abi.encode(account, slot, rlpAccountProof, rlpStorageProof);
        (address actualAccount, uint256 actualSlot, bytes32 actualValue) =
            parentToChildProver.verifyStorageSlot(retrievedStateRoot, verifyInput);

        assertEq(actualAccount, account, "account mismatch");
        assertEq(actualSlot, slot, "slot mismatch");
        assertEq(actualValue, expectedValue, "value mismatch");
    }

    /// @notice Test verifyTargetBlockHash reverts when called on home chain
    function test_verifyTargetBlockHash_onHomeChain() public {
        vm.selectFork(l1ForkId);

        bytes32 homeBlockHash = bytes32(uint256(1));
        bytes memory input = abi.encode(
            hex"", // rlpBlockHeader
            uint256(100), // batchIndex
            hex"", // accountProof
            hex""  // storageProof
        );

        vm.expectRevert(ParentToChildProver.CallOnHomeChain.selector);
        parentToChildProver.verifyTargetBlockHash(homeBlockHash, input);
    }

    /// @notice Test version returns 1
    function test_version() public view {
        assertEq(parentToChildProver.version(), 1);
    }

    /// @notice Test constructor sets immutables correctly
    function test_constructor() public view {
        assertEq(parentToChildProver.scrollChain(), address(scrollChainMock));
        assertEq(parentToChildProver.finalizedStateRootsSlot(), FINALIZED_STATE_ROOTS_SLOT);
        assertEq(parentToChildProver.homeChainId(), l1ChainId);
    }
}
