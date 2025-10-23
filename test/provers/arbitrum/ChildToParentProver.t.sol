// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console, Test} from "forge-std/Test.sol";
import {Broadcaster} from "../../../src/contracts/Broadcaster.sol";
import {IBroadcaster} from "../../../src/contracts/interfaces/IBroadcaster.sol";
import {ParentToChildProver} from "../../../src/contracts/provers/arbitrum/ParentToChildProver.sol";
import {IOutbox} from "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import {ChildToParentProver} from "../../../src/contracts/provers/arbitrum/ChildToParentProver.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {IBuffer} from "block-hash-pusher/contracts/interfaces/IBuffer.sol";

import {RLP} from "@openzeppelin/contracts/utils/RLP.sol";

contract BroadcasterTest is Test {
    using RLP for RLP.Encoder;
    using Bytes for bytes;

    uint256 public parentForkId;
    uint256 public childForkId;

    IOutbox public outbox = IOutbox(0x65f07C7D521164a4d5DaC6eB8Fac8DA067A3B78F);

    uint256 public rootSlot = 3;

    ChildToParentProver public childToParentProver; // Home is Child, Target is Parent

    uint256 childChainId;

    function setUp() public {
        parentForkId = vm.createFork(vm.envString("ETHEREUM_RPC_URL"));
        childForkId = vm.createFork(vm.envString("ARBITRUM_RPC_URL"));

        vm.selectFork(childForkId);
        childChainId = block.chainid;
        childToParentProver = new ChildToParentProver(childChainId);
    }

    function _loadPayload(string memory path) internal view returns (bytes memory payload) {
        payload = vm.parseBytes(vm.readFile(string.concat(vm.projectRoot(), "/", path)));
    }

    function test_getTargetBlockHash() public {
        vm.selectFork(childForkId);
        bytes memory payload = _loadPayload("test/payloads/arbitrum/calldata_get.hex");

        assertEq(payload.length, 64);

        bytes32 input;
        bytes32 targetBlockHash;

        assembly {
            input := mload(add(payload, 0x20))
            targetBlockHash := mload(add(payload, 0x40))
        }

        bytes32 result = childToParentProver.getTargetBlockHash(abi.encode(input));

        assertEq(result, targetBlockHash);
    }

    function test_reverts_getTargetBlockHash_on_target_chain() public {
        vm.selectFork(parentForkId);
        bytes memory payload = _loadPayload("test/payloads/arbitrum/calldata_get.hex");

        ChildToParentProver newChildToParentProver = new ChildToParentProver(childChainId);

        assertEq(payload.length, 64);

        bytes32 input;
        bytes32 targetBlockHash;

        assembly {
            input := mload(add(payload, 0x20))
            targetBlockHash := mload(add(payload, 0x40))
        }

        vm.expectRevert(ChildToParentProver.CallNotOnHomeChain.selector);
        newChildToParentProver.getTargetBlockHash(abi.encode(input));
    }

    function test_reverts_getTargetBlockHash_reverts_not_found() public {
        vm.selectFork(childForkId);

        uint256 input = type(uint256).max;

        vm.expectRevert(abi.encodeWithSelector(IBuffer.UnknownParentChainBlockHash.selector, input));
        childToParentProver.getTargetBlockHash(abi.encode(input));
    }

    function test_verifyTargetBlockHash() public {
        vm.selectFork(parentForkId);

        bytes memory payload = _loadPayload("test/payloads/arbitrum/calldata_verify_target.hex");

        ChildToParentProver childToParentProverCopy = new ChildToParentProver(childChainId);

        assertGt(payload.length, 64);

        bytes32 homeBlockHash;
        bytes32 targetBlockHash;

        bytes memory input = Bytes.slice(payload, 64);

        assembly {
            homeBlockHash := mload(add(payload, 0x20))
            targetBlockHash := mload(add(payload, 0x40))
        }

        bytes32 result = childToParentProverCopy.verifyTargetBlockHash(homeBlockHash, input);

        assertEq(result, targetBlockHash);
    }

    function test_verifyTargetBlockHash_reverts_on_home_chain() public {
        vm.selectFork(childForkId);

        bytes memory payload = _loadPayload("test/payloads/arbitrum/calldata_verify_target.hex");

        ChildToParentProver childToParentProverCopy = new ChildToParentProver(childChainId);

        assertGt(payload.length, 64);

        bytes32 homeBlockHash;
        bytes32 targetBlockHash;

        bytes memory input = Bytes.slice(payload, 64);

        assembly {
            homeBlockHash := mload(add(payload, 0x20))
            targetBlockHash := mload(add(payload, 0x40))
        }

        vm.expectRevert(ChildToParentProver.CallOnHomeChain.selector);
        childToParentProverCopy.verifyTargetBlockHash(homeBlockHash, input);
    }

    function test_verifyStorageSlot() public {
        vm.selectFork(parentForkId);

        address knownAccount = 0x38f918D0E9F1b721EDaA41302E399fa1B79333a9;
        uint256 knownSlot = 10;

        bytes memory payload = _loadPayload("test/payloads/arbitrum/calldata_verify_slot.hex");

        ChildToParentProver childToParentProverCopy = new ChildToParentProver(childChainId);

        assertGt(payload.length, 64);

        bytes32 targetBlockHash;
        bytes32 storageSlotValue;
        bytes memory input = Bytes.slice(payload, 64);

        assembly {
            targetBlockHash := mload(add(payload, 0x20))
            storageSlotValue := mload(add(payload, 0x40))
        }

        (address account, uint256 slot, bytes32 value) =
            childToParentProverCopy.verifyStorageSlot(targetBlockHash, input);

        assertEq(account, knownAccount);
        assertEq(slot, knownSlot);
        assertEq(value, storageSlotValue);
    }
}
