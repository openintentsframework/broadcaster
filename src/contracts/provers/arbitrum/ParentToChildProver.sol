// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ProverUtils} from "../../libraries/ProverUtils.sol";
import {IStateProver} from "../../interfaces/IStateProver.sol";
import {IOutbox} from "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";

/// @notice Arbitrum implementation of a parent to child IStateProver.
/// @dev    verifyTargetStateCommitment and getTargetStateCommitment get block hashes from the child chain's Outbox contract.
///         verifyStorageSlot is implemented to work against any Arbitrum child chain with a standard Ethereum block header and state trie.
contract ParentToChildProver is IStateProver {
    /// @dev Address of the child chain's Outbox contract
    address public immutable OUTBOX;
    /// @dev Storage slot the Outbox contract uses to store roots.
    ///      Should be set to 3 unless the outbox contract has been modified.
    ///      See https://github.com/OffchainLabs/nitro-contracts/blob/9d0e90ef588f94a9d2ffa4dc22713d91a76f57d4/src/bridge/AbsOutbox.sol#L32
    uint256 public immutable ROOTS_SLOT;

    /// @dev The chain ID of the home chain (where this prover reads from).
    uint256 public immutable HOME_CHAIN_ID;

    error CallNotOnHomeChain();
    error CallOnHomeChain();
    error TargetBlockHashNotFound();

    constructor(address _outbox, uint256 _rootsSlot, uint256 _homeChainId) {
        OUTBOX = _outbox;
        ROOTS_SLOT = _rootsSlot;
        HOME_CHAIN_ID = _homeChainId;
    }

    /// @notice Verify a target chain block hash given a home chain block hash and a proof.
    /// @param  homeBlockHash The block hash of the home chain.
    /// @param  input ABI encoded (bytes blockHeader, bytes32 sendRoot, bytes accountProof, bytes storageProof)
    function verifyTargetStateCommitment(bytes32 homeBlockHash, bytes calldata input)
        external
        view
        returns (bytes32 targetStateCommitment)
    {
        if (block.chainid == HOME_CHAIN_ID) {
            revert CallOnHomeChain();
        }

        // decode the input
        (bytes memory rlpBlockHeader, bytes32 sendRoot, bytes memory accountProof, bytes memory storageProof) =
            abi.decode(input, (bytes, bytes32, bytes, bytes));

        // calculate the slot based on the provided send root
        // see: https://github.com/OffchainLabs/nitro-contracts/blob/9d0e90ef588f94a9d2ffa4dc22713d91a76f57d4/src/bridge/AbsOutbox.sol#L32
        uint256 slot = uint256(SlotDerivation.deriveMapping(bytes32(ROOTS_SLOT), sendRoot));

        // verify proofs and get the block hash
        targetStateCommitment =
            ProverUtils.getSlotFromBlockHeader(homeBlockHash, rlpBlockHeader, OUTBOX, slot, accountProof, storageProof);

        if (targetStateCommitment == bytes32(0)) {
            revert TargetBlockHashNotFound();
        }
    }

    /// @notice Get a target chain block hash given a target chain sendRoot
    /// @param  input ABI encoded (bytes32 sendRoot)
    function getTargetStateCommitment(bytes calldata input) external view returns (bytes32 targetStateCommitment) {
        if (block.chainid != HOME_CHAIN_ID) {
            revert CallNotOnHomeChain();
        }

        // decode the input
        bytes32 sendRoot = abi.decode(input, (bytes32));
        // get the target block hash from the outbox
        targetStateCommitment = IOutbox(OUTBOX).roots(sendRoot);

        if (targetStateCommitment == bytes32(0)) {
            revert TargetBlockHashNotFound();
        }
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
