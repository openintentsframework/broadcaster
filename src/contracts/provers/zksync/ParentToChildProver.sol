// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ProverUtils} from "../../libraries/ProverUtils.sol";
import {IBlockHashProver} from "../../interfaces/IBlockHashProver.sol";
import {IOutbox} from "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";

import {MessageHashing, ProofData} from "./libraries/MessageHashing.sol";

struct L2Log {
    uint8 l2ShardId;
    bool isService;
    uint16 txNumberInBatch;
    address sender;
    bytes32 key;
    bytes32 value;
}

/// @dev An arbitrary length message passed from L2
/// @notice Under the hood it is `L2Log` sent from the special system L2 contract
/// @param txNumberInBatch The L2 transaction number in a Batch, in which the message was sent
/// @param sender The address of the L2 account from which the message was passed
/// @param data An arbitrary length message
struct L2Message {
    uint16 txNumberInBatch;
    address sender;
    bytes data;
}

struct ZkSyncProof {
    uint256 batchNumber;
    uint256 index;
    L2Message message;
    bytes32[] proof;
}

import {console} from "forge-std/console.sol";




/// @notice Arbitrum implementation of a parent to child IBlockHashProver.
/// @dev    verifyTargetBlockHash and getTargetBlockHash get block hashes from the child chain's Outbox contract.
///         verifyStorageSlot is implemented to work against any Arbitrum child chain with a standard Ethereum block header and state trie.
contract ParentToChildProver is IBlockHashProver {
    /// @dev Address of the child chain's Outbox contract
    address public immutable outbox;
    /// @dev Storage slot the Outbox contract uses to store roots.
    ///      Should be set to 3 unless the outbox contract has been modified.
    ///      See https://github.com/OffchainLabs/nitro-contracts/blob/9d0e90ef588f94a9d2ffa4dc22713d91a76f57d4/src/bridge/AbsOutbox.sol#L32
    uint256 public immutable rootsSlot;

    uint256 public immutable childChainId;

    error TargetBlockHashNotFound();

    constructor(address _outbox, uint256 _rootsSlot, uint256 _childChainId) {
        outbox = _outbox;
        rootsSlot = _rootsSlot;
        childChainId = _childChainId;
    }

    /// @notice Verify a target chain block hash given a home chain block hash and a proof.
    /// @param  homeBlockHash The block hash of the home chain.
    /// @param  input ABI encoded (bytes blockHeader, bytes32 sendRoot, bytes accountProof, bytes storageProof)
    function verifyTargetBlockHash(bytes32 homeBlockHash, bytes calldata input)
        external
        view
        returns (bytes32 targetBlockHash)
    {
        
        // decode the input
        (bytes memory rlpBlockHeader, bytes32 sendRoot, bytes memory accountProof, bytes memory storageProof) =
            abi.decode(input, (bytes, bytes32, bytes, bytes));

        // calculate the slot based on the provided send root
        // see: https://github.com/OffchainLabs/nitro-contracts/blob/9d0e90ef588f94a9d2ffa4dc22713d91a76f57d4/src/bridge/AbsOutbox.sol#L32
        uint256 slot = uint256(SlotDerivation.deriveMapping(bytes32(rootsSlot), sendRoot));

        // verify proofs and get the block hash
        targetBlockHash =
            ProverUtils.getSlotFromBlockHeader(homeBlockHash, rlpBlockHeader, outbox, slot, accountProof, storageProof);
    }

    /// @notice Get a target chain block hash given a target chain sendRoot
    /// @param  input ABI encoded (bytes32 sendRoot)
    function getTargetBlockHash(bytes calldata input) external view returns (bytes32 targetBlockHash) {
        // decode the input
        bytes32 sendRoot = abi.decode(input, (bytes32));
        // get the target block hash from the outbox
        targetBlockHash = IOutbox(outbox).roots(sendRoot);

        if(targetBlockHash == bytes32(0)) {
            revert TargetBlockHashNotFound();
        }
    }

    /// @notice Verify a storage slot given a target chain block hash and a proof.
    /// @param  targetBlockHash The block hash of the target chain.
    /// @param  input ABI encoded (bytes blockHeader, address account, uint256 slot, bytes accountProof, bytes storageProof)
    function verifyStorageSlot(bytes32 targetBlockHash, bytes calldata input)
        external
        view
        returns (address account, uint256 slot, bytes32 value)
    {
        ZkSyncProof memory proof = abi.decode(input, (ZkSyncProof));

        L2Log memory log = _l2MessageToLog(proof.message);

        bytes32 hashedLog = keccak256(
            // solhint-disable-next-line func-named-parameters
            abi.encodePacked(log.l2ShardId, log.isService, log.txNumberInBatch, log.sender, log.key, log.value)
        );

        if(!_proveL2LeafInclusion({
            _chainId: childChainId,
            _blockOrBatchNumber: proof.batchNumber,
            _leafProofMask: proof.index,
            _leaf: hashedLog,
            _proof: proof.proof,
            _targetBatchRoot: targetBlockHash
        })){
            revert("Batch settlement root mismatch");
        }

        (bytes32 messageSent, bytes32 timestamp) = abi.decode(proof.message.data, (bytes32, bytes32));

        
        account = proof.message.sender;
        slot = uint256(keccak256(abi.encode(account, messageSent)));
        value = timestamp;
        
    }

    function _proveL2LeafInclusion(
        uint256 _chainId,
        uint256 _blockOrBatchNumber,
        uint256 _leafProofMask,
        bytes32 _leaf,
        bytes32[] memory _proof, 
        bytes32 _targetBatchRoot
    ) internal view returns (bool){

        ProofData memory proofData = MessageHashing._getProofData({
            _chainId: _chainId,
            _batchNumber: _blockOrBatchNumber,
            _leafProofMask: _leafProofMask,
            _leaf: _leaf,
            _proof: _proof
        });


        if (proofData.finalProofNode) {

            return _targetBatchRoot == proofData.batchSettlementRoot && _targetBatchRoot != bytes32(0);
        }

        return _proveL2LeafInclusion({
            _chainId: proofData.settlementLayerChainId,
            _blockOrBatchNumber: proofData.settlementLayerBatchNumber, //SL block number
            _leafProofMask: proofData.settlementLayerBatchRootMask,
            _leaf: proofData.chainIdLeaf,
            _proof: MessageHashing.extractSliceUntilEnd(_proof, proofData.ptr),
            _targetBatchRoot: _targetBatchRoot
        });

    }

    function _l2MessageToLog(L2Message memory _message) internal pure returns (L2Log memory) {
        return
            L2Log({
                l2ShardId: 0,
                isService: true,
                txNumberInBatch: _message.txNumberInBatch,
                sender: 0x0000000000000000000000000000000000008008,
                key: bytes32(uint256(uint160(_message.sender))),
                value: keccak256(_message.data)
            });
    }

    /// @inheritdoc IBlockHashProver
    function version() external pure returns (uint256) {
        return 1;
    }
}