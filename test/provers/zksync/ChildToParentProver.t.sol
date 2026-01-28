// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console, Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Broadcaster} from "../../../src/contracts/Broadcaster.sol";
import {IBroadcaster} from "../../../src/contracts/interfaces/IBroadcaster.sol";
import {IOutbox} from "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import {ChildToParentProver} from "../../../src/contracts/provers/zksync/ChildToParentProver.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {IBuffer} from "../../../src/contracts/block-hash-pusher/interfaces/IBuffer.sol";
import {BufferMock} from "../../mocks/BufferMock.sol";
import {RLP} from "@openzeppelin/contracts/utils/RLP.sol";
import {BlockHeaders} from "../../utils/BlockHeaders.sol";

contract ZksyncChildToParentProverTest is Test {
    using stdJson for string;
    using RLP for RLP.Encoder;
    using Bytes for bytes;

    uint256 public parentForkId;
    uint256 public childForkId;

    IOutbox public outbox = IOutbox(0x65f07C7D521164a4d5DaC6eB8Fac8DA067A3B78F);

    uint256 public rootSlot = 3;

    ChildToParentProver public childToParentProver; // Home is Child, Target is Parent

    uint256 childChainId;

    address public blockHashBuffer;

    function setUp() public {
        parentForkId = vm.createFork(vm.envString("ETHEREUM_RPC_URL"));
        childForkId = vm.createFork(vm.envString("ZKSYNC_RPC_URL"));

        vm.selectFork(childForkId);
        childChainId = block.chainid;
        blockHashBuffer = address(new BufferMock());
        childToParentProver = new ChildToParentProver(blockHashBuffer, childChainId);
    }

    function test_verifyStorageSlot_broadcaster() public {
        vm.selectFork(childForkId);

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

        IBuffer buffer = IBuffer(blockHashBuffer);

        bytes32[] memory blockHashes = new bytes32[](1);
        blockHashes[0] = blockHash;

        buffer.receiveHashes(blockNumber, blockHashes);

        bytes memory input = abi.encode(rlpBlockHeader, account, expectedSlot, rlpAccountProof, rlpStorageProof);

        (address actualAccount, uint256 actualSlot, bytes32 actualValue) =
            childToParentProver.verifyStorageSlot(blockHash, input);

        assertEq(actualAccount, account, "account mismatch");
        assertEq(actualSlot, slot, "slot mismatch");
        assertEq(actualValue, value, "value mismatch");
    }

    function test_verifyStorageSlot_broadcaster_notHomeChain() public {
        vm.selectFork(parentForkId);

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

        bytes memory input = abi.encode(rlpBlockHeader, account, expectedSlot, rlpAccountProof, rlpStorageProof);

        ChildToParentProver childToParentProverCopy = new ChildToParentProver(blockHashBuffer, childChainId);

        (address actualAccount, uint256 actualSlot, bytes32 actualValue) =
            childToParentProverCopy.verifyStorageSlot(blockHash, input);

        assertEq(actualAccount, account, "account mismatch");
        assertEq(actualSlot, slot, "slot mismatch");
        assertEq(actualValue, value, "value mismatch");
    }
}
