//SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console, Test} from "forge-std/Test.sol";

import {ParentToChildProver, IZkSyncDiamond} from "../../../src/contracts/provers/zksync/ParentToChildProver.sol";

import {SparseMerkleTree, TreeEntry} from "src/contracts/provers/zksync/helpers/SparseMerkleTree.sol";

contract ZkSyncParentToChildProverTest is Test {
    struct StoredBatchInfo {
        uint64 batchNumber;
        bytes32 batchHash;
        uint64 indexRepeatedStorageChanges;
        uint256 numberOfLayer1Txs;
        bytes32 priorityOperationsHash;
        bytes32 dependencyRootsRollingHash;
        bytes32 l2LogsTreeRoot;
        uint256 timestamp;
        bytes32 commitment;
    }

    struct CommitBatchInfo {
        uint64 batchNumber;
        uint64 timestamp;
        uint64 indexRepeatedStorageChanges;
        bytes32 newStateRoot;
        uint256 numberOfLayer1Txs;
        bytes32 priorityOperationsHash;
        bytes32 bootloaderHeapInitialContentsHash;
        bytes32 eventsQueueStateHash;
        bytes systemLogs;
        bytes operatorDAInput;
    }

    SparseMerkleTree public sparce;

    function setUp() public {
        vm.createSelectFork(vm.envString("ZKSYNC_RPC_URL"));

        bytes memory latestBatch = vm.rpc("zks_L1BatchNumber", "[]");

        uint256 latestBatchNumber =
            abi.decode(abi.encodePacked(new bytes(32 - latestBatch.length), latestBatch), (uint256));

        bytes32[] memory storageKeys = new bytes32[](1);
        storageKeys[0] = 0xed71b28e74e0c345ccea429109d91e298de836bf32290bfda4210d76bb646cd7;

        address account = 0x0000000000000000000000000000000000008003;

        sparce = new SparseMerkleTree();
    }

    function test_verifyStorageSlot() public {
        ParentToChildProver prover = new ParentToChildProver(IZkSyncDiamond(address(0)), sparce);

        bytes32[] memory path = new bytes32[](24);

        path[0] = 0x17fb6283151ad9351232d842b84ae9169af8a5883b616f39967d5003110cd918;
        path[1] = 0xf3c29dd26f477f181070c6e6b8eb065bc7e97542b352bbfefe47f0f470c7c9be;
        path[2] = 0xbdd038888ea8844923c3be830be8a878820847da0df802e5083c308e4d915eb9;
        path[3] = 0x1ddbede31535d664dbc74bb14c304b2b984cdc1a0367ba5ed6b825c424e8805a;
        path[4] = 0x25c6633b686dba669411f9637309ead980c6b6360bc5477105327074f9fcf2dd;
        path[5] = 0x0b693af0ff03ab2769517ecbcd3ed7e1188958d8c1ee203b1548a6c7bfa08a0c;
        path[6] = 0x2a05a0a77238f5d17c88bf8851fb59c16211aaf3bd75e25fe0f7c5382ea911d7;
        path[7] = 0xc59f6a4e83ced9a3dff05057a8204b68e251df0a1b88ebbd3ff42e590c0db20c;
        path[8] = 0x1aa1fad374ab774184ca658e7d25beded20e872c0f813986eb67af9db214ba74;
        path[9] = 0xe97ef72246965f5a8efdd04e51858c9510bc3867afa437af5ffefa323e88e4b8;
        path[10] = 0xd974e2368e4abcb1b6f2fc6b3f93723e8c185b19ab68556b7b6c7e9d5658bd16;
        path[11] = 0x2585318f0ae1d7670ae921e5e02ad87b581d084dfd1e96bc8ca1310ae9703685;
        path[12] = 0x2b9c92773a9d9ad930fc3f2afc0e7ceabf0cd888952a69b2745d1fd35881c0b9;
        path[13] = 0xe519d118e01ae8f5aa6c83fef18c0308d73531614f1a5bab05a0cf7ab62871ac;
        path[14] = 0x56efe8a330578f4a8c8fbc28b40ad7e5c5ba7705e8107a13121b94ae5b42aba5;
        path[15] = 0x3182a02f284e18467b0217211a888f39f8bc45e491dd688240472846d303383c;
        path[16] = 0xe64829e98f5d08252b07241a3777cff8d3cce1ff223bf90238f8d6522826a5af;
        path[17] = 0x212812c4692621d3af9395a1440ceca7dbfcfc236ccd57c69c67c7b8c4919e1e;
        path[18] = 0x8f6aa327f3e794bde1dc50022c334141b4972cf5d1efdc587d2b9e660ec1cea9;
        path[19] = 0xda17d99bd51d328c1b5fc0425835ff81c9e189417e91ad2571dae3e72788d74c;
        path[20] = 0xe5fbb07b4e46c805ea9bea975b697cd7cef4ed3dd33bc89d705d4e3703f521e6;
        path[21] = 0xda3d3144c95b1b1f3bec50a816eda209a377e763abf3f425c98762c9794b3131;
        path[22] = 0xbbcf9dba2802d9aa802e048eef22b2e8f682677464106cf083c53c22f32240af;
        path[23] = 0xb34a7a64886a3fab5e0eeb91f12f2ea5ea78ff05054790099fd2120c30c2ae0e;

        ParentToChildProver.StorageProof memory proof = ParentToChildProver.StorageProof({
            metadata: ParentToChildProver.BatchMetadata({
                batchNumber: 0x48d0,
                indexRepeatedStorageChanges: 0x26f3fc0, //
                numberOfLayer1Txs: 0x1,
                priorityOperationsHash: 0x45decabc1018dc1585ef3bdefac2ce5f5875b95b0c788a567c2fe0572f94cec1, //
                dependencyRootsRollingHash: 0x910b3320d29ee7b190ee0f9f76be94b663d2c437e37945645335518a8440f4df,
                l2LogsTreeRoot: 0x82df9311899ac3950a50baa4cc91021cb4317cf4a55ec00e354e42e2dc499a85, //
                timestamp: 0x693284ee,
                commitment: 0xcf2f23d2e27e86fce2e9489b212175114b8b5dc6ca5d25f69c7b4bb328f74e68 //
            }),
            account: 0x40F58Bd4616a6E76021F1481154DB829953BF01B,
            key: 0x4d2f31e8578316b1eee225feb6442c49f42083864fa317ea81928e275ad2e366,
            value: 0x00000000000000000000000000000000000000000000000000000000692dac93,
            path: path,
            index: 40831776
        });

        bytes32 targetBatchHash = 0x00ffc6d3d34bf5144d9bed2035b326343260e96893458e87b620153ee52547c5;

        bytes memory input = abi.encode(proof);

        prover.verifyStorageSlot(targetBatchHash, input);
    }
}
