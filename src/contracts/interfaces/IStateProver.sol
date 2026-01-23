// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice The IStateProver is responsible for retrieving the state commitment of its target chain given its home chain's state.
///         The home chain's state is given either by a state commitment and proof, or by the StateProver executing on the home chain.
///         A single home and target chain are fixed by the logic of this contract.
interface IStateProver {
    /// @notice Verify the state commitment of the target chain given the state commitment of the home chain and a proof.
    /// @dev    MUST revert if called on the home chain.
    ///         MUST revert if the input is invalid or the input is not sufficient to determine the state commitment.
    ///         MUST return a target chain state commitment.
    ///         MUST be pure, with 1 exception: MAY read address(this).code.
    /// @param  homeStateCommitment The state commitment of the home chain.
    /// @param  input Any necessary input to determine a target chain state commitment from the home chain state commitment.
    /// @return targetStateCommitment The state commitment of the target chain.
    function verifyTargetStateCommitment(bytes32 homeStateCommitment, bytes calldata input)
        external
        view
        returns (bytes32 targetStateCommitment);

    /// @notice Get the state commitment of the target chain. Does so by directly accessing state on the home chain.
    /// @dev    MUST revert if not called on the home chain.
    ///         MUST revert if the target chain's state commitment cannot be determined.
    ///         MUST return a target chain state commitment.
    ///         SHOULD use the input to determine a specific state commitment to return. (e.g. input could be a block number)
    ///         SHOULD NOT read from its own storage. This contract is not meant to have state.
    ///         MAY make external calls.
    /// @param  input Any necessary input to fetch a target chain state commitment.
    /// @return targetStateCommitment The state commitment of the target chain.
    function getTargetStateCommitment(bytes calldata input) external view returns (bytes32 targetStateCommitment);

    /// @notice Verify a storage slot given a target chain state commitment and a proof.
    /// @dev    This function MUST NOT assume it is being called on the home chain.
    ///         MUST revert if the input is invalid or the input is not sufficient to determine a storage slot and its value.
    ///         MUST return a storage slot and its value on the target chain.
    ///         MUST be pure, with 1 exception: MAY read address(this).code.
    ///         While messages MUST be stored in storage slots, alternative reading mechanisms may be used in some cases.
    /// @param  targetStateCommitment The state commitment of the target chain.
    /// @param  input Any necessary input to determine a single storage slot and its value.
    /// @return account The address of the account on the target chain.
    /// @return slot The storage slot of the account on the target chain.
    /// @return value The value of the storage slot.
    function verifyStorageSlot(bytes32 targetStateCommitment, bytes calldata input)
        external
        view
        returns (address account, uint256 slot, bytes32 value);

    /// @notice The version of the state commitment prover.
    /// @dev    MUST be pure, with 1 exception: MAY read address(this).code.
    function version() external pure returns (uint256);
}
