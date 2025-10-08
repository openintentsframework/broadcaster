// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.30;

// import {Lib_SecureMerkleTrie} from "@eth-optimism/contracts/libraries/trie/Lib_SecureMerkleTrie.sol";
// import {Lib_RLPWriter} from "@eth-optimism/contracts/libraries/rlp/Lib_RLPWriter.sol";
// import {Lib_RLPReader} from "@eth-optimism/contracts/libraries/rlp/Lib_RLPReader.sol";
// import {console} from "forge-std/console.sol";

// /**
//  * @title MerkleTrieMock
//  * @notice Mock contract for generating test inputs for Lib_SecureMerkleTrie.get()
//  * @dev This contract provides utilities to create mock Merkle trie proofs and data
//  *      for testing purposes. It generates valid RLP-encoded proofs that can be used
//  *      with the Lib_SecureMerkleTrie library.
//  */
// contract MerkleTrieMock {
//     using Lib_RLPReader for Lib_RLPReader.RLPItem;

//     /**
//      * @notice Generates mock inputs for Lib_SecureMerkleTrie.get()
//      * @param key The key to search for (will be hashed internally by Lib_SecureMerkleTrie)
//      * @param value The value to associate with the key
//      * @param shouldExist Whether the key should exist in the trie
//      * @return _key The original key (as bytes)
//      * @return _proof RLP-encoded Merkle trie inclusion proof
//      * @return _root The root hash of the Merkle trie
//      */
//     function generateMockInputs(
//         bytes memory key,
//         bytes memory value,
//         bool shouldExist
//     ) public pure returns (bytes memory _key, bytes memory _proof, bytes32 _root) {
//         if (shouldExist) {
//             return generateExistingKeyProof(key, value);
//         } else {
//             return generateNonExistentKeyProof(key);
//         }
//     }

//     /**
//      * @notice Generates a proof for an existing key-value pair
//      * @param key The key that exists in the trie
//      * @param value The value associated with the key
//      * @return _key The original key
//      * @return _proof RLP-encoded proof for the existing key
//      * @return _root The root hash of the trie
//      */
//     function generateExistingKeyProof(bytes memory key, bytes memory value)
//         public
//         pure
//         returns (bytes memory _key, bytes memory _proof, bytes32 _root)
//     {
//         // Create a simple leaf node proof
//         // For a leaf node, we need: [path, value]
//         bytes memory leafPath = createLeafPath(key);
//         bytes memory leafValue = Lib_RLPWriter.writeBytes(value);
        
//         // Create the leaf node: [path, value]
//         bytes[] memory leafNode = new bytes[](2);
//         leafNode[0] = leafPath;
//         leafNode[1] = leafValue;
        
//         // RLP encode the leaf node
//         bytes memory encodedLeaf = Lib_RLPWriter.writeList(leafNode);
        
//         // Create the proof array with the leaf node
//         bytes[] memory proofArray = new bytes[](1);
//         proofArray[0] = encodedLeaf;
        
//         // RLP encode the entire proof
//         _proof = Lib_RLPWriter.writeList(proofArray);
        
//         // Calculate the root hash (simplified - in reality this would be more complex)
//         _root = keccak256(encodedLeaf);
        
//         _key = key;
//     }

//     /**
//      * @notice Generates a proof for a non-existent key
//      * @param key The key that doesn't exist in the trie
//      * @return _key The original key
//      * @return _proof RLP-encoded proof showing the key doesn't exist
//      * @return _root The root hash of the trie
//      */
//     function generateNonExistentKeyProof(bytes memory key)
//         public
//         pure
//         returns (bytes memory _key, bytes memory _proof, bytes32 _root)
//     {
//         // For a non-existent key, we create a proof that shows the path
//         // but ends with an empty value or a different leaf
        
//         // Create a leaf node for a different key to show the path exists
//         bytes memory differentKey = abi.encodePacked(key, bytes1(0x01));
//         bytes memory leafPath = createLeafPath(differentKey);
//         bytes memory leafValue = Lib_RLPWriter.writeBytes(abi.encodePacked("different_value"));
        
//         bytes[] memory leafNode = new bytes[](2);
//         leafNode[0] = leafPath;
//         leafNode[1] = leafValue;
        
//         bytes memory encodedLeaf = Lib_RLPWriter.writeList(leafNode);
        
//         bytes[] memory proofArray = new bytes[](1);
//         proofArray[0] = encodedLeaf;
        
//         _proof = Lib_RLPWriter.writeList(proofArray);
//         _root = keccak256(encodedLeaf);
//         _key = key;
//     }

//     /**
//      * @notice Creates a leaf path for a given key
//      * @param key The key to create a path for
//      * @return path The leaf path with appropriate prefix
//      */
//     function createLeafPath(bytes memory key) internal pure returns (bytes memory path) {
//         // Convert key to nibbles
//         bytes memory nibbles = toNibbles(key);
        
