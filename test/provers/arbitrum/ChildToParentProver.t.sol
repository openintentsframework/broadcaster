// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console, Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Broadcaster} from "../../../src/contracts/Broadcaster.sol";
import {IBroadcaster} from "../../../src/contracts/interfaces/IBroadcaster.sol";
import {ParentToChildProver} from "../../../src/contracts/provers/arbitrum/ParentToChildProver.sol";
import {IOutbox} from "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import {ChildToParentProver} from "../../../src/contracts/provers/arbitrum/ChildToParentProver.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {IBuffer} from "../../../src/contracts/block-hash-pusher/interfaces/IBuffer.sol";

import {RLP} from "@openzeppelin/contracts/utils/RLP.sol";
import {BlockHeaders} from "../../utils/BlockHeaders.sol";

contract BroadcasterTest is Test {
    using stdJson for string;
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

    function _getAccountProofBroadcast() internal pure returns (bytes memory) {
        // Nodes sourced from test/proofs/arbitrum/proof_broadcast.json (accountProof)
        bytes[] memory accountProofList = new bytes[](8);
        accountProofList[0] = RLP.encode(
            hex"f90211a068495e12a1ce50376d2d8a89f1b628c36270cb4d6674ce028eb0abfbd9a86d5ba0dd317914d747cdcfdc457d6275b011db4dbb72e2970bacfa03a8f63afdb95a6ba0e22db85789d8c1109174c3ab18c4e75564c9897ce7f740a72ce43e76e222fc8ba023adf0a3c0cd33e5e7c3d60231b5a33083867fb8ddbf58583884055cd37a3f66a04a4359e679c5074fd062e48d843196c31f2cd57dbf256c76ff85aeeda080c7fba0d2952adeacf9c50306e3972b46853fca57bcc9b5e2de6f01291df67142340d7da0f93b7549b46f79e78abee70b7c799ce8a63533b360b895b4d884af0e81b623bba0c4ca4fb6f4b96eba8063599d26d99aec5e97a3748b4322ecdc211e0e49cd0ec0a0b62bb8d52d875db984da8f91df931690356458c33d45b1971c569a2a96788105a01e4d8b3234845557ab14596975ff4a7f1ac4a7ea924fe5525cbe1fd58eb88172a013e3a6e41cfd3a87e8afaf61d49c3e8693f9eb0928627b8dce38e3a6331bc91aa0759faf37fc3c53567ed6611702984e90b11e97f3260d9a09dd84f2cef8fa5bb9a03d7e08b6f5ebbfb0c8f6e4473907d00891fae1c789768cc9ad416ea349b155cba02f49d77a68807f13596e116de4c153d9fc8ff8598765474af9ee805eded21797a00c4a2bf78904e075efacf92be4c83ba8ae47aee6bf55a28739c92c7535c78c34a03a8d1eeb23fcca04b152d4fe181a38ae94e0959da2438690c526a0d3b9af92f080"
        );
        accountProofList[1] = RLP.encode(
            hex"f90211a013ba5cf4109987ddcd54c27e499cc826a5243bb7aca7ab903c175522aa8d6ed3a000b67a90047f2b8c9f130f3d5c3e0c9f216cf142551364b55630ce6e4f4e6938a0daf3269dcc36a96de79482e066ba539e6df3cf6991686e304ede0e63daa40703a0d4390373b872e576fd1462045b66cd0b9707416bdae9316cf68cf542697d12e9a03cb921d65167c85635fd95986cb02f961992b05d2f9da44995a64ace570f18eda02a780b383890077cda05ac536f68656c8911cd2f1ed2151201ff4e99bb95f314a0f09464ba6eefe927d5cb3ab7c3da4fa7841da1e4e14feed4dfefd3e223f8cd11a06580f23f6555775babd169942479bd4f9a53b84f63236107bc2327902aa2fd35a081b0fc5747fc2916a801113e27bf272b1042d4f1515512e4e60e5be6b5f45cf1a0fa9de81cb423db803a205617df94a59ecc30b46e2b1b000ff280ba9aa2ede7fba0921f589b695004609a322552d02f10d11c8e38c73c7430070827c33bfa7619cba05dd8e78185c78638210a3bce08a3f72db55abdd157964ae17d0d781c82ebd53aa0a90d777bcb45bc01ed5147d461cc879514bb1cb756a25a3815a2f1c09fb88131a08538a7397dd218f50af9ccc60e50e362c6ce2815e2bcd9f13ac4c3e96e620242a0074e847c66f19dba42a32bb700546caac4d641661f1a580a7b76d5ec59890446a0cebdfa4c3d8726c479ca27cfb03ceaad2cf801470249a01d6fa364a5a3b6d57180"
        );
        accountProofList[2] = RLP.encode(
            hex"f90211a0aa7fa2b8a272ef1fa767bb9f1280eb21e0532a1702e78bc39598f40e4f1ed512a0c0aa53b903ae2ed87db2ef82ddc0ab5f8f9f326bd21843cd016e00c03ab1f708a088f4d386420b5dc0c69dd448302b332b36e81aae9cc82768fde8014b8ccc47a8a07d1d769406e1333e9e92a3d92fbd6f5b83dab3299056f5a89ffbab1550fee6d7a0f2df43ab2e783535760cef36a87de399c6dbf9c192bdd5fdb02f7136c9a93893a0311f3f7ada5b7ab5ee59e6c6d84abedc14e336b54461db6a6d275091e05d31aea0a7254108824c3a9e40029e1bec15c8488e5b689029569fdf0ba6dd1f84677ffaa0f73e394af18c408e349d3761c8feaeaeddaa2d4ecc530f9a1c00b344b0c1279ea01e3492673d849acedb43f5b47f5d5d6bc29500398ec59403927146660f4d0605a09db66687d86cc49388277e21ab54a756691cde14d4ea9dd797415e6861f3d684a081f0b42bd39b6b75f63313e6a63c4ab432653b94f2a90efabe98777069b603baa044cb3b8f855eaebd9cf777f1749e05ee768529f2f36fcf0e78d162a312c2ffb6a05d364fad6797f2a171c533e877b5a5565d82736085bec2190eadddb54e4e860aa0e42f8173ead0140e176bd6ffeed00063891d4fc90d22b52cd342b5ee2f87f2a7a0ba00732131622890d5f0c1c9f7aa6fba55bd29c51128c6960253fea01b6a76d2a047a602487abe4f58d433f6324be127f58cdfd50bdf7ac86ef362071b72975cce80"
        );
        accountProofList[3] = RLP.encode(
            hex"f90211a0ac6a821457345770334e09dd8ef630a29a0015692628c4cc18bc4d017926585fa04f8f7c3a2aba215f0cf64a1607b643579175dc5243093b7cfbf8fee52e5cc652a06dc52d24e3c528a58e8c5cc18d7e611e5b8ba6d39561b1ef17707f2138e0f4b7a04f9109a265a0beaad642106742003593f8b0c1db3a2d6366c48a6dacf03ec0d8a02566899094f4564cdb189a0a5e4109eb0550499677bb343a310dd3eeadf04774a0f146340af3750d21e479c29b2f29f92649834b9544ef185bb543f67f6565f739a0bc2782a82075c4776fae40f8a076ef2187a9530a16f14dabc167829b604fd125a08786b8148ab9ac7c6e60d0fd3c371c0262cc2b4738da282797a450d84f1db21aa0fef29cf945ea13a49906d801a83e876af0267c07a536ce7ecf531a41984f33ada012242a3b92cd965f289c7343faa887a933e51ed84a9dcffa4ab785732a3da42ba0d61135542c4d13f2a611cb1957bb61b57cad5650ab9a5e2ed666ac320007dbafa010e12a652adab679df34b3e6bd76db9f114bace57589ac1ae22de83ef40417dea0eb6470ab3489b70cd4acaebaa6fac49896f4fe2987f0e94eff9701847b126cbfa0dedb1ffa019901ab7cbb6ffbb936a03c3a4a5ba84115cad7c55d0aa5167f4ef2a0189509e85a1bcd72f4fe8e16bce32e0a61c42b7f12f3275aaaad88602e9e7fc1a053540eb812a50a34c8c59857894e45bda9c6a7b03a96ddc5f88dc2623ed2c04680"
        );
        accountProofList[4] = RLP.encode(
            hex"f90211a09cbd69967953472248f33bc7b65dbc11e51a331f31c5a5b1863f701ea7f136dfa08da14622e86f9e9ac6e98ba34fc355ed91c487487390ced7d9ce2e6d38d1873ea05c596a0006f15316a1b763c297b57c66511e8cd3d552336c7b89ab04bd743ee8a0e535f7b306552ea06eb435d824c4b9e58fa6609d660df7e63595ea3e77426c4ea00e0221ccf429371d655686bcccbf582ada081a835c405eedb15c63c251040b29a012934cf1e4a01094581e3807f046c883b3fc8be7182227fb4d5f271d1745772ea0d16a6490fad1250761d787577614e8d915ea318d73ba4b7eb5f437d90c8bc042a03086df460b9506f938d2e552b6733c8ce61541f8bd1101532cedaf4df3eae2f5a001edbcfe3c65d7b7de957dd654d41f8457caf1586d425cdd0acdf3ac3bcaaafaa0e3e9b52dd3ac2b4b58c807a7b09c99bca44f9e8331ceea2e4b50097122cf43f7a0ff05a213975640dab564ee97a48e2139b56b905aa9f8e1f2ccf46787c9ddbe07a02639992585fe80ab0aa3c1c9a0509a1e3450f78d2a39b17ff6782dc4b2cc9c57a0c8c052b18b1fcb7da093118caa6fbbdd55d30ceb9eeef71b6c2f01ee51ed4d32a0adce55a5efbd2f07154a502bcbe38921319bf30cbcbe8fe0b34e5ee353a53010a006bfb31bd1c9fdf0db840190f8f6ff696671729f3e78379ec55d77fd8fee6343a037c889398e7e44c91c454a77c69f3689b294157958e90bbf1848df30a7670d7480"
        );
        accountProofList[5] = RLP.encode(
            hex"f90211a092d7d5895494170e8a4b81bdf8798663e30016d3f3232dc5b9b60ba44e1854eca03c646b103610a0d85c5b512f863db1e02c758bf06cdade3ce278cb9ad7c5dd7ea0098340a50f05166e18dc4eaf680d4cca5c3ef3122b252bb25c61eb46113de5eca0bcf6ea20fee054dfa15f3ebb6bc4ff4303ddaa2eb1c559b2715782a43d90d38aa0f6f5db2476cb67984e422ba5ee4d033208701c5cd647eb20fe0fa610f65f999ba06337d18d5714d4429b75a560aa08901ea18e8cd05f02ab3b4cb183659a639a34a005fa8296eb592ce18931966e68763e963e69da388264d69d3ca9d6c1f0565188a08741c5279f29a8b3f4faef7612d7e1164ddaebbc274a3263a25a6be869249b99a06f3ce8da16d989dedcc9311638fe878fcfc210bb58906849e2e1f6337166c4daa0a2a00f1d61a1270107929ea04e7e1452278025ae90e95665e6f78f20fc0bf77da09020440ff072ab6e6f3b10bd9c93be7d3dee74c1c2106de434c687ff5cb6e2d6a00b640358864ac03587fa522fbfa7f42802db08cbaf46149c58e03e192ba6b468a06702242b240695c83bcb62eaeb3e0eb9dd3536c38ae574dfce25fd8c7210341ea0dd93ab820e27cf1469c04a4bfd6a26137e65aa8ba1a135f729a241dac513e192a0155927a6f52025cb53999a049840bd8693461083e276ff586a864781dba35f8ca0b5ec104a87a0773756ad6b0cc44edf6afe89c89db5ce94b3ecbc29b84bb1d85680"
        );
        accountProofList[6] = RLP.encode(
            hex"f90171a0e0d4461d9aec51264a25b47c44d423a8315ac1742752b979d3f27babd82ede39a0e221333bd270f7c2407ca99c34e15e74c120cdf2edf2fdc1523284ac32f89dd1a040196e43c59bba4d30dd08937e1f7536dd2bb76d502d29a9ef520e2df107fb2ba061760a5085194cbfaa61cbc5ecf57ab9a878d150051045770ba0c7e52d48948da0305506affe332344a6e16aa49bd5fc4cbc2d680602fd4a2c1bb130cb56aaefeda0f6bbc85f5eb04edf849889dd15811309c0cc1b0383bc4c92a7c1b4d0bcec5f5380a0bfca7c4787eb9d7e4f4a94d5996577d636056e4f0e8ee18dd43bc49d00ab7c48a06851e6a4a5d7312f645587de4855ec5b319324e981fc01da0e9bc30031428c6fa09e9ba798b699a2b7d92981123cefa304f5538c8f788f745b37a31e6fb75eaddca024eb1e981929ebac2bc6355806b961e91a918a65a3e0156c84b5aa567478a8b8808080a02d23b0058d7096d72982289e05102781c64644d61478aa11e6f8ac04a9771ddb8080"
        );
        accountProofList[7] = RLP.encode(
            hex"f8669d32cc05f6ec97cdd52af5716ff806f93adbe088fcbe6aea1197da14c00bb846f8440180a0bf4af2e8e4472148c44c393bd49fd938d117337c5348177981fb025d21339b76a03debe8ce6033a7570465c1bd57dfe3c0ca9dba458721039d4d47c10d5025252b"
        );
        return RLP.encode(accountProofList);
    }

    function _getStorageProofBroadcast() internal pure returns (bytes memory) {
        // Nodes sourced from test/proofs/arbitrum/proof_broadcast.json (storageProof)
        bytes[] memory storageProofList = new bytes[](1);
        storageProofList[0] =
            RLP.encode(hex"e8a120e9c5cc9c750ef3a170b3a02cf938ffded668959e8c4d274ee43f58103248e67e858468f9ca7f");
        return RLP.encode(storageProofList);
    }

    function _loadPayload(string memory path) internal view returns (bytes memory payload) {
        payload = vm.parseBytes(vm.readFile(string.concat(vm.projectRoot(), "/", path)));
    }

    function test_getTargetStateCommitment() public {
        vm.selectFork(childForkId);
        bytes memory payload = _loadPayload("test/payloads/arbitrum/calldata_get.hex");

        assertEq(payload.length, 64);

        uint256 input;
        bytes32 targetStateCommitment;

        assembly {
            input := mload(add(payload, 0x20))
            targetStateCommitment := mload(add(payload, 0x40))
        }

        bytes32 result = childToParentProver.getTargetStateCommitment(abi.encode(input));

        assertEq(result, targetStateCommitment);
    }

    function test_getTargetStateCommitment_broadcast() public {
        vm.selectFork(childForkId);

        bytes32 targetStateCommitment = 0x57845b0a97194c2869580ed8857fee67c91f2bb9cdf54368685c0ea5bf25f6c2;
        uint256 blockNumber = 9043658;

        bytes32 result = childToParentProver.getTargetStateCommitment(abi.encode(blockNumber));

        assertEq(result, targetStateCommitment);
    }

    function test_getTargetStateCommitment_broadcaster() public {
        vm.selectFork(childForkId);
        bytes memory payload = _loadPayload("test/payloads/arbitrum/broadcaster_get.hex");

        assertEq(payload.length, 64);

        bytes32 input;
        bytes32 targetStateCommitment;

        assembly {
            input := mload(add(payload, 0x20))
            targetStateCommitment := mload(add(payload, 0x40))
        }

        bytes32 result = childToParentProver.getTargetStateCommitment(abi.encode(input));

        assertEq(result, targetStateCommitment);
    }

    function test_reverts_getTargetStateCommitment_on_target_chain() public {
        vm.selectFork(parentForkId);
        bytes memory payload = _loadPayload("test/payloads/arbitrum/calldata_get.hex");

        ChildToParentProver newChildToParentProver = new ChildToParentProver(childChainId);

        assertEq(payload.length, 64);

        bytes32 input;
        bytes32 targetStateCommitment;

        assembly {
            input := mload(add(payload, 0x20))
            targetStateCommitment := mload(add(payload, 0x40))
        }

        vm.expectRevert(ChildToParentProver.CallNotOnHomeChain.selector);
        newChildToParentProver.getTargetStateCommitment(abi.encode(input));
    }

    function test_reverts_getTargetStateCommitment_reverts_not_found() public {
        vm.selectFork(childForkId);

        uint256 input = type(uint256).max;

        vm.expectRevert(abi.encodeWithSelector(IBuffer.UnknownParentChainBlockHash.selector, input));
        childToParentProver.getTargetStateCommitment(abi.encode(input));
    }

    function test_verifyTargetStateCommitment() public {
        vm.selectFork(parentForkId);

        bytes memory payload = _loadPayload("test/payloads/arbitrum/calldata_verify_target.hex");

        ChildToParentProver childToParentProverCopy = new ChildToParentProver(childChainId);

        assertGt(payload.length, 64);

        bytes32 homeBlockHash;
        bytes32 targetStateCommitment;

        bytes memory input = Bytes.slice(payload, 64);

        assembly {
            homeBlockHash := mload(add(payload, 0x20))
            targetStateCommitment := mload(add(payload, 0x40))
        }

        bytes32 result = childToParentProverCopy.verifyTargetStateCommitment(homeBlockHash, input);

        assertEq(result, targetStateCommitment);
    }

    function test_verifyTargetStateCommitment_reverts_on_home_chain() public {
        vm.selectFork(childForkId);

        bytes memory payload = _loadPayload("test/payloads/arbitrum/calldata_verify_target.hex");

        ChildToParentProver childToParentProverCopy = new ChildToParentProver(childChainId);

        assertGt(payload.length, 64);

        bytes32 homeBlockHash;
        bytes32 targetStateCommitment;

        bytes memory input = Bytes.slice(payload, 64);

        assembly {
            homeBlockHash := mload(add(payload, 0x20))
            targetStateCommitment := mload(add(payload, 0x40))
        }

        vm.expectRevert(ChildToParentProver.CallOnHomeChain.selector);
        childToParentProverCopy.verifyTargetStateCommitment(homeBlockHash, input);
    }

    function test_verifyStorageSlot() public {
        vm.selectFork(parentForkId);

        address knownAccount = 0x38f918D0E9F1b721EDaA41302E399fa1B79333a9;
        uint256 knownSlot = 10;

        bytes memory payload = _loadPayload("test/payloads/arbitrum/calldata_verify_slot.hex");

        ChildToParentProver childToParentProverCopy = new ChildToParentProver(childChainId);

        assertGt(payload.length, 64);

        bytes32 targetStateCommitment;
        bytes32 storageSlotValue;
        bytes memory input = Bytes.slice(payload, 64);

        assembly {
            targetStateCommitment := mload(add(payload, 0x20))
            storageSlotValue := mload(add(payload, 0x40))
        }

        (address account, uint256 slot, bytes32 value) =
            childToParentProverCopy.verifyStorageSlot(targetStateCommitment, input);

        assertEq(account, knownAccount);
        assertEq(slot, knownSlot);
        assertEq(value, storageSlotValue);
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

        IBuffer buffer = IBuffer(0x0000000048C4Ed10cF14A02B9E0AbDDA5227b071);

        address aliasedPusher = 0x6B6D4f3d0f0eFAeED2aeC9B59b67Ec62a4667e99;
        bytes32[] memory blockHashes = new bytes32[](1);
        blockHashes[0] = blockHash;

        vm.prank(aliasedPusher);
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

        IBuffer buffer = IBuffer(0x0000000048C4Ed10cF14A02B9E0AbDDA5227b071);

        address aliasedPusher = 0x6B6D4f3d0f0eFAeED2aeC9B59b67Ec62a4667e99;
        bytes32[] memory blockHashes = new bytes32[](1);
        blockHashes[0] = blockHash;

        vm.prank(aliasedPusher);
        buffer.receiveHashes(blockNumber, blockHashes);

        bytes memory input = abi.encode(rlpBlockHeader, account, expectedSlot, rlpAccountProof, rlpStorageProof);

        ChildToParentProver childToParentProverCopy = new ChildToParentProver(childChainId);

        (address actualAccount, uint256 actualSlot, bytes32 actualValue) =
            childToParentProverCopy.verifyStorageSlot(blockHash, input);

        assertEq(actualAccount, account, "account mismatch");
        assertEq(actualSlot, slot, "slot mismatch");
        assertEq(actualValue, value, "value mismatch");
    }
}
