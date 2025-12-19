// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ProverUtils} from "../../libraries/ProverUtils.sol";
import {IBlockHashProver} from "../../interfaces/IBlockHashProver.sol";
import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";

import {MessageHashing, ProofData} from "./libraries/MessageHashing.sol";

/// @notice Interface for interacting with ZkChain contracts to retrieve L2 logs root hashes.
interface IZkChain {
    /// @notice Retrieves the L2 logs root hash for a given batch number.
    /// @param _batchNumber The batch number to query.
    /// @return The L2 logs root hash for the specified batch.
    function l2LogsRootHash(uint256 _batchNumber) external view returns (bytes32);
}

/// @notice Represents an L2 log entry in the ZkSync system.
/// @param l2ShardId The shard ID of the L2 log.
/// @param isService Whether this is a service log.
/// @param txNumberInBatch The transaction number within the batch.
/// @param sender The address that sent the log.
/// @param key The key associated with the log.
/// @param value The value associated with the log.
struct L2Log {
    uint8 l2ShardId;
    bool isService;
    uint16 txNumberInBatch;
    address sender;
    bytes32 key;
    bytes32 value;
}

/// @notice An arbitrary length message passed from L2 to L1.
/// @dev Under the hood it is an `L2Log` sent from the special system L2 contract.
/// @param txNumberInBatch The L2 transaction number in a batch, in which the message was sent.
/// @param sender The address of the L2 account from which the message was passed.
/// @param data An arbitrary length message data.
struct L2Message {
    uint16 txNumberInBatch;
    address sender;
    bytes data;
}

/// @notice Proof structure for verifying L2 messages in ZkSync batches.
/// @param batchNumber The batch number containing the message.
/// @param index The index/leaf proof mask for the message in the Merkle tree.
/// @param message The L2 message to be verified.
/// @param proof The Merkle proof for verifying the message inclusion.
struct ZkSyncProof {
    uint256 batchNumber;
    uint256 index;
    L2Message message;
    bytes32[] proof;
}

