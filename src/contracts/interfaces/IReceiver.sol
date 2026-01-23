// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IBlockHashProver} from "./IBlockHashProver.sol";

/// @notice Reads messages from a broadcaster.
interface IReceiver {
    /// @notice Arguments required to read state of an account on a remote chain.
    /// @dev    The proof is always for a single storage slot. If the proof is for multiple slots the IReceiver MUST revert.
    ///         The proof format depends on the state commitment scheme used by the StateProver (e.g., storage proofs).
    ///         While messages MUST be stored in storage slots, alternative reading mechanisms may be used in some cases.
    /// @param  route The home chain addresses of the StateProverPointers along the route to the remote chain.
    /// @param  scpInputs The inputs to the StateProver / StateProverCopies.
    /// @param  proof Proof passed to the last StateProver / StateProverCopy
    ///               to verify a storage slot given a target state commitment.
    struct RemoteReadArgs {
        address[] route;
        bytes[] scpInputs;
        bytes proof;
    }

    /// @notice Reads a broadcast message from a remote chain.
    /// @param  broadcasterReadArgs A RemoteReadArgs object:
    ///         - The route points to the broadcasting chain
    ///         - The account proof is for the broadcaster's account
    ///         - The proof is for the message storage slot (MAY accept proofs of other transmission mechanisms (e.g., child-to-parent native bridges) if the broadcaster contract uses other transmission mechanisms)
    /// @param  message The message to read.
    /// @param  publisher The address of the publisher who broadcast the message.
    /// @return broadcasterId The broadcaster's unique identifier.
    /// @return timestamp The timestamp when the message was broadcast.
    function verifyBroadcastMessage(RemoteReadArgs calldata broadcasterReadArgs, bytes32 message, address publisher)
        external
        view
        returns (bytes32 broadcasterId, uint256 timestamp);

    /// @notice Updates the state commitment prover copy in storage.
    ///         Checks that StateProverCopy has the same code hash as stored in the StateProverPointer
    ///         Checks that the version is increasing.
    /// @param  scpPointerReadArgs A RemoteReadArgs object:
    ///         - The route points to the StateProverPointer's home chain
    ///         - The account proof is for the StateProverPointer's account
    ///         - The proof is for the STATE_PROVER_POINTER_SLOT
    /// @param  scpCopy The StateProver copy on the local chain.
    /// @return scpPointerId The ID of the StateProverPointer
    function updateStateProverCopy(RemoteReadArgs calldata scpPointerReadArgs, IStateProver scpCopy)
        external
        returns (bytes32 scpPointerId);

    /// @notice The StateProverCopy on the local chain corresponding to the scpPointerId
    ///         MUST return 0 if the StateProverPointer does not exist.
    function stateProverCopy(bytes32 scpPointerId) external view returns (IStateProver scpCopy);
}
