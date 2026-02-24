// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IStateProver} from "./interfaces/IStateProver.sol";
import {IStateProverPointer} from "./interfaces/IStateProverPointer.sol";

bytes32 constant STATE_PROVER_POINTER_SLOT = bytes32(uint256(keccak256("eip7888.pointer.slot")) - 1);

/// @title StateProverPointer
/// @notice Manages a versioned pointer to the latest StateProver implementation
/// @dev This contract stores the address and code hash of the current StateProver implementation.
///      It enforces version monotonicity to ensure that updates always move to newer versions.
///      The code hash is stored in a dedicated storage slot for efficient cross-chain verification.
/// @custom:security-contact security@openzeppelin.com
contract StateProverPointer is IStateProverPointer, Ownable {
    address internal _implementationAddress;

    error NonIncreasingVersion(uint256 newVersion, uint256 oldVersion);
    error InvalidImplementationAddress();

    constructor(address _initialOwner) Ownable(_initialOwner) {}

    /// @notice Returns the address of the current StateProver implementation
    /// @return The address of the current implementation contract
    function implementationAddress() public view returns (address) {
        return _implementationAddress;
    }

    /// @notice Return the code hash of the latest version of the prover.
    /// @return codeHash The code hash of the current implementation stored in the pointer slot.
    function implementationCodeHash() external view returns (bytes32 codeHash) {
        codeHash = StorageSlot.getBytes32Slot(STATE_PROVER_POINTER_SLOT).value;
    }

    /// @notice Updates the StateProver implementation to a new version
    /// @dev This function enforces version monotonicity - the new implementation must have a higher version number
    ///      than the current one. It also updates the stored code hash to match the new implementation.
    ///      Can only be called by the contract owner.
    /// @param _newImplementationAddress The address of the new StateProver implementation
    /// @custom:throws NonIncreasingVersion if the new version is not greater than the current version
    function setImplementationAddress(address _newImplementationAddress) external onlyOwner {
        if (_newImplementationAddress == address(0)) {
            revert InvalidImplementationAddress();
        }

        (bool success, bytes memory returnData) =
            _newImplementationAddress.staticcall(abi.encodeWithSelector(IStateProver.version.selector));
        if (!success || returnData.length != 32) {
            revert InvalidImplementationAddress();
        }

        uint256 newVersion = abi.decode(returnData, (uint256));

        address currentImplementationAddress = implementationAddress();
        if (currentImplementationAddress != address(0)) {
            uint256 oldVersion = IStateProver(currentImplementationAddress).version();
            if (newVersion <= oldVersion) {
                revert NonIncreasingVersion(newVersion, oldVersion);
            }
        }

        _implementationAddress = _newImplementationAddress;
        _setCodeHash(_newImplementationAddress.codehash);

        emit ImplementationAddressSet(
            newVersion, _newImplementationAddress, _newImplementationAddress.codehash, currentImplementationAddress
        );
    }

    function _setCodeHash(bytes32 _codeHash) private {
        StorageSlot.getBytes32Slot(STATE_PROVER_POINTER_SLOT).value = _codeHash;
    }
}
