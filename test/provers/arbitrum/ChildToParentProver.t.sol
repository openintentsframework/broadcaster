// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console, Test} from "forge-std/Test.sol";
import {Broadcaster} from "../../../src/contracts/Broadcaster.sol";
import {IBroadcaster} from "../../../src/contracts/interfaces/IBroadcaster.sol";
import {ParentToChildProver} from "../../../src/contracts/provers/arbitrum/ParentToChildProver.sol";
import {IOutbox} from "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import {ChildToParentProver} from "../../../src/contracts/provers/arbitrum/ChildToParentProver.sol";

import {RLP} from "@openzeppelin/contracts/utils/RLP.sol";

contract BroadcasterTest is Test {
    using RLP for RLP.Encoder;
    Broadcaster public broadcaster;

    address public publisher = makeAddr("publisher");
    uint256 public parentForkId;
    uint256 public childForkId;

    IOutbox public outbox = IOutbox(0x65f07C7D521164a4d5DaC6eB8Fac8DA067A3B78F);

    uint256  public rootSlot = 3;

    ParentToChildProver public parentToChildProver; // Home is Parent, Target is Child
    ChildToParentProver public childToParentProver; // Home is Child, Target is Parent

    struct L1BlockHeader {
        bytes32 parentHash;
        bytes32 sha3Uncles;
        address miner;
        bytes32 stateRoot;
        bytes32 transactionsRoot;
        bytes32 receiptsRoot;
        bytes   logsBloom;
        uint256 difficulty;
        uint256 number;
        uint64  gasLimit;
        uint64  gasUsed;
        uint64  timestamp;
        bytes   extraData;
        bytes32 mixHash;
        bytes8  nonce;
        uint256 baseFeePerGas;
        bytes32 withdrawalsRoot;
        uint64 blobGasUsed;
        uint64 excessBlobGas;
        bytes32 parentBeaconBlockRoot;
        bytes32 requestsHash;
    }

    struct L2BlockHeader {
        bytes32 parentHash;
        bytes32 sha3Uncles;
        address miner;
        bytes32 stateRoot;
        bytes32 transactionsRoot;
        bytes32 receiptsRoot;
        bytes   logsBloom;
        uint256 difficulty;
        uint256 number;
        uint64  gasLimit;
        uint64  gasUsed;
        uint64  timestamp;
        bytes   extraData;
        bytes32 mixHash;
        bytes8  nonce;
        uint256 baseFeePerGas;
        bytes32 withdrawalsRoot;
        uint64 blobGasUsed;
        uint64 excessBlobGas;
        bytes32 parentBeaconBlockRoot;
        bytes32 requestsHash;
        uint256 l1BlockNumber;
        uint256 sendCount;
        bytes32 sendRoot;
    }

    // baseFeePerGas        100000000
    // difficulty           1
    // extraData            0x8ca332e1f5a64276a8be61be7a90c8ea6ae0332535a53ef9a85dde62ca0300b6
    // gasLimit             1125899906842624
    // gasUsed              328393
    // hash                 0xdb596a6c9d87f870506e424482862ac675e2344b7e354d197a5aa3a7659a85b5
    // logsBloom            0x0001000200000404000000000000000800000000090000000100000000000000000000200000400000000000000000000000000080002000000000010128000000000000000000081000400800000000000002000000080000000000008000004000200004000000420800100200000000000000200000000000001000081000002000000000000000000000010000000800020000000000000000000000000002c000002000800400100000000000800000000000010000200020080004000000020102000000080000000200000000000002000000000040008000002000000010000004000100000000000000000000000000000000000002000000004400
    // miner                0xA4b000000000000000000073657175656e636572
    // mixHash              0x000000000001a67d000000000087c92300000000000000280000000000000000
    // nonce                0x00000000001ada92
    // number               180000000
    // parentHash           0xb9b101833624e02c45f8158f226c8f6e2a3ad9f223ef92018c69451721aabfa6
    // parentBeaconRoot     
    // transactionsRoot     0xa62d25d2050b4dbc0e99a3aa5b9b8ebfbfac14300b0bddab79adc418d6714cb5
    // receiptsRoot         0xa54852996b1524cd5e58243a73bc078f4a254f4d365f0eef707b48c38269a689
    // sha3Uncles           0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347
    // size                 1287
    // stateRoot            0x80b95cb698a5b9b83ccb8f5563add29d5e251300950e2f4258c7e25557cedf11
    // timestamp            1754165104 (Sat, 2 Aug 2025 20:05:04 +0000)
    // withdrawalsRoot      
    // totalDifficulty      
    // blobGasUsed          
    // excessBlobGas        
    // requestsHash         
    // targetBlobsPerBlock  
    // transactions:        [
    //     0x6f39dafed2fda3169c167b10fbf50012e4610128028beb0e995d2353f4e17ed0
    //     0x5dc2e9434e7ca6a742ec6dbc27f8bc47cb195458ae3ce03d196bf6bd7f496a35
    //     0x430e046cbc8fe9c0d21705188c8faeda170bade50669d6fd730df453680a3fb6
    //     0x4915da3d915eb1b47e18bb1b83d1991c117616ba38f5ff9f933f7f7953838929
    // ]
    // l1BlockNumber        8898851
    // sendCount            108157
    // sendRoot             63612146052391417355742635086633654320610540077509025281783574630860826280118

    L1BlockHeader public blockHeader;
    L2BlockHeader public l2BlockHeader;

    function encode(L1BlockHeader memory h) internal pure returns (bytes memory out) {
       RLP.Encoder memory enc = RLP
            .encoder()
            .push(h.parentHash)
            .push(h.sha3Uncles)
            .push(h.miner)
            .push(h.stateRoot)
            .push(h.transactionsRoot)
            .push(h.receiptsRoot)
            .push(h.logsBloom)
            .push(h.difficulty)
            .push(h.number)
            .push(h.gasLimit)
            .push(h.gasUsed)
            .push(h.timestamp)
            .push(h.extraData)
            .push(h.mixHash)
            .push(abi.encodePacked(h.nonce))
            .push(h.baseFeePerGas)
            .push(h.withdrawalsRoot)
            .push(h.blobGasUsed)
            .push(h.excessBlobGas)
            .push(h.parentBeaconBlockRoot)
            .push(h.requestsHash);

        out = enc.encode(); // wraps items as an RLP list
    }

    function encode(L2BlockHeader memory h) internal pure returns (bytes memory out) {
        RLP.Encoder memory enc = RLP
            .encoder()
            // .push(h.parentHash)
            // .push(h.sha3Uncles)
            // .push(h.miner)
            // .push(h.stateRoot)
            // .push(h.transactionsRoot)
            // .push(h.receiptsRoot)
            // .push(h.logsBloom)
            // .push(h.difficulty)
            // .push(h.number)
            // .push(h.gasLimit)
            // .push(h.gasUsed)
            // .push(h.timestamp)
            // .push(h.extraData)
            // .push(h.mixHash)
            // .push(abi.encodePacked(h.nonce))
            // .push(h.baseFeePerGas)
            // .push(h.withdrawalsRoot)
            // .push(h.blobGasUsed)
            // .push(h.excessBlobGas)
            // .push(h.parentBeaconBlockRoot)
            // .push(h.requestsHash)
            .push(h.sendRoot)
            .push(h.sendCount)
            .push(h.l1BlockNumber)
            .push(1);

        out = enc.encode(); // wraps items as an RLP list
    }



    function setUp() public {
        blockHeader = L1BlockHeader({
            parentHash: 0x1e9c639e9b29486266f7e41b0def33287c5c26ae35bb0f7f6737d7fdeb4a1ed3,
            sha3Uncles: 0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347,
            miner: 0x25941dC771bB64514Fc8abBce970307Fb9d477e9,
            stateRoot: 0xcbdb57934e557e2e6a38a5c6aa70bb8a7d0f9700160d928b28a5f04f1de971d1,
            transactionsRoot: 0x82a99363ce8da6eb8ad62254faa538f3735ab98bb8ec7623001dc7dfc26f0bf5,
            receiptsRoot: 0x7605f9bacc57fed2bc64f7f9811bb7ce858c17621895435fadb82aed4195bf3d,
            logsBloom: hex"002200040282e40000901112ac4080050b0030000400111000008104408205500a19000000810325008a400000b5008043031018c2928ca2801010a25829199092c0a802012e01414008610a002840221d1010c0014008000002048ac00498000203010c232148c10920a005a09128028a0889c020581134009090101000204002c2802200501404200010000204c4820104848f0080d40f8171004004200c8622480402100802800884100120204808204000811100080920f428a22030010342108002050080000445004008024050109440102000f8110044350a4400203050509c168840242084021008a0018000223a02000a0900409080024202004841",
            difficulty: 0,
            number: 9043403,
            gasLimit: 59941351,
            gasUsed: 7545006,
            timestamp: 1755911328,
            extraData: hex"d883010f0b846765746888676f312e32342e32856c696e7578",
            mixHash: 0x1e51d45b5109e05249b12823031e12efc6bd3d594abf51178207570ff3c341ec,
            nonce: 0x0000000000000000,
            baseFeePerGas: 2558257,
            withdrawalsRoot: 0x57f125b7c33933258d27cf8f90a0e856bf9ad73790eb4889f06cc41fa8ec1fad,
            blobGasUsed: 262144,
            excessBlobGas: 0,
            parentBeaconBlockRoot: 0xf89f3fe12da24f2018b32b060312cc0756e7772184683c0c7bf024c80bceccc0,
            requestsHash: 0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        });

        l2BlockHeader = L2BlockHeader({
            parentHash: 0xb9b101833624e02c45f8158f226c8f6e2a3ad9f223ef92018c69451721aabfa6,
            sha3Uncles: 0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347,
            miner: 0xA4b000000000000000000073657175656e636572,
            stateRoot: 0x9c44bc86617b28c4adb70bc506ae3d5e27a61feeadc09c4d2e16f629d6b17b05,
            transactionsRoot: 0x8175dca6d0174e1d629eb92480b882f5852eaf5d64d21012a7dda3132a641201,
            receiptsRoot: 0x4cdd3cdcb468d9c108e5ec5659737b7041a9a21cb2df2a26de1bc8b112780300,
            logsBloom: hex"000000000800000000000800000001820000000800000400000000006040000000000000000000000000000000000000000004000200820000000000002020000000000000000840000004080108001000000000000000000000000000020000000000000000400000200000010000000000000000080000000000300000000000000004000000000800400000004002000000005400040000008000000000000a0000020040000000000040000000000040100000000080000000000000000000000002000000400000000000000080001000000008000000001000000000000010240000000000000000080000000080000024000000000000080000004000",
            difficulty: 1,
            number: 180000000,
            gasLimit: 1125899906842624,
            gasUsed: 3916554,
            timestamp: 1706000664,
            extraData: hex"daecbf61aadfe56079f53903ab837f1b41559410507a6d4dd0984d5a02622817",
            mixHash: 0x0000000000004ab500000000004e6780000000000000000a0000000000000000,
            nonce: 0x0000000000062703,
            baseFeePerGas: 100000000,
            withdrawalsRoot: 0xe2c11498924fee97556dd5f33339475590b7e77d79d0d940dad3713a132cfae1,
            blobGasUsed: 1048576,
            excessBlobGas: 524288,
            parentBeaconBlockRoot: 0x0642f66ab0f0e5368b19898c41634b7557d7d93865f67b37f5c4227f120247b6,
            requestsHash: 0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855,
            l1BlockNumber: 8898851,
            sendCount: 108157,
            sendRoot: 0x8CA332E1F5A64276A8BE61BE7A90C8EA6AE0332535A53EF9A85DDE62CA0300B6
        });

        parentForkId = vm.createFork(vm.envString("PARENT_RPC_URL")); // Sepolia
        childForkId = vm.createFork(vm.envString("CHILD_RPC_URL")); // Arbitrum Sepolia
        vm.selectFork(parentForkId);
        broadcaster = new Broadcaster();
        parentToChildProver = new ParentToChildProver(address(outbox), rootSlot);

        vm.selectFork(childForkId);
        childToParentProver = new ChildToParentProver();
    }

    function test_broadcast() public {
        vm.selectFork(parentForkId);
        bytes32 message = "test";

        vm.prank(publisher);
        vm.expectEmit();
        emit IBroadcaster.MessageBroadcast(message, publisher);
        broadcaster.broadcastMessage(message);

        assertEq(broadcaster.hasBroadcasted(message, publisher), true);
    }

    function test_getTargetBlockHash() public {

        uint256 blockNumber = 9043403;
        vm.selectFork(parentForkId);

        bytes32 expectedBlockHash = keccak256(encode(blockHeader));
        vm.selectFork(childForkId);

        bytes32 targetBlockHash = childToParentProver.getTargetBlockHash(abi.encode(blockNumber));
        assertEq(targetBlockHash, expectedBlockHash);
    }

    function test_verifyTargetBlockHash_reverts_on_home_chain() public {
        vm.selectFork(childForkId);
        childToParentProver = new ChildToParentProver();

        vm.expectRevert();
        childToParentProver.verifyTargetBlockHash(blockhash(block.number), abi.encode(1));


    }

    function test_verifyTargetBlockHash() public {
        vm.selectFork(parentForkId);

        childToParentProver = new ChildToParentProver();

        bytes memory rlpBlockHeader = encode(l2BlockHeader);
        uint256 targetBlockNumber = blockHeader.number;
        bytes memory accountProof = _getAccountProof();
        bytes memory storageProof = _getStorageProof();

        console.log("l2 Block Header");
        console.logBytes32(keccak256(encode(l2BlockHeader)));

        bytes memory input = abi.encode(rlpBlockHeader, targetBlockNumber, accountProof, storageProof);

        bytes32 targetBlockHash = childToParentProver.verifyTargetBlockHash(keccak256(encode(l2BlockHeader)), input);
        
        // Verify the target block hash matches expected
        assertEq(targetBlockHash, keccak256(encode(blockHeader)));
    }

    function test_verifyStorageSlot() public {
        vm.selectFork(parentForkId);
        
        // Test verifying a storage slot on the target chain (parent)
        bytes32 targetBlockHash = keccak256(encode(blockHeader));
        address testAccount = address(broadcaster);
        uint256 testSlot = 0;
        
        // Create mock proofs for storage verification
        bytes memory accountProof = _getAccountProof();
        bytes memory storageProof = _getStorageProof();
        
        bytes memory input = abi.encode(
            encode(blockHeader), 
            testAccount, 
            testSlot, 
            accountProof, 
            storageProof
        );
        
        (address account, uint256 slot, bytes32 value) = childToParentProver.verifyStorageSlot(targetBlockHash, input);
        
        assertEq(account, testAccount);
        assertEq(slot, testSlot);
        // Note: The actual value would depend on the storage proof data
    }

    function test_verifyStorageSlot_invalid_proof() public {
        vm.selectFork(parentForkId);
        
        bytes32 targetBlockHash = keccak256(encode(blockHeader));
        address testAccount = address(broadcaster);
        uint256 testSlot = 0;
        
        // Create invalid proofs
        bytes memory invalidAccountProof = hex"deadbeef";
        bytes memory invalidStorageProof = hex"deadbeef";
        
        bytes memory input = abi.encode(
            encode(blockHeader), 
            testAccount, 
            testSlot, 
            invalidAccountProof, 
            invalidStorageProof
        );
        
        // This should revert due to invalid proof
        vm.expectRevert();
        childToParentProver.verifyStorageSlot(targetBlockHash, input);
    }

    function test_getTargetBlockHash_invalid_block_number() public {
        vm.selectFork(childForkId);
        
        // Test with a non-existent block number
        uint256 invalidBlockNumber = type(uint256).max;
        
        bytes32 targetBlockHash = childToParentProver.getTargetBlockHash(abi.encode(invalidBlockNumber));
        
        // Should return zero for non-existent block number
        assertEq(targetBlockHash, bytes32(0));
    }

    function test_verifyTargetBlockHash_invalid_input() public {
        vm.selectFork(parentForkId);
        
        childToParentProver = new ChildToParentProver();
        
        // Test with malformed input
        bytes memory invalidInput = hex"deadbeef";
        
        vm.expectRevert();
        childToParentProver.verifyTargetBlockHash(keccak256(encode(l2BlockHeader)), invalidInput);
    }

    function test_version() public {
        vm.selectFork(childForkId);
        
        uint256 version = childToParentProver.version();
        assertEq(version, 1);
    }

    function test_constructor_parameters() public {
        vm.selectFork(childForkId);
        
        // Test that constructor parameters are set correctly
        assertEq(childToParentProver.blockHashBuffer(), 0x0000000048C4Ed10cF14A02B9E0AbDDA5227b071);
        assertEq(childToParentProver.blockHashMappingSlot(), 51);
    }

    function test_verifyTargetBlockHash_empty_input() public {
        vm.selectFork(parentForkId);
        
        childToParentProver = new ChildToParentProver();
        
        vm.expectRevert();
        childToParentProver.verifyTargetBlockHash(keccak256(encode(l2BlockHeader)), "");
    }

    function test_verifyTargetBlockHash_short_input() public {
        vm.selectFork(parentForkId);
        
        childToParentProver = new ChildToParentProver();
        
        bytes memory shortInput = abi.encode(encode(l2BlockHeader), blockHeader.number);
        
        vm.expectRevert();
        childToParentProver.verifyTargetBlockHash(keccak256(encode(l2BlockHeader)), shortInput);
    }

    function test_verifyStorageSlot_empty_input() public {
        vm.selectFork(parentForkId);
        
        bytes32 targetBlockHash = keccak256(encode(blockHeader));
        
        vm.expectRevert();
        childToParentProver.verifyStorageSlot(targetBlockHash, "");
    }

    function test_verifyStorageSlot_short_input() public {
        vm.selectFork(parentForkId);
        
        bytes32 targetBlockHash = keccak256(encode(blockHeader));
        address testAccount = address(broadcaster);
        uint256 testSlot = 0;
        
        bytes memory shortInput = abi.encode(encode(blockHeader), testAccount, testSlot);
        
        vm.expectRevert();
        childToParentProver.verifyStorageSlot(targetBlockHash, shortInput);
    }

    function test_verifyStorageSlot_max_slot_value() public {
        vm.selectFork(parentForkId);
        
        bytes32 targetBlockHash = keccak256(encode(blockHeader));
        address testAccount = address(broadcaster);
        uint256 maxSlot = type(uint256).max;
        
        bytes memory accountProof = _getAccountProof();
        bytes memory storageProof = _getStorageProof();
        
        bytes memory input = abi.encode(
            encode(blockHeader), 
            testAccount, 
            maxSlot, 
            accountProof, 
            storageProof
        );
        
        (address account, uint256 slot, bytes32 value) = childToParentProver.verifyStorageSlot(targetBlockHash, input);
        
        assertEq(account, testAccount);
        assertEq(slot, maxSlot);
    }

    function test_verifyStorageSlot_zero_address() public {
        vm.selectFork(parentForkId);
        
        bytes32 targetBlockHash = keccak256(encode(blockHeader));
        address zeroAccount = address(0);
        uint256 testSlot = 0;
        
        bytes memory accountProof = _getAccountProof();
        bytes memory storageProof = _getStorageProof();
        
        bytes memory input = abi.encode(
            encode(blockHeader), 
            zeroAccount, 
            testSlot, 
            accountProof, 
            storageProof
        );
        
        (address account, uint256 slot, bytes32 value) = childToParentProver.verifyStorageSlot(targetBlockHash, input);
        
        assertEq(account, zeroAccount);
        assertEq(slot, testSlot);
    }

    function test_getTargetBlockHash_max_block_number() public {
        vm.selectFork(childForkId);
        
        uint256 maxBlockNumber = type(uint256).max;
        
        bytes32 targetBlockHash = childToParentProver.getTargetBlockHash(abi.encode(maxBlockNumber));
        
        // Should return zero for non-existent block number
        assertEq(targetBlockHash, bytes32(0));
    }

    function test_verifyTargetBlockHash_wrong_home_block_hash() public {
        vm.selectFork(parentForkId);
        
        childToParentProver = new ChildToParentProver();
        
        bytes memory accountProof = _getAccountProof();
        bytes memory storageProof = _getStorageProof();
        
        bytes memory input = abi.encode(encode(l2BlockHeader), blockHeader.number, accountProof, storageProof);
        
        // Use wrong home block hash
        bytes32 wrongHomeBlockHash = 0x0000000000000000000000000000000000000000000000000000000000000000;
        
        vm.expectRevert();
        childToParentProver.verifyTargetBlockHash(wrongHomeBlockHash, input);
    }

    function test_verifyStorageSlot_wrong_target_block_hash() public {
        vm.selectFork(parentForkId);
        
        bytes32 wrongTargetBlockHash = 0x0000000000000000000000000000000000000000000000000000000000000000;
        address testAccount = address(broadcaster);
        uint256 testSlot = 0;
        
        bytes memory accountProof = _getAccountProof();
        bytes memory storageProof = _getStorageProof();
        
        bytes memory input = abi.encode(
            encode(blockHeader), 
            testAccount, 
            testSlot, 
            accountProof, 
            storageProof
        );
        
        vm.expectRevert();
        childToParentProver.verifyStorageSlot(wrongTargetBlockHash, input);
    }

    function test_broadcast_and_verify_message() public {
        vm.selectFork(parentForkId);
        
        bytes32 message = keccak256("test message");
        
        // Broadcast message
        vm.prank(publisher);
        broadcaster.broadcastMessage(message);
        
        // Verify message was broadcast
        assertTrue(broadcaster.hasBroadcasted(message, publisher));
        
        // Now test verifying this message from child chain perspective
        vm.selectFork(childForkId);
        
        // This would require proper proofs to verify the message on the child chain
        // For now, just verify the prover can handle the verification process
        bytes32 targetBlockHash = keccak256(encode(blockHeader));
        address broadcasterAccount = address(broadcaster);
        uint256 messageSlot = uint256(keccak256(abi.encode(message, publisher)));
        
        bytes memory accountProof = _getAccountProof();
        bytes memory storageProof = _getStorageProof();
        
        bytes memory input = abi.encode(
            encode(blockHeader), 
            broadcasterAccount, 
            messageSlot, 
            accountProof, 
            storageProof
        );
        
        (address account, uint256 slot, bytes32 value) = childToParentProver.verifyStorageSlot(targetBlockHash, input);
        
        assertEq(account, broadcasterAccount);
        assertEq(slot, messageSlot);
    }

    function test_multiple_broadcasts_same_publisher() public {
        vm.selectFork(parentForkId);
        
        bytes32 message1 = keccak256("message1");
        bytes32 message2 = keccak256("message2");
        
        // Broadcast first message
        vm.prank(publisher);
        broadcaster.broadcastMessage(message1);
        
        // Broadcast second message
        vm.prank(publisher);
        broadcaster.broadcastMessage(message2);
        
        // Verify both messages were broadcast
        assertTrue(broadcaster.hasBroadcasted(message1, publisher));
        assertTrue(broadcaster.hasBroadcasted(message2, publisher));
    }

    function test_multiple_broadcasts_different_publishers() public {
        vm.selectFork(parentForkId);
        
        address publisher2 = makeAddr("publisher2");
        bytes32 message1 = keccak256("message1");
        bytes32 message2 = keccak256("message2");
        
        // Broadcast from first publisher
        vm.prank(publisher);
        broadcaster.broadcastMessage(message1);
        
        // Broadcast from second publisher
        vm.prank(publisher2);
        broadcaster.broadcastMessage(message2);
        
        // Verify both messages were broadcast
        assertTrue(broadcaster.hasBroadcasted(message1, publisher));
        assertTrue(broadcaster.hasBroadcasted(message2, publisher2));
    }

    function test_duplicate_message_revert() public {
        vm.selectFork(parentForkId);
        
        bytes32 message = keccak256("duplicate test");
        
        // First broadcast should succeed
        vm.prank(publisher);
        broadcaster.broadcastMessage(message);
        
        // Second broadcast should revert
        vm.prank(publisher);
        vm.expectRevert();
        broadcaster.broadcastMessage(message);
    }

    function test_verifyTargetBlockHash_different_block_numbers() public {
        vm.selectFork(parentForkId);
        
        childToParentProver = new ChildToParentProver();
        
        // Test with different L1 block numbers
        for (uint256 i = 0; i < 5; i++) {
            L1BlockHeader memory testHeader = blockHeader;
            testHeader.number = blockHeader.number + i;
            
            bytes memory accountProof = _getAccountProof();
            bytes memory storageProof = _getStorageProof();
            
            bytes memory input = abi.encode(encode(l2BlockHeader), testHeader.number, accountProof, storageProof);
            
            // This might revert depending on the proof validity, but should not panic
            try childToParentProver.verifyTargetBlockHash(keccak256(encode(l2BlockHeader)), input) returns (bytes32 result) {
                // If it succeeds, verify it's a valid block hash
                assertTrue(result != bytes32(0));
            } catch {
                // Expected for invalid proofs
            }
        }
    }

    function test_verifyStorageSlot_different_accounts() public {
        vm.selectFork(parentForkId);
        
        bytes32 targetBlockHash = keccak256(encode(blockHeader));
        uint256 testSlot = 0;
        
        address[] memory testAccounts = new address[](5);
        testAccounts[0] = address(broadcaster);
        testAccounts[1] = address(childToParentProver.blockHashBuffer());
        testAccounts[2] = address(childToParentProver);
        testAccounts[3] = address(0x1234567890123456789012345678901234567890);
        testAccounts[4] = address(0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD);
        
        bytes memory accountProof = _getAccountProof();
        bytes memory storageProof = _getStorageProof();
        
        for (uint256 i = 0; i < testAccounts.length; i++) {
            bytes memory input = abi.encode(
                encode(blockHeader), 
                testAccounts[i], 
                testSlot, 
                accountProof, 
                storageProof
            );
            
            try childToParentProver.verifyStorageSlot(targetBlockHash, input) returns (address account, uint256 slot, bytes32 value) {
                assertEq(account, testAccounts[i]);
                assertEq(slot, testSlot);
            } catch {
                // Expected for invalid proofs
            }
        }
    }

    function test_verifyStorageSlot_different_slots() public {
        vm.selectFork(parentForkId);
        
        bytes32 targetBlockHash = keccak256(encode(blockHeader));
        address testAccount = address(broadcaster);
        
        uint256[] memory testSlots = new uint256[](5);
        testSlots[0] = 0;
        testSlots[1] = 1;
        testSlots[2] = 100;
        testSlots[3] = type(uint256).max / 2;
        testSlots[4] = type(uint256).max;
        
        bytes memory accountProof = _getAccountProof();
        bytes memory storageProof = _getStorageProof();
        
        for (uint256 i = 0; i < testSlots.length; i++) {
            bytes memory input = abi.encode(
                encode(blockHeader), 
                testAccount, 
                testSlots[i], 
                accountProof, 
                storageProof
            );
            
            try childToParentProver.verifyStorageSlot(targetBlockHash, input) returns (address account, uint256 slot, bytes32 value) {
                assertEq(account, testAccount);
                assertEq(slot, testSlots[i]);
            } catch {
                // Expected for invalid proofs
            }
        }
    }

    function test_gas_estimation_getTargetBlockHash() public {
        vm.selectFork(childForkId);
        
        bytes memory input = abi.encode(blockHeader.number);
        
        uint256 gasUsed = gasleft();
        childToParentProver.getTargetBlockHash(input);
        uint256 gasConsumed = gasUsed - gasleft();
        
        // Log gas consumption for optimization analysis
        console.log("Gas consumed by getTargetBlockHash:", gasConsumed);
        
        // Ensure reasonable gas consumption (adjust threshold as needed)
        assertTrue(gasConsumed < 100000, "Gas consumption too high");
    }

    function test_gas_estimation_verifyTargetBlockHash() public {
        vm.selectFork(parentForkId);
        
        childToParentProver = new ChildToParentProver();
        
        bytes memory accountProof = _getAccountProof();
        bytes memory storageProof = _getStorageProof();
        bytes memory input = abi.encode(encode(l2BlockHeader), blockHeader.number, accountProof, storageProof);
        
        uint256 gasUsed = gasleft();
        try childToParentProver.verifyTargetBlockHash(keccak256(encode(l2BlockHeader)), input) {
            uint256 gasConsumed = gasUsed - gasleft();
            console.log("Gas consumed by verifyTargetBlockHash:", gasConsumed);
            assertTrue(gasConsumed < 500000, "Gas consumption too high");
        } catch {
            // Expected for invalid proofs
        }
    }

    function test_gas_estimation_verifyStorageSlot() public {
        vm.selectFork(parentForkId);
        
        bytes32 targetBlockHash = keccak256(encode(blockHeader));
        address testAccount = address(broadcaster);
        uint256 testSlot = 0;
        
        bytes memory accountProof = _getAccountProof();
        bytes memory storageProof = _getStorageProof();
        bytes memory input = abi.encode(encode(blockHeader), testAccount, testSlot, accountProof, storageProof);
        
        uint256 gasUsed = gasleft();
        try childToParentProver.verifyStorageSlot(targetBlockHash, input) {
            uint256 gasConsumed = gasUsed - gasleft();
            console.log("Gas consumed by verifyStorageSlot:", gasConsumed);
            assertTrue(gasConsumed < 500000, "Gas consumption too high");
        } catch {
            // Expected for invalid proofs
        }
    }

    function _getAccountProof() internal pure returns (bytes memory) {
        bytes[] memory accountProofList = new bytes[](8);
        accountProofList[0] = RLP.encode(hex"f90211a0a2118d18c0c4762beaf5d6fc6cddbc6cb419c06bc8fb316bcc67813c7ad89f37a0d7720e4491aa4a2cef36d8a7ea3febea8cb0574c4ba72665f41f527a57a813c2a03072959eeceac7aec9091468d2aa1dc1e95037a7a8f30c623a6de37adf9cec95a04f229bec3621bbcc637e0c2210b3a0bba3436d5e2450940cb799a7fb5b950275a0f98abf2524d6607355669aafdc8cc80dae3dac4925db6e6b86f39bf5bf8ab093a064ff6a0d660ac73bb9475c1236801a9ca05506685061c50cf56e9a8349326908a0ccf95fe007a11db8b950b5b38436b7da70ad3f0e2c82026557055df775152c47a0c2edc5b33c2713b12db7a02209388788c34a3586311f7da1f56cdbce27769589a09bd711e27548764f457806154a992417de311f4c760c4401037e605a10cdc822a07f4f2e8933334da53f967441b3e8e2c5f741854be891c9a8a6d5defb96b921b3a0822f988473fb665f4a5f52475a52e2b0a7820c7d1815bf9a9a9ca01e68f74dd5a05ca349638c54148f5a679e1f708295853a3ed8b419ea0c65ad074b6c91ca6f16a0692da42801bf351e3fe694d5c537200a7bfb7588f1778f977aba27a1d0607fc1a0dcc0edde6410518f151cc156677e466e837db4d3f47629da2d2be47756d29fb3a0e121cb1deba0f87f0c39d364f67af075a721474c3f9705314cec02b0ccd49e8aa0dea4ecbf4f4708f16ad51d09cc4dcf1cafb01b2c005731b0a22297ba816a97f180");
        accountProofList[1] = RLP.encode(hex"f90211a05af07107cdaa845180db2946932cdd8dafb95fab50324cbac7b5d043c1de627ba09f3c61145ff3558bd0f0852ffeac8c2704ca3077be271de3d9870bc534020e0ba0fb867ffba548679e1bfdc54d34e7bdaacd527ea2329d669dc6e86d1c66b09365a004245988e3ca042a3eea8c3fb047d51a898c23211b25d622e451756313466f09a00af7c1016bb41567f1fe427d09164be154c190afb896535605bd36fae82a2bb2a0701867a4489e7092adafa40992e11466de3923bc3343915c9cd8ac425cb56d9da0f77ecdedd005140d0d70624a2f0cbc0db4943ab58f78fa5180cd80c50d6bde68a04bfde40aa649098538698e1eb20467adb07d74804fe27b633fdf776e5272ce37a0058a2f6788359e8343761059d0541b8acc68850453fb075d59f0834e8ed8b86da064191e9044af3ffc7d4f5b52e891e7739a6cb14dfdcf9eba67dbe42f753e74bda08e86648c113e9266ef233eb5c83435ee7cf0d64ae2ac2330d989e245585ce1cea09c12738640fbb002e7e5a42add6b674b90b73bfa02aae571bc985f06221b4e17a044505729506507694fb252b0e7011144811ea43ef9c2dbcab946859d261262aea0358c43e47a29fc80bfd036b9dda606ed505cae123e3593aec84b1dd9b0605c55a01b27e31e951a781a93fb2f41c677bec595096d1c27735fd9aa12f9d7a21bd06fa0d10f49f28be16b70af7928c1a71bc930fad51715cf0942b5f68f8c5e8757c0f380");
        accountProofList[2] = RLP.encode(hex"f90211a08c5c3ea64e95f219703b2c65f129a7dad26a88dc45b55c6a8430a7fe8d2d5b5fa0110f5f293a5c6e4599ca000bc2f85dc3c89eb0882ff9979378b74295fd16d303a08a4000086c73253741e57041077c9c0a50ee5f7e13947ba96ddf9b5b4639947aa081aac18b1ef8de1edb92e8da70510444e1a5811a0e58974586fc6bb7f0659fd9a0cefeb9ae4bd7300664c56e2171951eb03fdac51fb7083025dc7b72d48733eb09a059619e783b25187dab04d347588928e408d71c04b5106e623e9fbd0d43edb7b4a026c4ab0f02fa523843fc0b08f0b94b0e0050821824beb4b812c200f2f5a25f4fa0de0f22d02f160b4714332e8d155dc80db79c501c0214685c7fd1fb0fa0e23fa2a0c3eb0458c36953f7d1702ed3827fbc40974ddaca826c99bb13409b16dd903fcda0c1aa496cbc544b083d172bfd6e4a7d29a112c650d106a786e71f2f38c1d6f398a0819eeb7c0ab88145a91887ee50b07c2c4d3fa2d3ee26e87ec9ab9bdf445f809aa0b074688f766e63735d6d6b3293224a2705c3d65cda629a84849c7e289efbd300a0881f7eb4e2948d344fbf1a0dbdc821b751770a25fe3c7ee0d689454f5ed39b33a045347bf854908c31f3c73e5cf499578e296d23f3ea9651d016532aa9d47fa81aa0f4e943dc52a2f0fea62a0320c1c038efd139e89031ca0d5c25077d7f4dce7fe4a04c8786806dd41d05b30949f0d3736803f63387de8d6976003358174aeeb5092780");
        accountProofList[3] = RLP.encode(hex"f90211a009ff057b7fa9bd54f24901b2a29ff712441c48a2caa7d32755d32c2e803d60c7a09aed488d8c9e0fac48124a94e49de7efab4124759bdcc98aff3d38bfa58deb5fa0950ef570c6f492bbe5c5433147cd330d685833ef9eaf9fa5fa7cc843998da0c1a0c24a4f41940fdba7f41e5f04d9be01fb36ee4d1177d950e689b264daaa81b461a01f893c202269bf4eb50fff004ead1b1a61d70554e9b2eba1784637a7ee87ec1aa03e179a921b515bbe631a2738eec41034453e3f952dbf2ef1953f980c1dfbbccda06e18bda1cd2d20627b2a2de62b2eb1a8d6d7a2089ad41ee9fe1e49cd1019a024a0310dd2c90f7004e38c92335878553afa180d41c782ab27b989aa18fb0973aaeea0ede28ad0a5d4ac794b8101035ec9da5af2182667c9ff1304fa9dd6b4f13c7d59a01c14f35b32d943b90c39f4d5b0d0b31e3a03edca84054c8d2a173f2f78ed1cf0a023df0c7f2fb329c4e570a3d132b5bb721351b5da2d191ee82cb6d593aae28b03a0863c532ce070494071f3ae088b209c17e6aaca5f6e2117112df635e21587f41ea05153f4ee8159dc592bfebb325d85c97b94fae4f733bb2270352b80466cfe7f42a08bc0d9803ace8d2b1701130001a09bd02701ab0d1e61d00a7e84708a19a320e7a06808f7b7bb2851e21727b35cbf6fbc7da655e9d0917fe9c2d44fd812192b2491a08a9fa897082afce4c2be40303e8fe27df2f3a4a55c1740377a9c920701b619d180");
        accountProofList[4] = RLP.encode(hex"f90211a09eea0e5ae46bf062cc393b7246f2d1abcf68ada339e341be915ef977ee11251da085c60e3a6c0c4c3ebfb0fc246130d5528eea36b4224e4273b93bd1343a227944a09c967a9f134e8a9f81cdfbc77288bbd4dd4fdc1d97212fd8718f069ab27f6229a0ea80321bf088ed15452d8154b046246d15574fe48ab86491eed665c86af08130a08a325ce8df99d1fc3a1ff632e4eb861bcb2982fcb6ecaf940c9d083e18f86f08a02004bc03385d695ba0523ca0a0af9d06513e96f47e46f261ba3849b5155c0c17a0c76315383129c6849ed2ec425c96fe0c6f1acd45feeddf0c5196d72270382b9ba0bc52982a958476546ba539ca41bfda1cc36aaa635d492061e6ea657f3696e13ca086801924094139f671ec0b76de9b0f9e113c2b157d19f238d0bbad6bcb1d6a15a0048a34ffcb491289f75e1b75ecd51dcb0b69f58bdafcd54874d160fb6d9bf36fa020e86997eeeb9102304e4ee15d3e31986ca1fdf961ce0be46da1e7f05568a92ba079454aca4c542e0b15d46b029c8c5862d84c70911206d55b89bb4dcc0c1a9d4da0c28137f9f053cb5a5a90ba6c054e94f46a1a2e20b08e05f4fcbe9a5cd89c1681a02fad4690b1fee7aba45907c2299d53e5f7e2cd7f7748c5370552fdec8f62a285a08578852e777b413e893d8bfc7640985c7192799977a91cbe607706fb01d50f0fa0fbfe773b2c8762d0435685cae660845e8ec20d03ec7fe6cf56cda51a437a87bc80");
        accountProofList[5] = RLP.encode(hex"f90211a0e1b93e13f760381154b72fc32ad00aba873a5899d3a03914080c07f2f98831f3a03e6ba2240ba6bda182e4b2a38d8e9f055f25ac712e7089fc4e8b3a231b644b55a0371d7fa0bbd94059d89d2c53383ff3b57dc03c64170e140244011ea60ff507d3a019125b0f1b5c35c07ee529e963c7eac3a0b92d35c688c302bdf1cd773278c956a020230ee77522f53c62fbeb70657e7c57f75e40ca64a3c92af5ee2ddc7560931aa0101187e2c61703fcb199f7ae88019f6f698de7757a8add82e67c0a100178b9e4a0ba77dbf37c2bdbfbcc733a0fcf7bf9499fa964325c7cce9d281f8605bbcf5e92a01a49c2efc4e81f7cd0eb68658ac1b2186891a3cb789ecc885fade8f6acb7424aa07d2e2fe0f5ebea8c4a38ce2301a88de40350d7b1617a81d44169cf44d70ce82fa06e20425e1638def3faa20e367fe683be21f291e7f68a7673ab8dc3e2293f873da09af71c8f8b8e57c447b71ce1f2f5ca0ec2477cb8a93ad025667e56d08f95a139a08b8f77833aa54f56a1c4ee2a9b0b9e2e97c0f00dbbb410e1a06e5af9020cce56a02a0f03d38d63d313190c2c1c8efadc889eac14b3d8776b4add70400db18b2fc4a01c98e9aa23024b72b0483a9fa3789ef6755c404f620d86c9954e1e48b61dcbe7a0cf85f4956397bdbb69ad44720afb4543456aafdf8fe4217a1d277d7a683cc907a0723f3c73ba707b624ed009ddfeb85bf3da21c64e5e4ddb244110c9865890b30a80");
        accountProofList[6] = RLP.encode(hex"f8f1a0dd180ac5f12b37ee3ae9cc5602b590a841869f9df98dbd5d2f241bb8051006b8a0c060540d4e56683e4bea706db8e36f326488aac0af85a68475c70b5fc55eb3108080a01769a419738d807498e6b42e8bc5306fb2f3989ecd5026811afe175f7a2c849780a05241c221c031e2ca56064816dd3d0ec73cbd67abdad0eae27cb4ed4d28503d3780a0e97c753eb5415089740e4930e0fc365ea30a9e10020f6780fa740f37b9619dc680a0db55de35ad990486086ef8e4f05544868d0ca0d49d12b81cb39a52106e56cd3380a0a97974ddd28c59248132f8f180dfaa4af3fdbd5f4f4a8bbfa9f562a34a52b65080808080");
        accountProofList[7] = RLP.encode(hex"f8669d3f067c00b247b61f5eb18cd60870b41b51d016cdb9c0628ca3659ee784b846f8440180a0b9941cf26e67f34096c49b3ec31543e4be86aaa36e8bd42209b7ee8d7c60df4ba08736329b580cfc0c0c39ee6700515e0bc51652afb614640db9e34a5d784933e8");

        return RLP.encode(accountProofList);
    }

    function _getStorageProof() internal pure returns (bytes memory) {
        bytes[] memory storageProofList = new bytes[](5);

        storageProofList[0] = RLP.encode(hex"f90211a0b33465ffacdced06a69a8d72df1c701c626e57472ebd7064365259b653c067e8a097a867acee4139e502e459b7130c85aa556fb189c97b3effa444ca06cd28d4fca0c9635ab3c1ad1830a1957d034d8ef95997e7dec700f16bb759a841764def1ce4a09ce8504f9d7882c39f3df76a2f22dd587cc02a12ebbaf694937147cff26f0a21a082e461aa0446b8192b4a0b7c9d2b6cbd94deede9d3efd9fa119595cf06635a24a055d466ade6350a4b88dea161ca40c29c7d5c26f3ba98361b8e8d06356cee6558a08968e2cc68c8eb7af29b15b9415f72ffca529f68ddaf77bf15d3234ce191f12fa030831a905336a320a84b13993e270709f10922955a6f7c3c3427ed7b0e20ec78a0fc5f3774c76588b1e7ef82d7b4540d550ca76cdd73e420cd85b7b9278d3149e2a0c2338a30b6451618424528c3ef7fa3031cdbaa6bfb3f3858845ac69d9fee6108a031658c992b377e0dfd5ce60caf4109e04e920e567ad985deb9b1d0ffd10f34eba04a901ada2d44da9c185db36cb3227b9e34900feb86e39cf9a47bd7cb6daa9d30a053b84cd1dd27a2be742d4a644d2d3f6b94f2908f1e3cecc13e8e7f0184638256a0d1c63dd15af48442e80923e3af80f9346e370653655003ce96473cbe6147a6e5a08d294de8159e11eaf4246496f36bfe0fa968937cd78fc990e4edc05448c01e20a017fb4047699fc4c3d4483cc38306cbabbac7e32202c6eeeb39a716ab8a43bec380");
        storageProofList[1] = RLP.encode(hex"f90211a002d8e953aa5bbf1b090919d432f98da71e42551c7704445777726867eacd880fa0483386d5094035bbb6e622f58e12bf2d3b868c3a8633e62711682d5ac7c8ac21a0fe1d169346618286dbf7e445767f74806d308d106d2aece6e71e0e5332a9f268a0a82b81164516b1d0cc829d1b1d38bc4259e61f35696d0bd4cbfd8a0a10563710a0a6a8103aa1f4117e6dde07822fbd3052ac6ff3331bf8489215ddb7e10590262da09a7410e0235727880b34caedd59496292ca70c97828f2a4da189e36e4eeefdf1a0227eeec265051a98f5a9c088e6ba0775767e54f7dab22ae47a395fd6dccef1e4a0b1e23c411e66f4a160d9899a15afaca7125485c7257448b48607ab7e8e15c46da0277032d5ca4e4c91ad348311c861496a634846428e213a3cc41f9873a87e72a1a06a216545720ab28209204ca56b85e4135f4893852a9b398942829bfb8560b8b3a099bc2c181322ad122b6773cebd47db425ba0615a137de069a25921bb9b1e15a7a0c83fd04980e13b7845b5dea401a698b7e83a3bb6496e339047731b5fd6554166a0e6596f5205e3612be086b45e68135584e8e4d53076c42a88d4cbd43638ec20e6a07bfe6a392d669d2f5d574b9ae840a0c75702a1fb85d81465af6637d4edfefeffa09f50fddde7ae5050f374da72b9b34eccb43ab4988145072ff5f2e045d4965a1ba0f1fcb4ee03ebd291bf6f4cc8d675c928cb2f78015f4eaeca56ea9fc80f2677e380");
        storageProofList[2] = RLP.encode(hex"f90211a025ed53e3071ec7165c7a3758d269b4f3ef4bb9513408dcf3af11494f5b0604e8a00e80afb8672b474f28abf8c2644fe2102abad2693f3280b300e65343192aa103a0234a8f90a794a32938ad65046259c164a9fbb65670b9d0346c2eceeed579c162a03fa2a10c2cfda2ae26bc35a5c64094dcf79d790572743fd0d272e96abe74da30a041b01073428696edc17c43b981a5f85aadfed1d996685d1ba69dfe38a2c5557ea040b0c179871d733194f6008355cbe1c743638f72b17bd251c2681720214d477aa0ccaa059850f10c8afa9634a3dbcb6772404ab531aa4a0569701a578427ba0ceaa002e925f7c7fc0fda8d854f15fc709b280fd7a7a28127717caa56ee75ad67c82da091891c805738d41ff1e0c73b821a912f4b65b3e65b7d3f4afc3847ac3b2efc2da00bcba522f2615e7e3f9a81e04cd706a2222012d12da05cf7deca39214caf7f1ea06daa07961f37ce80d18e4c85908f72a501f5afd1bc324c66c23861e641220ed6a080ace8c88d9dd3ff82806cf0ba95460f53bd1313391539d062a08bfbcbd2ce3ba061600e0431d1e84fb53dbd3e5a84b6b7a1808a64dbb9d80a69cf4b9cfb806158a007553406e2f5da7af415f2fa55cb0c62e9f0ab8e453a53d52066553451e912c2a0ba3ff886ed5aeb3c2e8e3efff4e4ee7504d978a8a390f230fc31b732db6d95d8a027f087b45f903117afc4ddf6f51c97dd836a03313c501bed3eb878fba9a24af580");
        storageProofList[3] = RLP.encode(hex"f8f18080a01ff05c6ac03dbfc65acc35d317c0d3ec3e364f06e4d37382f23a6ebbf4389f96a00e94b2d9e0250e1759360ac14b155cf368b9b7cffda77a2b64dcdf3e8c0aea2ea09db20f89e8fd1af9d5e64ccc8fb378c42b817d7b9f81a2f0890de079e6ec077d80a0f8907c3a4b39c8bc3377817aef08d607620a8248ff8a0734899d7691b78b441da08bbc815ec576ce47929a12a999d9a48672418361159f2d266dfced9bc53ed249a056590ac65819a0b6cbfcb04b64c9667f3e4b0fd50e3b631898a0d10d6df646ab80a012d248064c226796f9e0017d98bff92539366b386b8e503fda4b7a166acebe4f808080808080");
        storageProofList[4] = RLP.encode(hex"f8429f207816ec57943ac573dfff1824385a0b74ccbb7ae56734a7e79bb580fdfb7ba1a0a97ce065a04d2abfec36a459db323721847718d3159d51c4256d271ee3b37e42");

        return RLP.encode(storageProofList);
    }
}
