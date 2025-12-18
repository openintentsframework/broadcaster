// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ProverUtils} from "../../libraries/ProverUtils.sol";
import {IBlockHashProver} from "../../interfaces/IBlockHashProver.sol";
import {IOutbox} from "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";

import {MessageHashing, ProofData} from "./libraries/MessageHashing.sol";


interface IZkChain {
    function l2LogsRootHash(uint256 _batchNumber) external view returns (bytes32);
}

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


/// @notice Arbitrum implementation of a parent to child IBlockHashProver.
/// @dev    verifyTargetBlockHash and getTargetBlockHash get block hashes from the child chain's Outbox contract.
///         verifyStorageSlot is implemented to work against any Arbitrum child chain with a standard Ethereum block header and state trie.
contract ParentToChildProver is IBlockHashProver {


    IZkChain public immutable zkChain;
    
    uint256 public immutable l2LogsRootHashSlot;

    uint256 public immutable childChainId;

    error L2LogsRootHashNotFound();
    error NotInHomeChain();
    error BatchSettlementRootMismatch();

    constructor(address _zkChain, uint256 _l2LogsRootHashSlot, uint256 _childChainId) {
        zkChain = IZkChain(_zkChain);
        l2LogsRootHashSlot = _l2LogsRootHashSlot;
        childChainId = _childChainId;
    }

    /// @notice Verify a target chain block hash given a home chain block hash and a proof.
    /// @param  homeBlockHash The block hash of the home chain.
    /// @param  input ABI encoded (bytes blockHeader, bytes32 sendRoot, bytes accountProof, bytes storageProof)
    function verifyTargetBlockHash(bytes32 homeBlockHash, bytes calldata input)
        external
        view
        returns (bytes32 targetL2LogsRootHash)
    {
        
        // decode the input
        (bytes memory rlpBlockHeader, uint256 batchNumber, bytes memory accountProof, bytes memory storageProof) =
            abi.decode(input, (bytes, uint256, bytes, bytes));

        
        uint256 slot = uint256(SlotDerivation.deriveMapping(bytes32(l2LogsRootHashSlot), batchNumber));

        // verify proofs and get the block hash
        targetL2LogsRootHash =
            ProverUtils.getSlotFromBlockHeader(homeBlockHash, rlpBlockHeader, address(zkChain), slot, accountProof, storageProof);
    }

    /// @notice Get a target chain L2 logs root hash given a batch number
    /// @param  input ABI encoded (uint256 batchNumber)
    function getTargetBlockHash(bytes calldata input) external view returns (bytes32 l2LogsRootHash) {

        uint256 batchNumber = abi.decode(input, (uint256));
        l2LogsRootHash = zkChain.l2LogsRootHash(batchNumber);

        if(l2LogsRootHash == bytes32(0)) {
            revert L2LogsRootHashNotFound();
        }
    }

    /// @notice Verify a storage slot given a target chain block hash and a proof.
    /// @param  targetL2LogRootHash The l2 logs root hash of the target chain.
    /// @param  input ABI encoded (ZkSyncProof proof)
    function verifyStorageSlot(bytes32 targetL2LogRootHash, bytes calldata input)
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
            _targetBatchRoot: targetL2LogRootHash
        })){
            revert BatchSettlementRootMismatch();
        }

        (bytes32 messageSent, bytes32 timestamp) = abi.decode(proof.message.data, (bytes32, bytes32));

        
        account = proof.message.sender;
        slot = uint256(keccak256(abi.encode(account, messageSent)));
        value = timestamp;
        
    }

    /// @notice Prove that an L2 leaf is included in a batch
    /// @param _chainId The chain id of the L2 where the leaf comes from.
    /// @param _blockOrBatchNumber The block or batch number.
    /// @param _leafProofMask The leaf proof mask.
    /// @param _leaf The leaf to be proven.
    /// @param _proof The proof.
    /// @param _targetBatchRoot The target batch root.
    /// @return success True if the leaf is included in the batch, false otherwise.
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

    /// @notice Convert an L2 message to an L2 log
    /// @param _message The L2 message.
    /// @return log The L2 log.
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