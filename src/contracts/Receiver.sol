// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IReceiver} from "./interfaces/IReceiver.sol";
import {IBlockHashProver} from "./interfaces/IBlockHashProver.sol";
import {IBlockHashProverPointer} from "./interfaces/IBlockHashProverPointer.sol";
import {BLOCK_HASH_PROVER_POINTER_SLOT} from "./BlockHashProverPointer.sol";

/// @title Receiver
/// @notice Verifies broadcast messages from remote chains using cryptographic storage proofs
/// @dev This contract enables cross-chain message verification by:
///      1. Maintaining local copies of BlockHashProver contracts for different chains
///      2. Using these provers to verify storage proofs from remote Broadcaster contracts
///      3. Following a proof route that can span multiple chain hops
///      The verification process ensures that a message was actually broadcast on a remote chain
///      at a specific timestamp without requiring trust in intermediaries.
contract Receiver is IReceiver {
    mapping(bytes32 blockHashProverPointerId => IBlockHashProver blockHashProverCopy) private _blockHashProverCopies;

    error InvalidRouteLength();
    error EmptyRoute();
    error ProverCopyNotFound();
    error MessageNotFound();
    error WrongMessageSlot();
    error WrongBlockHashProverPointerSlot();
    error DifferentCodeHash();
    error NewerProverVersion();

    /// @notice Verifies that a message was broadcast on a remote chain
    /// @dev This function uses a chain of BlockHashProvers to verify a storage proof that demonstrates
    ///      a message was broadcast. The verification route can span multiple chains, with each hop
    ///      proving the next chain's state. The function verifies:
    ///      1. The storage slot matches the expected slot for (message, publisher)
    ///      2. The slot value is non-zero (message was broadcast)
    ///      3. The entire proof chain is valid
    /// @param broadcasterReadArgs Contains the route (chain of addresses), BlockHashProver inputs for each hop,
    ///                             and the final storage proof for the broadcaster contract
    /// @param message The 32-byte message that was allegedly broadcast
    /// @param publisher The address that allegedly broadcast the message
    /// @return broadcasterId A unique identifier for the remote broadcaster contract (accumulated hash of route + account)
    /// @return timestamp The block timestamp when the message was broadcast on the remote chain
    /// @custom:throws MessageNotFound if the storage slot value is zero (message not broadcast)
    /// @custom:throws WrongMessageSlot if the proven slot doesn't match the expected slot for (message, publisher)
    function verifyBroadcastMessage(RemoteReadArgs calldata broadcasterReadArgs, bytes32 message, address publisher)
        external
        view
        returns (bytes32 broadcasterId, uint256 timestamp)
    {
        uint256 messageSlot;
        bytes32 slotValue;

        (broadcasterId, messageSlot, slotValue) = _readRemoteSlot(broadcasterReadArgs);

        if (slotValue == 0) {
            revert MessageNotFound();
        }

        uint256 expectedMessageSlot = uint256(keccak256(abi.encode(message, publisher)));
        if (messageSlot != expectedMessageSlot) {
            revert WrongMessageSlot();
        }

        timestamp = uint256(slotValue);
    }

    /// @notice Updates the local copy of a BlockHashProver for a specific remote chain
    /// @dev This function verifies and stores a local copy of a BlockHashProver contract from a remote chain.
    ///      The verification process ensures:
    ///      1. The provided proof reads from the correct storage slot (BLOCK_HASH_PROVER_POINTER_SLOT)
    ///      2. The code hash of the local copy matches the code hash stored in the remote pointer
    ///      3. The new version is newer than any existing local copy (version monotonicity)
    ///      This allows the Receiver to trustlessly obtain and update BlockHashProver implementations
    ///      needed for cross-chain message verification.
    /// @param bhpPointerReadArgs Contains the route and proofs to read the remote BlockHashProverPointer's storage
    /// @param bhpCopy The local deployed copy of the BlockHashProver contract
    /// @return bhpPointerId A unique identifier for the remote BlockHashProverPointer (accumulated hash of route)
    /// @custom:throws WrongBlockHashProverPointerSlot if the proof doesn't read from the expected slot
    /// @custom:throws DifferentCodeHash if the local copy's code hash doesn't match the remote pointer's stored hash
    /// @custom:throws NewerProverVersion if an existing local copy has a version >= the new copy's version
    function updateBlockHashProverCopy(RemoteReadArgs calldata bhpPointerReadArgs, IBlockHashProver bhpCopy)
        external
        returns (bytes32 bhpPointerId)
    {
        uint256 slot;
        bytes32 bhpCodeHash;
        (bhpPointerId, slot, bhpCodeHash) = _readRemoteSlot(bhpPointerReadArgs);

        if (slot != uint256(BLOCK_HASH_PROVER_POINTER_SLOT)) {
            revert WrongBlockHashProverPointerSlot();
        }

        if (address(bhpCopy).codehash != bhpCodeHash) {
            revert DifferentCodeHash();
        }

        IBlockHashProver oldProverCopy = _blockHashProverCopies[bhpPointerId];

        if (address(oldProverCopy) != address(0) && oldProverCopy.version() >= bhpCopy.version()) {
            revert NewerProverVersion();
        }

        _blockHashProverCopies[bhpPointerId] = bhpCopy;
    }

    /// @notice The BlockHashProverCopy on the local chain corresponding to the bhpPointerId
    ///         MUST return 0 if the BlockHashProverPointer does not exist.
    /// @param bhpPointerId The unique identifier of the BlockHashProverPointer.
    /// @return bhpCopy The BlockHashProver copy stored on the local chain, or address(0) if not found.
    function blockHashProverCopy(bytes32 bhpPointerId) external view returns (IBlockHashProver bhpCopy) {
        bhpCopy = _blockHashProverCopies[bhpPointerId];
    }

    function _readRemoteSlot(RemoteReadArgs calldata readArgs)
        internal
        view
        returns (bytes32 remoteAccountId, uint256 slot, bytes32 slotValue)
    {
        if (readArgs.route.length != readArgs.bhpInputs.length) {
            revert InvalidRouteLength();
        }

        if (readArgs.route.length == 0) {
            revert EmptyRoute();
        }

        IBlockHashProver prover;
        bytes32 blockHash;

        for (uint256 i = 0; i < readArgs.route.length; i++) {
            remoteAccountId = accumulator(remoteAccountId, readArgs.route[i]);

            if (i == 0) {
                prover = IBlockHashProver(IBlockHashProverPointer(readArgs.route[0]).implementationAddress());
                blockHash = prover.getTargetBlockHash(readArgs.bhpInputs[0]);
            } else {
                prover = _blockHashProverCopies[remoteAccountId];
                if (address(prover) == address(0)) {
                    revert ProverCopyNotFound();
                }

                blockHash = prover.verifyTargetBlockHash(blockHash, readArgs.bhpInputs[i]);
            }
        }

        address remoteAccount;

        (remoteAccount, slot, slotValue) = prover.verifyStorageSlot(blockHash, readArgs.storageProof);

        remoteAccountId = accumulator(remoteAccountId, remoteAccount);
    }

    function accumulator(bytes32 acc, address addr) internal pure returns (bytes32) {
        return keccak256(abi.encode(acc, addr));
    }
}
