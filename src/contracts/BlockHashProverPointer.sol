// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {StorageSlot} from "openzeppelin/utils/StorageSlot.sol";
import {IBlockHashProverPointer} from "./interfaces/IBlockHashProverPointer.sol";

bytes32 constant BLOCK_HASH_PROVER_POINTER_SLOT = bytes32(uint256(keccak256("eip7888.pointer.slot")) - 1);

abstract contract BlockHashProverPointer is IBlockHashProverPointer {
    address internal _implementationAddress;

    function implementationAddress() external view returns (address) {
        return _implementationAddress;
    }

    /// @notice Return the code hash of the latest version of the prover.
    function implementationCodeHash() external view returns (bytes32 codeHash) {
        codeHash = StorageSlot.getBytes32Slot(BLOCK_HASH_PROVER_POINTER_SLOT).value;
    }
}