/// @notice ZkSync implementation of a parent to child IBlockHashProver.
/// @dev This contract verifies L2 logs root hashes from ZkSync child chains on the parent chain (L1).
///      The `verifyTargetBlockHash` and `getTargetBlockHash` functions retrieve L2 logs root hashes
///      from the child chain's ZkChain contract. The `verifyStorageSlot` function is implemented
///      to work against any ZkSync child chain with a standard Ethereum block header and state trie.
///      This implementation is used to verify zkChain L2 log hash inclusion on L1 for messages that
///      use the gateway as a middleware between the L2 and the L1.
contract ParentToChildProver is IBlockHashProver {
    /// @notice The ZkChain contract address on the gateway chain that stores L2 logs root hashes.
    IZkChain public immutable gatewayZkChain;

    /// @notice The storage slot base for the L2 logs root hash mapping in the gateway ZkChain contract.
    uint256 public immutable l2LogsRootHashSlot;

    /// @notice The chain ID of the child chain (L2) for which this prover verifies messages.
    uint256 public immutable childChainId;

    /// @notice The chain ID of the gateway chain (settlement layer) that bridges between parent and child chains.
    uint256 public immutable gatewayChainId;

    /// @notice The chain ID of the home chain (L1) where this prover is deployed.
    uint256 public immutable homeChainId;

    /// @notice Error thrown when the requested L2 logs root hash is not found (returns zero).
    error L2LogsRootHashNotFound();

    /// @notice Error thrown when an operation is attempted on a chain that is not the home chain.
    error NotInHomeChain();

    /// @notice Error thrown when the batch settlement root does not match the expected target batch root.
    error BatchSettlementRootMismatch();

    /// @notice Error thrown when the settlement layer chain ID does not match the expected gateway chain ID.
    error ChainIdMismatch();

    /// @notice Error thrown when an operation is attempted on the home chain.
    error CallOnHomeChain();

    constructor(
        address _gatewayZkChain,
        uint256 _l2LogsRootHashSlot,
        uint256 _childChainId,
        uint256 _gatewayChainId,
        uint256 _homeChainId
    ) {
        gatewayZkChain = IZkChain(_gatewayZkChain);
        l2LogsRootHashSlot = _l2LogsRootHashSlot;
        childChainId = _childChainId;
        gatewayChainId = _gatewayChainId;
        homeChainId = _homeChainId;
    }

    /// @notice Verify a target chain L2 logs root hash given a home chain block hash and a proof.
    /// @dev Verifies that the L2 logs root hash for a specific batch is stored in the gateway ZkChain contract
    ///      by checking the storage slot using storage proofs against the home chain block header.
    /// @param homeBlockHash The block hash of the home chain (L1) containing the gateway ZkChain state.
    /// @param input ABI encoded tuple: (bytes rlpBlockHeader, uint256 batchNumber, bytes storageProof).
    ///              - rlpBlockHeader: RLP-encoded block header of the home chain.
    ///              - batchNumber: The batch number for which to retrieve the L2 logs root hash.
    ///              - storageProof: Storage proof for the storage slot containing the L2 logs root hash.
    /// @return targetL2LogsRootHash The L2 logs root hash for the specified batch number.
    function verifyTargetBlockHash(bytes32 homeBlockHash, bytes calldata input)
        external
        view
        returns (bytes32 targetL2LogsRootHash)
    {
        if (block.chainid == homeChainId) {
            revert CallOnHomeChain();
        }
        // decode the input
        (bytes memory rlpBlockHeader, uint256 batchNumber, bytes memory accountProof, bytes memory storageProof) =
            abi.decode(input, (bytes, uint256, bytes, bytes));

        uint256 slot = uint256(SlotDerivation.deriveMapping(bytes32(l2LogsRootHashSlot), batchNumber));

        // verify proofs and get the block hash
        targetL2LogsRootHash = ProverUtils.getSlotFromBlockHeader(
            homeBlockHash, rlpBlockHeader, address(gatewayZkChain), slot, accountProof, storageProof
        );
    }

    /// @notice Get a target chain L2 logs root hash given a batch number.
    /// @dev Directly queries the gateway ZkChain contract on the home chain to retrieve the L2 logs root hash.
    ///      This function must be called on the home chain where the gateway ZkChain contract is deployed.
    /// @param input ABI encoded uint256 batchNumber - the batch number for which to retrieve the L2 logs root hash.
    /// @return l2LogsRootHash The L2 logs root hash for the specified batch number.
    /// @custom:reverts L2LogsRootHashNotFound if the L2 logs root hash is not found (returns zero).
    function getTargetBlockHash(bytes calldata input) external view returns (bytes32 l2LogsRootHash) {
        if (block.chainid != homeChainId) {
            revert NotInHomeChain();
        }

        uint256 batchNumber = abi.decode(input, (uint256));
        l2LogsRootHash = gatewayZkChain.l2LogsRootHash(batchNumber);

        if (l2LogsRootHash == bytes32(0)) {
            revert L2LogsRootHashNotFound();
        }
    }

    /// @notice Verify a storage slot given a target chain L2 logs root hash and a proof.
    /// @dev Verifies that an L2 message is included in a batch by checking its inclusion in the L2 logs Merkle tree.
    ///      The message data is expected to contain a message hash and timestamp, which are used to derive
    ///      the storage slot and value on the target chain.
    /// @param targetL2LogRootHash The L2 logs root hash of the target chain batch to verify against.
    /// @param input ABI encoded ZkSyncProof containing:
    ///              - batchNumber: The batch number containing the message.
    ///              - index: The leaf proof mask for the message in the Merkle tree.
    ///              - message: The L2 message to be verified (contains txNumberInBatch, sender, and data).
    ///              - proof: The Merkle proof for verifying the message inclusion.
    /// @return account The address of the account on the target chain (from the message sender).
    /// @return slot The storage slot derived from the account address and message hash.
    /// @return value The timestamp value stored in the message data.
    /// @custom:reverts BatchSettlementRootMismatch if the message is not included in the batch.
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

        if (!_proveL2LeafInclusion({
                _chainId: childChainId,
                _blockOrBatchNumber: proof.batchNumber,
                _leafProofMask: proof.index,
                _leaf: hashedLog,
                _proof: proof.proof,
                _targetBatchRoot: targetL2LogRootHash
            })) {
            revert BatchSettlementRootMismatch();
        }

        (bytes32 messageSent, bytes32 timestamp) = abi.decode(proof.message.data, (bytes32, bytes32));


        account = proof.message.sender;
        slot = uint256(keccak256(abi.encode(messageSent, account)));
        value = timestamp;
    }

    /// @notice Prove that an L2 leaf is included in a batch.
    /// @dev Recursively verifies the inclusion of an L2 log leaf in a batch's Merkle tree.
    ///      If the proof spans multiple settlement layers, it recursively verifies each layer
    ///      until it reaches the final proof node or verifies against the gateway chain.
    /// @param _chainId The chain ID of the L2 where the leaf comes from.
    /// @param _blockOrBatchNumber The block or batch number containing the leaf.
    /// @param _leafProofMask The leaf proof mask indicating the position in the Merkle tree.
    /// @param _leaf The leaf hash to be proven (hashed L2 log).
    /// @param _proof The Merkle proof array for verifying the leaf inclusion.
    /// @param _targetBatchRoot The target batch root hash to verify against.
    /// @return success True if the leaf is included in the batch, false otherwise.
    /// @custom:reverts ChainIdMismatch if the settlement layer chain ID does not match the gateway chain ID.
    function _proveL2LeafInclusion(
        uint256 _chainId,
        uint256 _blockOrBatchNumber,
        uint256 _leafProofMask,
        bytes32 _leaf,
        bytes32[] memory _proof,
        bytes32 _targetBatchRoot
    ) internal view returns (bool) {
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

        if (proofData.settlementLayerChainId != gatewayChainId) {
            revert ChainIdMismatch();
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

    /// @notice Convert an L2 message to an L2 log structure.
    /// @dev Transforms an L2Message into the L2Log format used for Merkle tree hashing.
    ///      Uses fixed values for shard ID (0), service flag (true), and sender address
    ///      (the ZkSync system contract address). The message sender is encoded as the key,
    ///      and the message data hash is used as the value.
    /// @param _message The L2 message to convert.
    /// @return log The L2 log structure corresponding to the message.
    function _l2MessageToLog(L2Message memory _message) internal pure returns (L2Log memory) {
        return L2Log({
            l2ShardId: 0,
            isService: true,
            txNumberInBatch: _message.txNumberInBatch,
            sender: 0x0000000000000000000000000000000000008008,
            key: bytes32(uint256(uint160(_message.sender))),
            value: keccak256(_message.data)
        });
    }

    /// @notice Returns the version of this block hash prover implementation.
    /// @inheritdoc IBlockHashProver
    /// @return The version number (currently 1).
    function version() external pure returns (uint256) {
        return 1;
    }
}