//         // Determine if we need odd or even prefix
//         uint8 prefix;
//         if (nibbles.length % 2 == 0) {
//             prefix = 0x20; // PREFIX_LEAF_EVEN
//         } else {
//             prefix = 0x30; // PREFIX_LEAF_ODD
//             // Add padding nibble for odd length
//             bytes memory paddedNibbles = new bytes(nibbles.length + 1);
//             paddedNibbles[0] = 0x00; // padding nibble
//             for (uint256 i = 0; i < nibbles.length; i++) {
//                 paddedNibbles[i + 1] = nibbles[i];
//             }
//             nibbles = paddedNibbles;
//         }
        
//         // Combine prefix with nibbles
//         path = new bytes(nibbles.length + 1);
//         path[0] = bytes1(prefix);
//         for (uint256 i = 0; i < nibbles.length; i++) {
//             path[i + 1] = nibbles[i];
//         }
//     }

//     /**
//      * @notice Converts bytes to nibbles
//      * @param data The input bytes
//      * @return nibbles The nibble representation
//      */
//     function toNibbles(bytes memory data) internal pure returns (bytes memory nibbles) {
//         nibbles = new bytes(data.length * 2);
//         for (uint256 i = 0; i < data.length; i++) {
//             nibbles[i * 2] = bytes1(uint8(data[i]) / 16);
//             nibbles[i * 2 + 1] = bytes1(uint8(data[i]) % 16);
//         }
//     }

//     /**
//      * @notice Generates mock inputs for account data retrieval
//      * @param account The account address
//      * @param accountData The account data (RLP encoded)
//      * @param stateRoot The state root hash
//      * @return _key The account key (address encoded)
//      * @return _proof RLP-encoded account proof
//      * @return _root The state root
//      */
//     function generateAccountProof(
//         address account,
//         bytes memory accountData,
//         bytes32 stateRoot
//     ) public pure returns (bytes memory _key, bytes memory _proof, bytes32 _root) {
//         _key = abi.encodePacked(account);
//         (_proof, _root) = generateExistingKeyProof(_key, accountData);
//     }

//     /**
//      * @notice Generates mock inputs for storage slot retrieval
//      * @param slot The storage slot
//      * @param slotValue The storage slot value
//      * @param storageRoot The storage root hash
//      * @return _key The slot key (slot encoded)
//      * @return _proof RLP-encoded storage proof
//      * @return _root The storage root
//      */
//     function generateStorageProof(
//         uint256 slot,
//         bytes32 slotValue,
//         bytes32 storageRoot
//     ) public pure returns (bytes memory _key, bytes memory _proof, bytes32 _root) {
//         _key = abi.encode(slot);
//         bytes memory valueBytes = abi.encodePacked(slotValue);
//         (_proof, _root) = generateExistingKeyProof(_key, valueBytes);
//     }

//     /**
//      * @notice Test function to verify the mock inputs work with Lib_SecureMerkleTrie.get()
//      * @param key The key to test
//      * @param value The expected value
//      * @param shouldExist Whether the key should exist
//      * @return success Whether the test passed
//      * @return exists Whether the key was found to exist
//      * @return returnedValue The value returned by Lib_SecureMerkleTrie.get()
//      */
//     function testMockInputs(
//         bytes memory key,
//         bytes memory value,
//         bool shouldExist
//     ) public pure returns (bool success, bool exists, bytes memory returnedValue) {
//         (bytes memory _key, bytes memory _proof, bytes32 _root) = generateMockInputs(key, value, shouldExist);
        
//         // Note: This will likely fail for non-existent keys as our mock proof
//         // is simplified and may not be a valid Merkle trie proof
//         try Lib_SecureMerkleTrie.get(_key, _proof, _root) returns (bool _exists, bytes memory _value) {
//             exists = _exists;
//             returnedValue = _value;
//             success = true;
//         } catch {
//             success = false;
//             exists = false;
//             returnedValue = "";
//         }
//     }

//     /**
//      * @notice Creates a simple branch node proof (for more complex scenarios)
//      * @param key The key to create a proof for
//      * @param value The value to store
//      * @return _key The original key
//      * @return _proof RLP-encoded branch node proof
//      * @return _root The root hash
//      */
//     function generateBranchNodeProof(bytes memory key, bytes memory value)
//         public
//         pure
//         returns (bytes memory _key, bytes memory _proof, bytes32 _root)
//     {
//         // Create a simple branch node with 17 elements (16 branches + 1 value)
//         bytes[] memory branchNode = new bytes[](17);
        
//         // Initialize all branches to empty
//         for (uint256 i = 0; i < 16; i++) {
//             branchNode[i] = Lib_RLPWriter.writeBytes("");
//         }
        
//         // Set the value at the end
//         branchNode[16] = Lib_RLPWriter.writeBytes(value);
        
//         // RLP encode the branch node
//         bytes memory encodedBranch = Lib_RLPWriter.writeList(branchNode);
        
//         // Create proof with the branch node
//         bytes[] memory proofArray = new bytes[](1);
//         proofArray[0] = encodedBranch;
        
//         _proof = Lib_RLPWriter.writeList(proofArray);
//         _root = keccak256(encodedBranch);
//         _key = key;
//     }
// }
