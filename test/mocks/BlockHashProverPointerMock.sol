// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {BlockHashProverPointer, BLOCK_HASH_PROVER_POINTER_SLOT} from "../../src/contracts/BlockHashProverPointer.sol";

contract BlockHashProverPointerMock is BlockHashProverPointer, Ownable {
    constructor(address _initialOwner) Ownable(_initialOwner) {}

    function setImplementationAddress(address _newImplementationAddress) external onlyOwner {
        _implementationAddress = _newImplementationAddress;
        _setCodeHash(_newImplementationAddress.codehash);
    }

    function _setCodeHash(bytes32 _codeHash) internal {
        StorageSlot.getBytes32Slot(BLOCK_HASH_PROVER_POINTER_SLOT).value = _codeHash;
    }
}
