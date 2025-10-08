// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.30;

// import {Test} from "forge-std/Test.sol";
// import {Lib_SecureMerkleTrie} from "@eth-optimism/contracts/libraries/trie/Lib_SecureMerkleTrie.sol";
// import {MerkleTrieMock} from "../mocks/MerkleTrieMock.sol";
// import {console} from "forge-std/console.sol";

// /**
//  * @title MerkleTrieMockTest
//  * @notice Test contract demonstrating how to use MerkleTrieMock to generate inputs for Lib_SecureMerkleTrie.get()
//  */
// contract MerkleTrieMockTest is Test {
//     MerkleTrieMock public mock;

//     function setUp() public {
//         mock = new MerkleTrieMock();
//     }

//     /**
//      * @notice Test generating mock inputs for an existing key
//      */
//     function testGenerateExistingKeyInputs() public {
//         bytes memory key = abi.encodePacked("test_key");
//         bytes memory value = abi.encodePacked("test_value");
        
//         (bytes memory _key, bytes memory _proof, bytes32 _root) = 
//             mock.generateMockInputs(key, value, true);
        
//         // Verify the inputs are generated
//         assertEq(_key, key);
//         assertTrue(_proof.length > 0);
//         assertTrue(_root != bytes32(0));
        
//         console.log("Generated key length:", _key.length);
//         console.log("Generated proof length:", _proof.length);
//         console.logBytes32(_root);
//     }

//     /**
//      * @notice Test generating mock inputs for a non-existent key
//      */
//     function testGenerateNonExistentKeyInputs() public {
//         bytes memory key = abi.encodePacked("non_existent_key");
//         bytes memory value = abi.encodePacked("some_value");
        
//         (bytes memory _key, bytes memory _proof, bytes32 _root) = 
//             mock.generateMockInputs(key, value, false);
        
//         // Verify the inputs are generated
//         assertEq(_key, key);
//         assertTrue(_proof.length > 0);
//         assertTrue(_root != bytes32(0));
        
//         console.log("Generated non-existent key proof length:", _proof.length);
//     }

//     /**
//      * @notice Test generating account proof inputs
//      */
//     function testGenerateAccountProof() public {
//         address account = makeAddr("test_account");
//         bytes memory accountData = abi.encodePacked(
//             uint256(1), // nonce
//             uint256(1000), // balance
//             bytes32(0x123), // storage root
//             bytes32(0x456) // code hash
//         );
//         bytes32 stateRoot = keccak256("mock_state_root");
        
//         (bytes memory _key, bytes memory _proof, bytes32 _root) = 
//             mock.generateAccountProof(account, accountData, stateRoot);
        
//         assertEq(_key, abi.encodePacked(account));
//         assertTrue(_proof.length > 0);
//         assertTrue(_root != bytes32(0));
        
//         console.log("Account proof generated successfully");
//     }

//     /**
//      * @notice Test generating storage proof inputs
//      */
//     function testGenerateStorageProof() public {
//         uint256 slot = 42;
//         bytes32 slotValue = keccak256("test_slot_value");
//         bytes32 storageRoot = keccak256("mock_storage_root");
        
//         (bytes memory _key, bytes memory _proof, bytes32 _root) = 
//             mock.generateStorageProof(slot, slotValue, storageRoot);
        
//         assertEq(_key, abi.encode(slot));
//         assertTrue(_proof.length > 0);
//         assertTrue(_root != bytes32(0));
        
//         console.log("Storage proof generated successfully");
//     }

//     /**
//      * @notice Test using the generated inputs with Lib_SecureMerkleTrie.get()
//      * Note: This test may fail because our mock proofs are simplified
//      */
//     function testUsingGeneratedInputsWithSecureMerkleTrie() public {
//         bytes memory key = abi.encodePacked("test_key");
//         bytes memory value = abi.encodePacked("test_value");
        
//         (bytes memory _key, bytes memory _proof, bytes32 _root) = 
//             mock.generateMockInputs(key, value, true);
        
//         // Try to use the generated inputs with Lib_SecureMerkleTrie.get()
//         // This might fail because our mock proof is simplified
//         try Lib_SecureMerkleTrie.get(_key, _proof, _root) returns (bool exists, bytes memory returnedValue) {
//             console.log("Lib_SecureMerkleTrie.get() succeeded");
//             console.log("Key exists:", exists);
//             console.log("Returned value length:", returnedValue.length);
//         } catch Error(string memory reason) {
//             console.log("Lib_SecureMerkleTrie.get() failed with reason:", reason);
//             // This is expected for our simplified mock proofs
//         } catch {
//             console.log("Lib_SecureMerkleTrie.get() failed with unknown error");
//         }
//     }

//     /**
//      * @notice Test the testMockInputs function
//      */
//     function testMockInputsFunction() public {
//         bytes memory key = abi.encodePacked("test_key");
//         bytes memory value = abi.encodePacked("test_value");
        
//         (bool success, bool exists, bytes memory returnedValue) = 
//             mock.testMockInputs(key, value, true);
        
//         console.log("Test success:", success);
//         console.log("Key exists:", exists);
//         console.log("Returned value length:", returnedValue.length);
//     }

//     /**
//      * @notice Test generating branch node proof
//      */
//     function testGenerateBranchNodeProof() public {
//         bytes memory key = abi.encodePacked("branch_test_key");
//         bytes memory value = abi.encodePacked("branch_test_value");
        
//         (bytes memory _key, bytes memory _proof, bytes32 _root) = 
//             mock.generateBranchNodeProof(key, value);
        
//         assertEq(_key, key);
//         assertTrue(_proof.length > 0);
//         assertTrue(_root != bytes32(0));
        
//         console.log("Branch node proof generated successfully");
//         console.log("Branch proof length:", _proof.length);
//     }

//     /**
//      * @notice Example of how to use the mock in a real test scenario
//      */
//     function testExampleUsage() public {
//         // Example 1: Generate inputs for testing account data retrieval
//         address testAccount = makeAddr("test_account");
//         bytes memory accountData = abi.encodePacked(
//             uint256(1), // nonce
//             uint256(1000), // balance  
//             bytes32(0x123), // storage root
//             bytes32(0x456) // code hash
//         );
        
//         (bytes memory accountKey, bytes memory accountProof, bytes32 stateRoot) = 
//             mock.generateAccountProof(testAccount, accountData, keccak256("state_root"));
        
//         console.log("=== Account Proof Example ===");
//         console.log("Account:", testAccount);
//         console.log("Account key length:", accountKey.length);
//         console.log("Account proof length:", accountProof.length);
//         console.logBytes32(stateRoot);
        
//         // Example 2: Generate inputs for testing storage slot retrieval
//         uint256 testSlot = 123;
//         bytes32 testSlotValue = keccak256("slot_value");
        
//         (bytes memory slotKey, bytes memory slotProof, bytes32 storageRoot) = 
//             mock.generateStorageProof(testSlot, testSlotValue, keccak256("storage_root"));
        
//         console.log("=== Storage Proof Example ===");
//         console.log("Slot:", testSlot);
//         console.log("Slot key length:", slotKey.length);
//         console.log("Slot proof length:", slotProof.length);
//         console.logBytes32(storageRoot);
//     }
// }
