// SPDX-License-Identifier: AGPL-3.0
// Copyright 2023 Consensys Software Inc.
// Adapted for use in ERC-7888 provers

pragma solidity 0.8.30;

import {Mimc} from "./Mimc.sol";

/**
 * @title Library to perform SparseMerkleProof actions using the MiMC hashing algorithm
 * @author ConsenSys Software Inc.
 * @dev Used for verifying Linea L2 state proofs
 */
library SparseMerkleProof {
    /**
     * The Account struct represents the state of the account including the storage root, nonce, balance and codesize
     */
    struct Account {
        uint64 nonce;
        uint256 balance;
        bytes32 storageRoot;
        bytes32 mimcCodeHash;
        bytes32 keccakCodeHash;
        uint64 codeSize;
    }

    /**
     * Represents the leaf structure in both account and storage tries
     */
    struct Leaf {
        uint256 prev;
        uint256 next;
        bytes32 hKey;
        bytes32 hValue;
    }

    error WrongBytesLength(uint256 expectedLength, uint256 bytesLength);
    error LengthNotMod32();
    error MaxTreeLeafIndexExceed();
    error WrongProofLength(uint256 expectedLength, uint256 actualLength);

    uint256 internal constant TREE_DEPTH = 40;
    uint256 internal constant UNFORMATTED_PROOF_LENGTH = 42;
    bytes32 internal constant ZERO_HASH = 0x0;
    uint256 internal constant MAX_TREE_LEAF_INDEX = 2 ** TREE_DEPTH - 1;

    /**
     * @notice Formats input, computes root and returns true if it matches the provided merkle root
     * @param _rawProof Raw sparse merkle tree proof
     * @param _leafIndex Index of the leaf
     * @param _root Sparse merkle root
     * @return If the computed merkle root matches the provided one
     */
    function verifyProof(bytes[] memory _rawProof, uint256 _leafIndex, bytes32 _root) internal pure returns (bool) {
        if (_rawProof.length != UNFORMATTED_PROOF_LENGTH) {
            revert WrongProofLength(UNFORMATTED_PROOF_LENGTH, _rawProof.length);
        }

        (bytes32 nextFreeNode, bytes32 leafHash, bytes32[] memory proof) = _formatProof(_rawProof);
        return _verify(proof, leafHash, _leafIndex, _root, nextFreeNode);
    }

    /**
     * @notice Hash a value using MIMC hash
     * @param _input Value to hash
     * @return bytes32 Mimc hash
     */
    function mimcHash(bytes memory _input) internal pure returns (bytes32) {
        return Mimc.hash(_input);
    }

    /**
     * @notice Get leaf
     * @param _encodedLeaf Encoded leaf bytes (prev, next, hKey, hValue)
     * @return Leaf Formatted leaf struct
     */
    function getLeaf(bytes memory _encodedLeaf) internal pure returns (Leaf memory) {
        return _parseLeaf(_encodedLeaf);
    }

    /**
     * @notice Get account
     * @param _encodedAccountValue Encoded account value bytes
     * @return Account Formatted account struct
     */
    function getAccount(bytes memory _encodedAccountValue) internal pure returns (Account memory) {
        return _parseAccount(_encodedAccountValue);
    }

    /**
     * @notice Hash account value
     * @param _value Encoded account value bytes
     * @return bytes32 Account value hash
     */
    function hashAccountValue(bytes memory _value) internal pure returns (bytes32) {
        Account memory account = _parseAccount(_value);
        (bytes32 msb, bytes32 lsb) = _splitBytes32(account.keccakCodeHash);
        return Mimc.hash(
            abi.encode(
                account.nonce, account.balance, account.storageRoot, account.mimcCodeHash, lsb, msb, account.codeSize
            )
        );
    }

    /**
     * @notice Hash storage value
     * @param _value Encoded storage value bytes
     * @return bytes32 Storage value hash
     */
    function hashStorageValue(bytes32 _value) internal pure returns (bytes32) {
        (bytes32 msb, bytes32 lsb) = _splitBytes32(_value);
        return Mimc.hash(abi.encodePacked(lsb, msb));
    }

    /**
     * @notice Compute the hKey for an account address
     * @dev In Linea's SMT, account keys are hashed as: MiMC(address padded to 32 bytes)
     *      The address is left-padded with zeros to 32 bytes before hashing
     * @param _account The account address
     * @return bytes32 The hKey (MiMC hash of the address)
     */
    function hashAccountKey(address _account) internal pure returns (bytes32) {
        // Address is 20 bytes, pad to 32 bytes (left-padded with zeros via abi.encode)
        return Mimc.hash(abi.encode(_account));
    }

    /**
     * @notice Compute the hKey for a storage slot
     * @dev In Linea's SMT, storage keys are hashed as: MiMC(lsb || msb)
     *      The 32-byte slot is split into two 16-byte parts, reordered as lsb||msb,
     *      each padded to 32 bytes, then MiMC hashed
     * @param _slot The storage slot
     * @return bytes32 The hKey (MiMC hash of the reordered slot)
     */
    function hashStorageKey(bytes32 _slot) internal pure returns (bytes32) {
        (bytes32 msb, bytes32 lsb) = _splitBytes32(_slot);
        // Linea writes storage keys as lsb || msb (each in a 32-byte block)
        return Mimc.hash(abi.encodePacked(lsb, msb));
    }

    function _parseLeaf(bytes memory _encodedLeaf) private pure returns (Leaf memory) {
        if (_encodedLeaf.length != 128) {
            revert WrongBytesLength(128, _encodedLeaf.length);
        }
        return abi.decode(_encodedLeaf, (Leaf));
    }

    function _parseAccount(bytes memory _value) private pure returns (Account memory) {
        if (_value.length != 192) {
            revert WrongBytesLength(192, _value.length);
        }
        return abi.decode(_value, (Account));
    }

    function _splitBytes32(bytes32 _b) private pure returns (bytes32 msb, bytes32 lsb) {
        assembly {
            msb := shr(128, _b)
            lsb := and(_b, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
    }

    function _formatProof(bytes[] memory _rawProof) private pure returns (bytes32, bytes32, bytes32[] memory) {
        uint256 rawProofLength = _rawProof.length;
        uint256 formattedProofLength = rawProofLength - 2;

        bytes32[] memory proof = new bytes32[](formattedProofLength);

        if (_rawProof[0].length != 0x40) {
            revert WrongBytesLength(0x40, _rawProof[0].length);
        }

        bytes32 nextFreeNode;
        assembly {
            let data := mload(add(_rawProof, 0x20))
            nextFreeNode := mload(add(data, 0x20))
        }

        bytes32 leafHash = Mimc.hash(_rawProof[rawProofLength - 1]);

        for (uint256 i = 1; i < formattedProofLength;) {
            proof[formattedProofLength - i] = Mimc.hash(_rawProof[i]);
            unchecked {
                ++i;
            }
        }

        // If the sibling leaf (_rawProof[formattedProofLength]) is equal to zero bytes we don't hash it
        if (_isZeroBytes(_rawProof[formattedProofLength])) {
            proof[0] = ZERO_HASH;
        } else {
            proof[0] = Mimc.hash(_rawProof[formattedProofLength]);
        }

        return (nextFreeNode, leafHash, proof);
    }

    function _isZeroBytes(bytes memory _data) private pure returns (bool isZeroBytes) {
        if (_data.length % 0x20 != 0) {
            revert LengthNotMod32();
        }

        isZeroBytes = true;
        uint256 dataLength = _data.length;
        assembly {
            let dataStart := add(_data, 0x20)

            for { let currentPtr := dataStart } lt(currentPtr, add(dataStart, dataLength)) {
                currentPtr := add(currentPtr, 0x20)
            } {
                let dataWord := mload(currentPtr)

                if eq(iszero(dataWord), 0) {
                    isZeroBytes := 0
                    break
                }
            }
        }
    }

    function _verify(
        bytes32[] memory _proof,
        bytes32 _leafHash,
        uint256 _leafIndex,
        bytes32 _root,
        bytes32 _nextFreeNode
    ) private pure returns (bool) {
        bytes32 computedHash = _leafHash;
        uint256 currentIndex = _leafIndex;

        if (_leafIndex > MAX_TREE_LEAF_INDEX) {
            revert MaxTreeLeafIndexExceed();
        }

        for (uint256 height; height < TREE_DEPTH; ++height) {
            if ((currentIndex >> height) & 1 == 1) {
                computedHash = Mimc.hash(abi.encodePacked(_proof[height], computedHash));
            } else {
                computedHash = Mimc.hash(abi.encodePacked(computedHash, _proof[height]));
            }
        }

        return Mimc.hash(abi.encodePacked(_nextFreeNode, computedHash)) == _root;
    }
}
