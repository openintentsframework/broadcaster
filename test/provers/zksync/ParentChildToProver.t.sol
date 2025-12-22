// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {
    ParentToChildProver,
    ZkSyncProof,
    L2Message,
    IZkChain
} from "../../../src/contracts/provers/zksync/ParentToChildProver.sol";

contract MockZkChain is IZkChain {
    mapping(uint256 => bytes32) public l2LogsRootHashes;

    function setL2LogsRootHash(uint256 _batchNumber, bytes32 _l2LogsRootHash) external {
        l2LogsRootHashes[_batchNumber] = _l2LogsRootHash;
    }

    function l2LogsRootHash(uint256 _batchNumber) external view returns (bytes32) {
        return l2LogsRootHashes[_batchNumber];
    }
}

contract ZkSyncParentToChildProverTest is Test {
    uint256 public parentForkId;
    uint256 public parentChainId;

    function setUp() public {
        parentForkId = vm.createFork(vm.envString("ETHEREUM_RPC_URL"));

        parentChainId = 11155111;
    }

    function getZkSyncProof() public pure returns (ZkSyncProof memory) {
        // transaction hash: 0xebd27a8abb27e370c6ea78ae20bb1451ca4c414312044697dc73098f0e955661

        bytes32[] memory logProof = new bytes32[](36);
        logProof[0] = 0x010f0c0000000000000000000000000000000000000000000000000000000000;
        logProof[1] = 0xba721d8eb9acfdb6c9d126c73e753e704ed1ad03f5ae1e780a42b804a358289b;
        logProof[2] = 0x74fc01d158bebe1c78b66fb1c1f3243757aa7d7fd7c4dbf369c82a0b1985a81b;
        logProof[3] = 0x046ae899999754d50cb8837f25819fb1c89a1b6c5369e31919adf67bd9d16387;
        logProof[4] = 0xa786531a2f80df5b45f2278522956d4eec91639ce8e7c801e8a4777532dbafae;
        logProof[5] = 0x171acb5a7ac6bd565ac058b86eeb91ee9fec31b6bc63191c7319859ad517ea73;
        logProof[6] = 0xd1524dec2cb2f9fe4c6a65df20fd00bd127cb264c63b57cdbdbff9220e1979c3;
        logProof[7] = 0x66d7c5983afe44cf15ea8cf565b34c6c31ff0cb4dd744524f7842b942d08770d;
        logProof[8] = 0xb04e5ee349086985f74b73971ce9dfe76bbed95c84906c5dffd96504e1e5396c;
        logProof[9] = 0xac506ecb5465659b3a927143f6d724f91d8d9c4bdb2463aee111d9aa869874db;
        logProof[10] = 0x124b05ec272cecd7538fdafe53b6628d31188ffb6f345139aac3c3c1fd2e470f;
        logProof[11] = 0xc3be9cbd19304d84cca3d045e06b8db3acd68c304fc9cd4cbffe6d18036cb13f;
        logProof[12] = 0xfef7bd9f889811e59e4076a0174087135f080177302763019adaf531257e3a87;
        logProof[13] = 0xa707d1c62d8be699d34cb74804fdd7b4c568b6c1a821066f126c680d4b83e00b;
        logProof[14] = 0xf6e093070e0389d2e529d60fadb855fdded54976ec50ac709e3a36ceaa64c291;
        logProof[15] = 0xf7dee40f4d8b94f983076f3435067adec0f689c15b952eee60ccc7c5675f9b93;
        logProof[16] = 0x00000000000000000000000000000000000000000000000000000000000008d5;
        logProof[17] = 0x5f211cf8b014ea89ea6d8cd9fc5393a45b6a74b87ca155ba1b1c53090d5122a5;
        logProof[18] = 0xcc4c41edb0c2031348b292b768e9bac1ee8c92c09ef8a3277c2ece409c12d86a;
        logProof[19] = 0x52835f0f403fdc787f71794f03efff1105b0018d1feaa142bbb69d5ffd5686d7;
        logProof[20] = 0x4cd95f8962e2e3b5f525a0f4fdfbbf0667990c7159528a008057f3592bcb2c06;
        logProof[21] = 0x925e89147bb260c790628bdc8cab999454777f68dfa02514d69cd1745ae0797d;
        logProof[22] = 0xb5db2d4fe1e6b767734341bf876a562e0735721094f7d5221211eb089f79ab36;
        logProof[23] = 0x0a5f6c41e4aaebbcc906e88d076babe06188c00d48d7fec6e7913c684a991eb4;
        logProof[24] = 0xf82bdab99278345624d897be8747618882c3773507551b19f7781d1b1a6105c1;
        logProof[25] = 0x1b10d93c70611fb12dc351df7ce060c9bfcd2eb9d75d6cdb1af3bf3092f3f31d;
        logProof[26] = 0x8df5379fefae4adff70d71fd9e0f53a86f81b3e3a07c326468505b7a09d7521f;
        logProof[27] = 0xda185173bf3eb691ad5a68eaab1484df2d96b8c5d29f75d5f65ac6b28ee39f5a;
        logProof[28] = 0xa8a8e91b6bea9d7b61eaa7fd548b03445766c75c2aee6608d7c1b162ed032a0d;
        logProof[29] = 0x0000000000000000000000000000b99200000000000000000000000000000009;
        logProof[30] = 0x0000000000000000000000000000000000000000000000000000000000007f91;
        logProof[31] = 0x0104000100000000000000000000000000000000000000000000000000000000;
        logProof[32] = 0x356b32c2191984a81ffe9ed1daf0faebbc83cd5471ed49760de4077c0e055e97;
        logProof[33] = 0x41dfba0e4dd6b5e91fac4ff1de2bcff9b4435885d5330ecd4c6cc26e0447d38d;
        logProof[34] = 0xe07654c6d0b385cd0c9f20c213dee9e5502137a7b6a05e350b8ced1b94a9eed9;
        logProof[35] = 0x487867999683a00a7de702d49133af0a15785c25ed48dcc72cf71ea4bd862516;

        ZkSyncProof memory proof = ZkSyncProof({
            batchNumber: 18814,
            index: 4,
            message: L2Message({
                txNumberInBatch: 91,
                sender: 0x51665298A7Ce1781aD2CB50B1E512322A6B12458,
                data: hex"4d2f31e8578316b1eee225feb6442c49f42083864fa317ea81928e275ad2e3660000000000000000000000000000000000000000000000000000000069459b52"
            }),
            proof: logProof
        });
        return proof;
    }

    function test_verifyStorageSlot() public {
        ParentToChildProver prover = new ParentToChildProver(address(0), 0, 300, 32657, parentChainId);

        bytes32 expectedL2LogsRootHash = 0xc445ecf161f26c39cde0fe9a0db973d3d5193951d55c5d60f224cb0579370003;

        ZkSyncProof memory proof = getZkSyncProof();

        address accountSentMessage = 0x9a56fFd72F4B526c523C733F1F74197A51c495E1; // publisher
        bytes32 originalMessageSent = 0x0000000000000000000000000000000000000000000000000000000074657374; // "test"

        (address account, uint256 slot, bytes32 value) =
            prover.verifyStorageSlot(expectedL2LogsRootHash, abi.encode(proof, accountSentMessage, originalMessageSent));

        (uint256 messageSent, bytes32 timestamp) = abi.decode(proof.message.data, (uint256, bytes32));

        address expectedAccount = 0x9a56fFd72F4B526c523C733F1F74197A51c495E1; // publisher
        uint256 expectedSlot = messageSent;
        bytes32 expectedValue = timestamp;

        assertEq(account, expectedAccount, "account mismatch");
        assertEq(uint256(slot), expectedSlot, "slot mismatch");
        assertEq(value, expectedValue, "value mismatch");
    }

    function test_verifyStorageSlot_revertsWithWrongGatewayChainId() public {
        ParentToChildProver prover = new ParentToChildProver(address(0), 0, 300, 32657, parentChainId);

        bytes32 expectedL2LogsRootHash = 0xc445ecf161f26c39cde0fe9a0db973d3d5193951d55c5d60f224cb0579370003;

        ZkSyncProof memory proof = getZkSyncProof();

        proof.proof[30] = bytes32(uint256(123)); // change the settlement layer chain id

        vm.expectRevert(ParentToChildProver.ChainIdMismatch.selector);
        prover.verifyStorageSlot(expectedL2LogsRootHash, abi.encode(proof));
    }

    function test_getTargetBlockHash() public {
        vm.selectFork(parentForkId);

        MockZkChain mockZkChain = new MockZkChain();
        mockZkChain.setL2LogsRootHash(43984, 0x4cbeceb2a95a01369ab104ec6a305e37cb22d3717abb91da6880e038c3160470);

        ParentToChildProver prover = new ParentToChildProver(address(mockZkChain), 0, 300, 32657, parentChainId);

        bytes32 targetL2LogsRootHash = prover.getTargetBlockHash(abi.encode(43984));
        assertEq(
            targetL2LogsRootHash,
            0x4cbeceb2a95a01369ab104ec6a305e37cb22d3717abb91da6880e038c3160470,
            "targetL2LogsRootHash mismatch"
        );
    }

    function test_getTargetBlockHash_revertsWithNotFound() public {
        vm.selectFork(parentForkId);
        MockZkChain mockZkChain = new MockZkChain();

        ParentToChildProver prover = new ParentToChildProver(address(mockZkChain), 0, 300, 32657, parentChainId);

        vm.expectRevert(ParentToChildProver.L2LogsRootHashNotFound.selector);
        prover.getTargetBlockHash(abi.encode(43985));
    }

    function test_getTargetBlockHash_revertsWithNotInHomeChain() public {
        MockZkChain mockZkChain = new MockZkChain();

        ParentToChildProver prover = new ParentToChildProver(address(mockZkChain), 0, 300, 32657, parentChainId);

        vm.expectRevert(ParentToChildProver.NotInHomeChain.selector);
        prover.getTargetBlockHash(abi.encode(43985));
    }
}
