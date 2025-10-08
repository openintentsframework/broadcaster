// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console, Test} from "forge-std/Test.sol";
import {Broadcaster} from "../../../src/contracts/Broadcaster.sol";
import {IBroadcaster} from "../../../src/contracts/interfaces/IBroadcaster.sol";
import {ParentToChildProver} from "../../../src/contracts/provers/arbitrum/ParentToChildProver.sol";
import {IOutbox} from "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import {ChildToParentProver} from "../../../src/contracts/provers/arbitrum/ChildToParentProver.sol";
import {ArbitrumOutputMock} from "../../mocks/ArbitrumOutputMock.sol";

import {RLP} from "@openzeppelin/contracts/utils/RLP.sol";
import {BlockHeaders} from "../../utils/BlockHeaders.sol";
import {Lib_RLPWriter} from "@eth-optimism/contracts/libraries/rlp/Lib_RLPWriter.sol";

contract BroadcasterTest is Test {
    using RLP for RLP.Encoder;

    Broadcaster public broadcaster;

    address public publisher = makeAddr("publisher");
    uint256 public parentForkId;
    uint256 public childForkId;

    ParentToChildProver public parentToChildProver;
    ChildToParentProver public childToParentProver;

    ArbitrumOutputMock public arbOutputMock = new ArbitrumOutputMock();

    IOutbox public outbox = IOutbox(address(arbOutputMock));

    uint256 public rootSlot = 3;

    function getMockBlockHeader() public pure returns (bytes memory) {
        BlockHeaders.L1BlockHeader memory h = BlockHeaders.L1BlockHeader({
            parentHash: bytes32(uint256(0x27870928347)),
            sha3Uncles: bytes32(uint256(0x27870928347)),
            miner: address(0x27870928347),
            stateRoot: bytes32(uint256(0x27870928347)),
            transactionsRoot: bytes32(uint256(0x27870928347)),
            receiptsRoot: bytes32(uint256(0x27870928347)),
            logsBloom: hex"",
            difficulty: 0,
            number: 0,
            gasLimit: 0,
            gasUsed: 0,
            timestamp: 0,
            extraData: hex"",
            mixHash: bytes32(uint256(0x27870928347)),
            nonce: bytes8(uint64(0x27870928347)),
            baseFeePerGas: 0,
            withdrawalsRoot: bytes32(uint256(0x27870928347)),
            blobGasUsed: 0,
            excessBlobGas: 0,
            parentBeaconBlockRoot: bytes32(uint256(0x27870928347)),
            requestsHash: bytes32(uint256(0x27870928347))
        });

        return BlockHeaders.encode(h);
    }

    function _generateStorageProof(bytes32 key, bytes32 value) internal pure returns (bytes[] memory) {
        // For our simplified trie with a single leaf node, the proof is the leaf itself
        bytes[] memory proof = new bytes[](1);

        // Convert key to nibbles
        bytes memory nibbles = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            nibbles[i * 2] = bytes1(uint8(key[i]) / 16);
            nibbles[i * 2 + 1] = bytes1(uint8(key[i]) % 16);
        }

        // Encode path
        bytes memory path = new bytes(65);
        path[0] = bytes1(0x20); // Leaf prefix
        for (uint256 i = 0; i < 64; i++) {
            path[i + 1] = nibbles[i];
        }

        // Encode value
        bytes memory encodedValue = Lib_RLPWriter.writeUint(uint256(value));

        // Encode leaf
        bytes[] memory leaf = new bytes[](2);
        leaf[0] = path;
        leaf[1] = encodedValue;
        proof[0] = Lib_RLPWriter.writeList(leaf);

        return proof;
    }

    function _generateAccountProof(bytes memory address_, bytes memory accountData)
        internal
        pure
        returns (bytes[] memory)
    {
        // Similar to the storage proof but with an account address
        bytes[] memory proof = new bytes[](1);

        // For Ethereum, account addresses are hashed before being used as keys
        bytes32 hashedAddress = keccak256(address_);

        // Convert hashed address to nibbles (half-bytes)
        bytes memory nibbles = new bytes(64); // 32 bytes * 2 nibbles per byte
        for (uint256 i = 0; i < 32; i++) {
            nibbles[i * 2] = bytes1(uint8(hashedAddress[i]) / 16);
            nibbles[i * 2 + 1] = bytes1(uint8(hashedAddress[i]) % 16);
        }

        // Encode path by adding a prefix
        bytes memory path = new bytes(65);
        path[0] = bytes1(0x20); // Leaf prefix
        for (uint256 i = 0; i < 64; i++) {
            path[i + 1] = nibbles[i];
        }

        // Encode leaf node
        bytes[] memory leaf = new bytes[](2);
        leaf[0] = path;
        leaf[1] = accountData;
        proof[0] = Lib_RLPWriter.writeList(leaf);

        return proof;
    }

    function setUp() public {
        broadcaster = new Broadcaster();
        parentToChildProver = new ParentToChildProver(address(outbox), rootSlot);

        childToParentProver = new ChildToParentProver();
    }

    function test_getTargetBlockHash() public {
        bytes32 targetBlockHash = bytes32(uint256(0x123456));

        bytes32 sendRoot = bytes32(uint256(0xa898d909));

        bytes memory input = abi.encode(sendRoot);

        vm.expectRevert(ParentToChildProver.TargetBlockHashNotFound.selector);
        parentToChildProver.getTargetBlockHash(input);

        outbox.updateSendRoot(sendRoot, targetBlockHash);

        bytes32 blockHash = parentToChildProver.getTargetBlockHash(input);

        assertEq(blockHash, targetBlockHash);
    }

    function test_verifyTargetBlockHash() public {
        bytes memory blockHeader = getMockBlockHeader();

        bytes32 blockHash = keccak256(blockHeader);

        bytes[] memory accountParts = new bytes[](4);
        accountParts[0] = Lib_RLPWriter.writeBytes(hex"00"); 
        accountParts[1] = Lib_RLPWriter.writeBytes(hex"00"); // balance
        // Storage root for the contract
        bytes32 contractStorageRoot = bytes32(uint256(0xdeadbeef));  
        accountParts[2] = Lib_RLPWriter.writeBytes(abi.encodePacked(contractStorageRoot)); // storageRoot
        accountParts[3] = Lib_RLPWriter.writeBytes(abi.encodePacked(address(outbox).codehash)); // codeHash

        bytes memory rlpEncodedAccountProof = Lib_RLPWriter.writeList(accountParts);

        bytes memory storageProof = hex"abcd";

        bytes[] memory accountProofs = _generateAccountProof(abi.encodePacked(address(outbox)), rlpEncodedAccountProof);

        bytes memory input = abi.encode(blockHeader, bytes32(uint256(0x123456)), accountProofs, storageProof);

        bytes32 targetBlockHash = parentToChildProver.verifyTargetBlockHash(blockHash, input);

        assertEq(targetBlockHash, bytes32(uint256(0x123456)));
    }
}
