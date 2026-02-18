// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title  IStateProverPointer
/// @notice Keeps the code hash of the latest version of a state commitment prover.
///         MUST store the code hash in storage slot STATE_PROVER_POINTER_SLOT.
///         Different versions of the prover MUST have the same home and target chains.
///         If the pointer's prover is updated, the new prover MUST have a higher IStateProver::version() than the old one.
///         These pointers are always referred to by their address on their home chain.
interface IStateProverPointer {
    /// @notice Emitted when the implementation address is set.
    event ImplementationAddressSet(
        uint256 indexed newVersion,
        address newImplementationAddress,
        bytes32 newCodeHash,
        address oldImplementationAddress
    );

    /// @notice Return the code hash of the latest version of the prover.
    function implementationCodeHash() external view returns (bytes32);

    /// @notice Return the address of the latest version of the prover on the home chain.
    function implementationAddress() external view returns (address);
}
