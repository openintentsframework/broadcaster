// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console, Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Broadcaster} from "../../../src/contracts/Broadcaster.sol";
import {IBroadcaster} from "../../../src/contracts/interfaces/IBroadcaster.sol";
import {IOutbox} from "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import {ChildToParentProver} from "../../../src/contracts/provers/linea/ChildToParentProver.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {IBuffer} from "../../../src/contracts/block-hash-pusher/interfaces/IBuffer.sol";
import {BufferMock} from "../../mocks/BufferMock.sol";
import {RLP} from "@openzeppelin/contracts/utils/RLP.sol";
import {BlockHeaders} from "../../utils/BlockHeaders.sol";

contract LineaChildToParentProverTest is Test {
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
        childForkId = vm.createFork(vm.envString("LINEA_RPC_URL"));

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

    function test_verifyTargetStateCommitment_buffer() public {
        vm.selectFork(parentForkId);
        uint256 targetBlockNumber = 0x9c533c;
        uint256 accountLeafIndex = 673653;
        bytes[] memory accountProof = new bytes[](42);
        accountProof[0] =
            hex"00000000000000000000000000000000000000000000000000000000000a4a300b2f8516745cf175195b438204bca95bec9bbf1e432fdc82ef6a0b4f91249eef";
        accountProof[1] =
            hex"008a47a2a53dd5183a2dc127c399a004e2a6c7e60f73e104d7d79e6a2bd7e809008a47a2a53dd5183a2dc127c399a004e2a6c7e60f73e104d7d79e6a2bd7e809";
        accountProof[2] =
            hex"060f08aed06ffb90efc9705dc38d37a7000da1add99cef1b8a84b9e72e7c8b7b060f08aed06ffb90efc9705dc38d37a7000da1add99cef1b8a84b9e72e7c8b7b";
        accountProof[3] =
            hex"0a06dc31ae8e893bca0a076decb8c0caa9036b5f394abf79d7956411eef322550a06dc31ae8e893bca0a076decb8c0caa9036b5f394abf79d7956411eef32255";
        accountProof[4] =
            hex"01f35ef342eaa841ee4306d38f2a1adeafe8967d23c31fe1a379b9a69353da6d01f35ef342eaa841ee4306d38f2a1adeafe8967d23c31fe1a379b9a69353da6d";
        accountProof[5] =
            hex"090d53176fd185da729d0d68e0c0e646ef148f15864685f4ba56be7b7cbb2484090d53176fd185da729d0d68e0c0e646ef148f15864685f4ba56be7b7cbb2484";
        accountProof[6] =
            hex"11c8e229e3e2ae40a4959e036d500753aaedb52cda67d9caf60f0629f0b4f30611c8e229e3e2ae40a4959e036d500753aaedb52cda67d9caf60f0629f0b4f306";
        accountProof[7] =
            hex"07f048ac696418580a55a864a10ed030871fd615d5ab460c54d6184c16441d4807f048ac696418580a55a864a10ed030871fd615d5ab460c54d6184c16441d48";
        accountProof[8] =
            hex"0f5dc218160db17cfe8044d7ac4fd55dfcbdf2676815e2c15388f189bf144cd80f5dc218160db17cfe8044d7ac4fd55dfcbdf2676815e2c15388f189bf144cd8";
        accountProof[9] =
            hex"0cdf7d06a4b4b0e71713048f5f6ea86016467e909a27bfeeeca67b56c17e27390cdf7d06a4b4b0e71713048f5f6ea86016467e909a27bfeeeca67b56c17e2739";
        accountProof[10] =
            hex"014030b5cbe31660da2d33b6b1265b82bbde9a7ab7f331f8b274f2b798a45a3b014030b5cbe31660da2d33b6b1265b82bbde9a7ab7f331f8b274f2b798a45a3b";
        accountProof[11] =
            hex"11c8aeb3dc3ca059a29ba20d4471b20987d74a0d79ff8ecda247df6a02eca55411c8aeb3dc3ca059a29ba20d4471b20987d74a0d79ff8ecda247df6a02eca554";
        accountProof[12] =
            hex"1092d1b2349c4fbc88ea0202cf88685e4e316c99697063f786201b27d46e2c221092d1b2349c4fbc88ea0202cf88685e4e316c99697063f786201b27d46e2c22";
        accountProof[13] =
            hex"0969f4e85b86f0eb36ad13dfb1f35346d7d6518308dc27e73452c649850f1a890969f4e85b86f0eb36ad13dfb1f35346d7d6518308dc27e73452c649850f1a89";
        accountProof[14] =
            hex"079081f446c9a0c7b404834742cea1909426ccfc4696d19e1a08531b0cc30368079081f446c9a0c7b404834742cea1909426ccfc4696d19e1a08531b0cc30368";
        accountProof[15] =
            hex"004d50e626bda007887a31f60883e58bce50a1a3e7a3384b9ec18dab319dd458004d50e626bda007887a31f60883e58bce50a1a3e7a3384b9ec18dab319dd458";
        accountProof[16] =
            hex"0b2ae68e3af633dac72090cc9c9b0dce76cebf5117101a265f54b3b9a851b3cd0b2ae68e3af633dac72090cc9c9b0dce76cebf5117101a265f54b3b9a851b3cd";
        accountProof[17] =
            hex"0b7a8a9fe0ee619c9bd7ff504dcb47bdce0193546b53a79dedd5251f4f56f36c0b7a8a9fe0ee619c9bd7ff504dcb47bdce0193546b53a79dedd5251f4f56f36c";
        accountProof[18] =
            hex"0defe934a1ae079cf6ec6022145b60128eeb30503eea4404da990fc2b2430ea80defe934a1ae079cf6ec6022145b60128eeb30503eea4404da990fc2b2430ea8";
        accountProof[19] =
            hex"0e42718d49cb8c4be515181eda51f41d3b8198af5a2139a4670a8ee06b904a2b0e42718d49cb8c4be515181eda51f41d3b8198af5a2139a4670a8ee06b904a2b";
        accountProof[20] =
            hex"1276c046afd611be02a66cf85498d7210a15293357afe07968a86c89356662f51276c046afd611be02a66cf85498d7210a15293357afe07968a86c89356662f5";
        accountProof[21] =
            hex"04788a182809d30f07b4599b3d6de48ec1f9d7e592fa9b71d2a4e8e302496a4b0363d1479ee3fd6a6338e325b00af776c908cc8307086c8d35f494a91c80ad21";
        accountProof[22] =
            hex"070382f72e9f322433fb44fc4acfefd74b277b19b6cc1784379e7ca7338a2978070382f72e9f322433fb44fc4acfefd74b277b19b6cc1784379e7ca7338a2978";
        accountProof[23] =
            hex"0b2ba209569ae50b54730e958445aaa41922f50c0cb432a0f659932e6e452412017cc0b295fc9ca4547472fb7c80ab77b78f9e58cdc9fe35fb034ce891a97d26";
        accountProof[24] =
            hex"0b03678742039acaae14fd3964e2d6261b74410043c536f07bcf1bc4495d9f840b03678742039acaae14fd3964e2d6261b74410043c536f07bcf1bc4495d9f84";
        accountProof[25] =
            hex"0f3f9cf1e5ba6bdbb6daafc405bcceac97270fe89265b6a0faa2ba4bfd5cbf5d0f3f9cf1e5ba6bdbb6daafc405bcceac97270fe89265b6a0faa2ba4bfd5cbf5d";
        accountProof[26] =
            hex"0f68d2ba4bbd495e17f5aa587779c99cd5b3328db8d1a25a642c3378e3e3bbd10bd5c582cedfab879a04209e72f0847d7b59162579fa8e69f8962e9ff61c573f";
        accountProof[27] =
            hex"10c439d656480d21a08c068717556fb8104a7a76e26f60e393ce4e36ae21e07b10c439d656480d21a08c068717556fb8104a7a76e26f60e393ce4e36ae21e07b";
        accountProof[28] =
            hex"09ea86c5cd59ac4bfca4e46e7b50bb37c8327350888ba71112ecf3f5093baaef09ea86c5cd59ac4bfca4e46e7b50bb37c8327350888ba71112ecf3f5093baaef";
        accountProof[29] =
            hex"06c34c9cd476ae245cc905eb830253de7584295f8b414511c7efef805319e2cb0b971345bfa43e192ca2fb1c9ddd19f2dddf461243b1a54fdd5a4d581f850c11";
        accountProof[30] =
            hex"0729c44ed3fee17009428a1f4ab17a41c6f0c474c9d278f4d8fd462214d85c4b0120c487a010567e61cc4129b755f4b6bb3bed522757dccd3ccbd96800f49584";
        accountProof[31] =
            hex"04a48a418e99a80a1f317054572f1aad48eec2906bc4a555aeca5ecc5f9b8f950e1976a0e93563dc6c05ac14ee5e4b0ff417e84f6269291e0d4de418fbae139e";
        accountProof[32] =
            hex"128859bffdca4eb38d90ae6908236366e72886977fca619fe245c261b53c26110db42a219ce08744c9c35b01e509b1fe40aff2722bb9039fd48b9f2e02006248";
        accountProof[33] =
            hex"0993be45e9a36d995bb00d32b92ce49fa2015b15e2d324e74b8e7c8b61e933690eb4b15fb71c85cdea250061b6ab35aabfdff7858d2a9bbce01852f34ebeaa92";
        accountProof[34] =
            hex"076746d90b7f0aa3ad2190b9e5d9cdefe1f4e9b718877c001e533ffc36fcda00034210572e89a83655ec70dd65f85bf70163db85435074c8cf4d1af7a056c9a9";
        accountProof[35] =
            hex"06e41a6d5188948108e3f6383aefc7754f3904379c71d390ec4991391cd3de150125a1c6fc0ac9cad41ad8adb3a1096ab88685bccd6d2ef479ed86c4f1a14678";
        accountProof[36] =
            hex"098491137f9d1cbd88a72b10d0be74905ecb288a9618675cd4696fe2d5cfe83e04b16080acb9dec784013107ffb48bdaa1925c24e14a5db1fb4b192bb85449c8";
        accountProof[37] =
            hex"0e8be6c7e221af9f11351442a0e9294b449baceb73e70c1e0db7d0fb96398dbd019e87a13e0d5fa6ff5da2beab937cec81bcbf7575b9a7a5b433ebbda091fa80";
        accountProof[38] =
            hex"041a6c689db6cd128413b24006200bcf6e8e909e2e4c5db010fdf35d2aa97caa0630681f1dc736958cf6d002e912cacb924db5b24e27549c0f66e7fd335ac60b";
        accountProof[39] =
            hex"0d4a240cb6b54a392a98e15519ad89b6549a2e94dd3e0aa8e15b26742a5a21650f5956e324da7c65481e4f3e88f9f0b57a50111d6383208459200b966b11d5c5";
        accountProof[40] =
            hex"000000000000000000000000000000000000000000000000000000000004b5b9000000000000000000000000000000000000000000000000000000000006387600f5d764266e3cc31f277ce01c7bddda19607547c63dd7424d50e432f82090470f63a265153ba08bbcba43e8438552a0951ed6e2649596419c3a4cec98d2679e";
        accountProof[41] =
            hex"000000000000000000000000000000000000000000000000000000000001e51500000000000000000000000000000000000000000000000000000000000242a90e10a5194dfc6f830261e04445396e9dcdc44dba69c67b57ae08e080d777d54e126beb5291e7543e42d82a331dde7cdb53fefd41dc5d4abbb18bccc653194489";

        bytes memory accountValue =
            hex"0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000009f81ae5665fb84995e1dfbe2323bd69117cf371a555ea8ac86a554362dd0c890729d847e461f41999bcd5341526994c155b990f7c36053e191e2ea35596ca8502c4bfece5f919cea85fdc6176179f14eb072611c00707de723dddd9c60db07a0000000000000000000000000000000000000000000000000000000000000ba5";

        uint256 storageLeafIndex = 240;

        bytes[] memory storageProof = new bytes[](42);
        storageProof[0] =
            hex"00000000000000000000000000000000000000000000000000000000000000f90cc2d861a2a43c4e9bbc8af123aa65121234cff9a6e9327433c1ee41bbce1536";
        storageProof[1] =
            hex"008a47a2a53dd5183a2dc127c399a004e2a6c7e60f73e104d7d79e6a2bd7e809008a47a2a53dd5183a2dc127c399a004e2a6c7e60f73e104d7d79e6a2bd7e809";
        storageProof[2] =
            hex"060f08aed06ffb90efc9705dc38d37a7000da1add99cef1b8a84b9e72e7c8b7b060f08aed06ffb90efc9705dc38d37a7000da1add99cef1b8a84b9e72e7c8b7b";
        storageProof[3] =
            hex"0a06dc31ae8e893bca0a076decb8c0caa9036b5f394abf79d7956411eef322550a06dc31ae8e893bca0a076decb8c0caa9036b5f394abf79d7956411eef32255";
        storageProof[4] =
            hex"01f35ef342eaa841ee4306d38f2a1adeafe8967d23c31fe1a379b9a69353da6d01f35ef342eaa841ee4306d38f2a1adeafe8967d23c31fe1a379b9a69353da6d";
        storageProof[5] =
            hex"090d53176fd185da729d0d68e0c0e646ef148f15864685f4ba56be7b7cbb2484090d53176fd185da729d0d68e0c0e646ef148f15864685f4ba56be7b7cbb2484";
        storageProof[6] =
            hex"11c8e229e3e2ae40a4959e036d500753aaedb52cda67d9caf60f0629f0b4f30611c8e229e3e2ae40a4959e036d500753aaedb52cda67d9caf60f0629f0b4f306";
        storageProof[7] =
            hex"07f048ac696418580a55a864a10ed030871fd615d5ab460c54d6184c16441d4807f048ac696418580a55a864a10ed030871fd615d5ab460c54d6184c16441d48";
        storageProof[8] =
            hex"0f5dc218160db17cfe8044d7ac4fd55dfcbdf2676815e2c15388f189bf144cd80f5dc218160db17cfe8044d7ac4fd55dfcbdf2676815e2c15388f189bf144cd8";
        storageProof[9] =
            hex"0cdf7d06a4b4b0e71713048f5f6ea86016467e909a27bfeeeca67b56c17e27390cdf7d06a4b4b0e71713048f5f6ea86016467e909a27bfeeeca67b56c17e2739";
        storageProof[10] =
            hex"014030b5cbe31660da2d33b6b1265b82bbde9a7ab7f331f8b274f2b798a45a3b014030b5cbe31660da2d33b6b1265b82bbde9a7ab7f331f8b274f2b798a45a3b";
        storageProof[11] =
            hex"11c8aeb3dc3ca059a29ba20d4471b20987d74a0d79ff8ecda247df6a02eca55411c8aeb3dc3ca059a29ba20d4471b20987d74a0d79ff8ecda247df6a02eca554";
        storageProof[12] =
            hex"1092d1b2349c4fbc88ea0202cf88685e4e316c99697063f786201b27d46e2c221092d1b2349c4fbc88ea0202cf88685e4e316c99697063f786201b27d46e2c22";
        storageProof[13] =
            hex"0969f4e85b86f0eb36ad13dfb1f35346d7d6518308dc27e73452c649850f1a890969f4e85b86f0eb36ad13dfb1f35346d7d6518308dc27e73452c649850f1a89";
        storageProof[14] =
            hex"079081f446c9a0c7b404834742cea1909426ccfc4696d19e1a08531b0cc30368079081f446c9a0c7b404834742cea1909426ccfc4696d19e1a08531b0cc30368";
        storageProof[15] =
            hex"004d50e626bda007887a31f60883e58bce50a1a3e7a3384b9ec18dab319dd458004d50e626bda007887a31f60883e58bce50a1a3e7a3384b9ec18dab319dd458";
        storageProof[16] =
            hex"0b2ae68e3af633dac72090cc9c9b0dce76cebf5117101a265f54b3b9a851b3cd0b2ae68e3af633dac72090cc9c9b0dce76cebf5117101a265f54b3b9a851b3cd";
        storageProof[17] =
            hex"0b7a8a9fe0ee619c9bd7ff504dcb47bdce0193546b53a79dedd5251f4f56f36c0b7a8a9fe0ee619c9bd7ff504dcb47bdce0193546b53a79dedd5251f4f56f36c";
        storageProof[18] =
            hex"0defe934a1ae079cf6ec6022145b60128eeb30503eea4404da990fc2b2430ea80defe934a1ae079cf6ec6022145b60128eeb30503eea4404da990fc2b2430ea8";
        storageProof[19] =
            hex"0e42718d49cb8c4be515181eda51f41d3b8198af5a2139a4670a8ee06b904a2b0e42718d49cb8c4be515181eda51f41d3b8198af5a2139a4670a8ee06b904a2b";
        storageProof[20] =
            hex"1276c046afd611be02a66cf85498d7210a15293357afe07968a86c89356662f51276c046afd611be02a66cf85498d7210a15293357afe07968a86c89356662f5";
        storageProof[21] =
            hex"02a9fd706c3c223f9374481b7495fb775c1675407556d93f1edabfe54b3fc9b202a9fd706c3c223f9374481b7495fb775c1675407556d93f1edabfe54b3fc9b2";
        storageProof[22] =
            hex"070382f72e9f322433fb44fc4acfefd74b277b19b6cc1784379e7ca7338a2978070382f72e9f322433fb44fc4acfefd74b277b19b6cc1784379e7ca7338a2978";
        storageProof[23] =
            hex"0133209cd7936e208da6b743428ff7195e8ef92d3dac72472146ac7497355ed10133209cd7936e208da6b743428ff7195e8ef92d3dac72472146ac7497355ed1";
        storageProof[24] =
            hex"0b03678742039acaae14fd3964e2d6261b74410043c536f07bcf1bc4495d9f840b03678742039acaae14fd3964e2d6261b74410043c536f07bcf1bc4495d9f84";
        storageProof[25] =
            hex"0f3f9cf1e5ba6bdbb6daafc405bcceac97270fe89265b6a0faa2ba4bfd5cbf5d0f3f9cf1e5ba6bdbb6daafc405bcceac97270fe89265b6a0faa2ba4bfd5cbf5d";
        storageProof[26] =
            hex"08b60393196453ee74fdf240449d9aa2569875b43596ea2621eecda8d8909acd08b60393196453ee74fdf240449d9aa2569875b43596ea2621eecda8d8909acd";
        storageProof[27] =
            hex"10c439d656480d21a08c068717556fb8104a7a76e26f60e393ce4e36ae21e07b10c439d656480d21a08c068717556fb8104a7a76e26f60e393ce4e36ae21e07b";
        storageProof[28] =
            hex"09ea86c5cd59ac4bfca4e46e7b50bb37c8327350888ba71112ecf3f5093baaef09ea86c5cd59ac4bfca4e46e7b50bb37c8327350888ba71112ecf3f5093baaef";
        storageProof[29] =
            hex"0b971345bfa43e192ca2fb1c9ddd19f2dddf461243b1a54fdd5a4d581f850c110b971345bfa43e192ca2fb1c9ddd19f2dddf461243b1a54fdd5a4d581f850c11";
        storageProof[30] =
            hex"0edd0129edd35191a183ecd28cbcab2a48ad381215d8544acf35248639835dcd0edd0129edd35191a183ecd28cbcab2a48ad381215d8544acf35248639835dcd";
        storageProof[31] =
            hex"06644a89954a1e4c49903c218d78dd5b09419db3088f84c919c938a5f98eda1706644a89954a1e4c49903c218d78dd5b09419db3088f84c919c938a5f98eda17";
        storageProof[32] =
            hex"0df25a23a4aa91719cb5445e6b1944078f1cbdf2de3b12ab37d63fb9d7e890070df25a23a4aa91719cb5445e6b1944078f1cbdf2de3b12ab37d63fb9d7e89007";
        storageProof[33] =
            hex"049d2c2696d9464e59eb1c74df4ca823633abc8c94549aea247cce621a297d5804d1d3be3decce75e2c8b056ea025fc81b2429615bf6f8ef736da72311e96c99";
        storageProof[34] =
            hex"00b452763bb75e98bf941396484c6cd3960a5e77db886e9ec7761f1517a473a906c5f6476878bdabab76079e6f7779a18ba68b4461f63885617e20c67026a733";
        storageProof[35] =
            hex"111a3db213769a3d98599fdf4c6a492ffa21bd0144eaa33f4f289fc9d18dd0230ae9991d1226dfba940bb5861ea0701d47ec0a10b0d6b14be44ca12a8d416c37";
        storageProof[36] =
            hex"0c63ed9ee9d17605962e25c0cc1d261aed75ecda3b1ba6fee9d76beb20b295c811b725ca61f2ce226720c194c5e0bcca075b28e6479ea238bb08ee676e9b8e01";
        storageProof[37] =
            hex"020d22cedbbed737d02e14cd772361212db185f19722a41d0f52f070b6e921bb03d32149dded57ddc5b1de7982c50ddebd44938118a1a7a77c05d0cd3893e7af";
        storageProof[38] =
            hex"0ed5bb5b77cf0d44b3256b2367d76f4ccb2d9b9b5133fc33210241c04a96ad31096dc704c579a99d3458f03b50e499dbf2d90d9f650517369c32052745f2cf0b";
        storageProof[39] =
            hex"1027dfc114249f17c62031669a4e5a69fd2e74ee4e5582d95e31c509e336603010f2a88a21af848ff879b4277bbbc95cee1a2a942399c1f7df4f8c0611088aff";
        storageProof[40] =
            hex"00000000000000000000000000000000000000000000000000000000000000ab00000000000000000000000000000000000000000000000000000000000000ac04dd4a693957c956abeffe5f9bcff637b4974e93c8929f35f4b946b3a0927803072ea100330fa5979ebf1602290bdc17d78062d35049adaaefb772d073b8bc91";
        storageProof[41] =
            hex"00000000000000000000000000000000000000000000000000000000000000a3000000000000000000000000000000000000000000000000000000000000003603b8286441062a542bdaac6adfa4c76fa1bbd497ae11a11a15bc7b680d0fb1d60c4c7cd0d408ec8fe199d1c94b5afa51cd0d09d1cd0aaa43e4f4845edc1d7413";

        bytes32 claimedStorageValue = 0x3d202b937d57f129b40c81922ea4f3820df711e9770150ee3fbb63e071f5cf9f;

        bytes memory input = abi.encode(
            targetBlockNumber,
            accountLeafIndex,
            accountProof,
            accountValue,
            storageLeafIndex,
            storageProof,
            claimedStorageValue
        );

        bytes32 homeStateCommitment = 0x0FC7B13A9FBAE3EFFF0901C4C95D2663BD317573D32EF0A86455A2368436FB7E;
        address buffer = 0x12432DeEEEBFF3aBF63549206dE28FA4Dec04638;

        ChildToParentProver prover = new ChildToParentProver(buffer, childChainId);

        bytes32 targetStateCommitment = prover.verifyTargetStateCommitment(homeStateCommitment, input);

        assertEq(targetStateCommitment, claimedStorageValue, "target state commitment mismatch");
    }
}
