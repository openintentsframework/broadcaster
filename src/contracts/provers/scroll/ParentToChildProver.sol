// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ProverUtils} from "../../libraries/ProverUtils.sol";
import {IStateProver} from "../../interfaces/IStateProver.sol";
import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";
import {IScrollChain} from "@scroll-tech/scroll-contracts/L1/rollup/IScrollChain.sol";

/// @notice Scroll implementation of a parent to child IStateProver.
/// @dev    Home chain: L1 (Ethereum). Target chain: L2 (Scroll).
///         getTargetStateCommitment reads finalized L2 state roots directly from L1's ScrollChain.
///         verifyTargetStateCommitment verifies L2 state roots via storage proof against L1's ScrollChain.
///         verifyStorageSlot verifies storage against the L2 state root using standard MPT proofs.
///
///         NOTE: Unlike other provers that return block hashes, Scroll stores STATE ROOTS directly
///         in the ScrollChain contract. The "targetStateCommitment" returned by this prover is actually
///         the L2 state root, which can be used directly for MPT verification without needing
///         the L2 block header.
contract ParentToChildProver is IStateProver {
    /// @dev Address of the ScrollChain contract on L1
    address public immutable scrollChain;

    /// @dev Storage slot where ScrollChain stores the finalizedStateRoots mapping
    ///      mapping(uint256 batchIndex => bytes32 stateRoot)
    ///      This is slot 7 in the ScrollChain contract (after upgradeable storage gaps)
    uint256 public immutable finalizedStateRootsSlot;

    /// @dev L1 chain ID (home chain where this prover reads from)
    uint256 public immutable homeChainId;

    error CallNotOnHomeChain();
    error CallOnHomeChain();
    error StateRootNotFound();

    /// @param _scrollChain Address of the ScrollChain contract on L1
    /// @param _finalizedStateRootsSlot Storage slot of the finalizedStateRoots mapping
    /// @param _homeChainId Chain ID of the home chain (L1)
    constructor(address _scrollChain, uint256 _finalizedStateRootsSlot, uint256 _homeChainId) {
        scrollChain = _scrollChain;
        finalizedStateRootsSlot = _finalizedStateRootsSlot;
        homeChainId = _homeChainId;
    }

    /// @notice Verify L2 state root using L1 ScrollChain storage proof
    /// @dev    Called on non-home chains (e.g., another L2 that has L1 block hashes)
    /// @param  homeBlockHash The L1 block hash
    /// @param  input ABI encoded (bytes rlpBlockHeader, uint256 batchIndex, bytes accountProof, bytes storageProof)
    /// @return targetStateCommitment The L2 state root stored in L1's ScrollChain (NOTE: this is a state root, not a block hash)
    function verifyTargetStateCommitment(bytes32 homeBlockHash, bytes calldata input)
        external
        view
        returns (bytes32 targetStateCommitment)
    {
        if (block.chainid == homeChainId) {
            revert CallOnHomeChain();
        }

        // Decode the input
        (bytes memory rlpBlockHeader, uint256 batchIndex, bytes memory accountProof, bytes memory storageProof) =
            abi.decode(input, (bytes, uint256, bytes, bytes));

        // Calculate the storage slot for the finalized state root
        // slot = keccak256(abi.encode(batchIndex, finalizedStateRootsSlot))
        uint256 slot = uint256(SlotDerivation.deriveMapping(bytes32(finalizedStateRootsSlot), batchIndex));

        // Verify proofs and get the L2 state root from L1's ScrollChain
        targetStateCommitment = ProverUtils.getSlotFromBlockHeader(
            homeBlockHash, rlpBlockHeader, scrollChain, slot, accountProof, storageProof
        );

        if (targetStateCommitment == bytes32(0)) {
            revert StateRootNotFound();
        }
    }

    /// @notice Get L2 state root directly from L1 ScrollChain
    /// @dev    Called on home chain (L1)
    /// @param  input ABI encoded (uint256 batchIndex)
    /// @return targetStateCommitment The L2 state root (NOTE: this is a state root, not a block hash)
    function getTargetStateCommitment(bytes calldata input) external view returns (bytes32 targetStateCommitment) {
        if (block.chainid != homeChainId) {
            revert CallNotOnHomeChain();
        }

        // Decode the input
        uint256 batchIndex = abi.decode(input, (uint256));

        // Get the state root from ScrollChain
        targetStateCommitment = IScrollChain(scrollChain).finalizedStateRoots(batchIndex);

        if (targetStateCommitment == bytes32(0)) {
            revert StateRootNotFound();
        }
    }

    /// @notice Verify a storage slot given an L2 state root and a proof
    /// @dev    Since Scroll stores state roots directly (not block hashes), we can verify
    ///         the storage proof directly against the state root without needing the block header.
    /// @param  targetStateCommitment The L2 state root (NOTE: despite the name, this is a state root)
    /// @param  input ABI encoded (address account, uint256 slot, bytes accountProof, bytes storageProof)
    /// @return account The address of the account on L2
    /// @return slot The storage slot
    /// @return value The value of the storage slot
    function verifyStorageSlot(bytes32 targetStateCommitment, bytes calldata input)
        external
        pure
        returns (address, uint256, bytes32)
    {
        // Decode the input - note: no block header needed since targetStateCommitment IS the state root
        (address account, uint256 slot, bytes memory accountProof, bytes memory storageProof) =
            abi.decode(input, (address, uint256, bytes, bytes));

        // Verify proofs directly against the state root
        // This works because ScrollChain stores state roots, not block hashes
        bytes32 value = ProverUtils.getStorageSlotFromStateRoot(
            targetStateCommitment, // This is actually the state root
            accountProof,
            storageProof,
            account,
            slot
        );

        return (account, slot, value);
    }

    /// @inheritdoc IStateProver
    function version() external pure returns (uint256) {
        return 1;
    }
}
