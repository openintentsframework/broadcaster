// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ProverUtils} from "../../libraries/ProverUtils.sol";
import {IStateProver} from "../../interfaces/IStateProver.sol";

interface IL1Block {
    function hash() external view returns (bytes32);
}

/// @notice OP-stack implementation of a child to parent IStateProver.
/// @dev    verifyTargetStateCommitment and getTargetStateCommitment get block hashes from the L1Block predeploy.
///         verifyStorageSlot is implemented to work against any target chain with a standard Ethereum block header and state trie.
///
/// @dev    Note: L1Block only stores the LATEST L1 block hash.
///         Historical messages CAN be verified by generating fresh proofs on-demand.
///         Pre-generated proofs become stale when L1Block updates (~5 minutes).
///         Operational difference from Arbitrum: proofs must be generated just-in-time rather than pre-cached.
/// @custom:security-contact security@openzeppelin.com
contract ChildToParentProver is IStateProver {
    address public constant l1BlockPredeploy = 0x4200000000000000000000000000000000000015;
    uint256 public constant l1BlockHashSlot = 2; // hash is at slot 2

    /// @dev The chain ID of the home chain (Optimism L2)
    uint256 public immutable homeChainId;

    error CallNotOnHomeChain();
    error CallOnHomeChain();

    constructor(uint256 _homeChainId) {
        homeChainId = _homeChainId;
    }

    /// @notice Verify the latest available target block hash given a home chain block hash and a storage proof of the L1Block predeploy.
    /// @param  homeBlockHash The block hash of the home chain.
    /// @param  input ABI encoded (bytes blockHeader, bytes accountProof, bytes storageProof)
    function verifyTargetStateCommitment(bytes32 homeBlockHash, bytes calldata input)
        external
        view
        returns (bytes32 targetStateCommitment)
    {
        if (block.chainid == homeChainId) {
            revert CallOnHomeChain();
        }

        // decode the input
        bytes memory rlpBlockHeader;
        bytes memory accountProof;
        bytes memory storageProof;
        (rlpBlockHeader, accountProof, storageProof) = abi.decode(input, (bytes, bytes, bytes));

        // verify proofs and get the value
        targetStateCommitment = ProverUtils.getSlotFromBlockHeader(
            homeBlockHash, rlpBlockHeader, l1BlockPredeploy, l1BlockHashSlot, accountProof, storageProof
        );
    }

    /// @notice Get the latest parent chain block hash from the L1Block predeploy. Bytes argument is ignored.
    /// @dev    OP stack does not provide access to historical block hashes, so this function can only return the latest.
    ///
    ///         Calls to the Receiver contract could revert because proofs can become stale after the predeploy's block hash is updated.
    ///         In this case, failing calls may need to be retried with a new proof.
    ///
    ///         If the L1Block is consistently updated too frequently, calls to the Receiver may be DoS'd.
    ///         In this case, this prover contract may need to be modified to use a different source of block hashes,
    ///         such as a backup contract that calls the L1Block predeploy and caches the latest block hash.
    function getTargetStateCommitment(bytes calldata) external view returns (bytes32 targetStateCommitment) {
        if (block.chainid != homeChainId) {
            revert CallNotOnHomeChain();
        }
        return IL1Block(l1BlockPredeploy).hash();
    }

    /// @notice Verify a storage slot given a target chain block hash and a proof.
    /// @param  targetStateCommitment The block hash of the target chain.
    /// @param  input ABI encoded (bytes blockHeader, address account, uint256 slot, bytes accountProof, bytes storageProof)
    function verifyStorageSlot(bytes32 targetStateCommitment, bytes calldata input)
        external
        pure
        returns (address account, uint256 slot, bytes32 value)
    {
        // decode the input
        bytes memory rlpBlockHeader;
        bytes memory accountProof;
        bytes memory storageProof;
        (rlpBlockHeader, account, slot, accountProof, storageProof) =
            abi.decode(input, (bytes, address, uint256, bytes, bytes));

        // verify proofs and get the value
        value = ProverUtils.getSlotFromBlockHeader(
            targetStateCommitment, rlpBlockHeader, account, slot, accountProof, storageProof
        );
    }

    /// @inheritdoc IStateProver
    function version() external pure returns (uint256) {
        return 1;
    }
}
