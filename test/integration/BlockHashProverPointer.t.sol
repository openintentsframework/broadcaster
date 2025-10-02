// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console, Test} from "forge-std/Test.sol";
import {BlockHashProverPointer} from "../../../src/contracts/BlockHashProverPointer.sol";
import {ParentToChildProver} from "../../../src/contracts/provers/arbitrum/ParentToChildProver.sol";
import {ChildToParentProver} from "../../../src/contracts/provers/arbitrum/ChildToParentProver.sol";
import {IBlockHashProver} from "../../../src/contracts/interfaces/IBlockHashProver.sol";
import {IBlockHashProverPointer} from "../../../src/contracts/interfaces/IBlockHashProverPointer.sol";
import {IOutbox} from "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import {RLP} from "@openzeppelin/contracts/utils/RLP.sol";

/// @title BlockHashProverPointerTest
/// @notice Integration tests for BlockHashProverPointer functionality
/// @dev Tests pointer management, upgrades, and integration with provers
contract BlockHashProverPointerTest is Test {
    using RLP for RLP.Encoder;

    // Test accounts
    address public owner = makeAddr("owner");
    address public nonOwner = makeAddr("nonOwner");
    address public newOwner = makeAddr("newOwner");

    // Contracts
    BlockHashProverPointer public pointer;
    ParentToChildProver public parentToChildProver;
    ChildToParentProver public childToParentProver;
    ParentToChildProver public upgradedProver;

    // Arbitrum contracts
    IOutbox public outbox = IOutbox(0x65f07C7D521164a4d5DaC6eB8Fac8DA067A3B78F);

    function setUp() public {
        // Deploy initial prover
        parentToChildProver = new ParentToChildProver(address(outbox), 3);
        childToParentProver = new ChildToParentProver();
        
        // Deploy pointer with initial implementation
        pointer = new BlockHashProverPointer(owner);
    }

    function test_initial_state() public {
        // Test initial state
        assertEq(pointer.owner(), owner);
        assertEq(pointer.implementationAddress(), address(0));
        assertEq(pointer.version(), 0);
    }

    function test_update_implementation() public {
        // Test updating implementation
        vm.prank(owner);
        pointer.updateImplementation(address(parentToChildProver));
        
        assertEq(pointer.implementationAddress(), address(parentToChildProver));
        assertEq(pointer.version(), 1);
    }

    function test_update_implementation_non_owner() public {
        // Test that non-owner cannot update implementation
        vm.prank(nonOwner);
        vm.expectRevert();
        pointer.updateImplementation(address(parentToChildProver));
    }

    function test_multiple_updates() public {
        // Test multiple updates
        vm.startPrank(owner);
        
        // First update
        pointer.updateImplementation(address(parentToChildProver));
        assertEq(pointer.version(), 1);
        
        // Second update
        pointer.updateImplementation(address(childToParentProver));
        assertEq(pointer.version(), 2);
        
        // Third update
        pointer.updateImplementation(address(parentToChildProver));
        assertEq(pointer.version(), 3);
        
        vm.stopPrank();
    }

    function test_prover_functionality_through_pointer() public {
        // Set up pointer with prover
        vm.prank(owner);
        pointer.updateImplementation(address(parentToChildProver));
        
        // Test that we can call prover functions through the pointer
        uint256 version = IBlockHashProver(address(pointer)).version();
        assertEq(version, 1);
    }

    function test_prover_upgrade_scenario() public {
        // Initial setup
        vm.prank(owner);
        pointer.updateImplementation(address(parentToChildProver));
        
        // Deploy upgraded prover
        upgradedProver = new ParentToChildProver(address(outbox), 3);
        
        // Upgrade to new prover
        vm.prank(owner);
        pointer.updateImplementation(address(upgradedProver));
        
        // Verify upgrade
        assertEq(pointer.implementationAddress(), address(upgradedProver));
        assertEq(pointer.version(), 2);
        
        // Test that new prover works
        uint256 version = IBlockHashProver(address(pointer)).version();
        assertEq(version, 1); // Prover version, not pointer version
    }

    function test_zero_address_implementation() public {
        // Test updating to zero address
        vm.prank(owner);
        vm.expectRevert();
        pointer.updateImplementation(address(0));
    }

    function test_same_implementation_update() public {
        // Set initial implementation
        vm.prank(owner);
        pointer.updateImplementation(address(parentToChildProver));
        
        // Try to update to same implementation
        vm.prank(owner);
        pointer.updateImplementation(address(parentToChildProver));
        
        // Version should still increment
        assertEq(pointer.version(), 2);
    }

    function test_pointer_interface_compliance() public {
        // Test that pointer implements IBlockHashProverPointer
        assertTrue(address(pointer).code.length > 0);
        
        // Test interface functions
        assertEq(pointer.owner(), owner);
        assertEq(pointer.implementationAddress(), address(0));
        assertEq(pointer.version(), 0);
    }

    function test_prover_interface_compliance() public {
        // Set up pointer
        vm.prank(owner);
        pointer.updateImplementation(address(parentToChildProver));
        
        // Test that pointer can be used as IBlockHashProver
        IBlockHashProver prover = IBlockHashProver(address(pointer));
        
        // Test version function
        uint256 version = prover.version();
        assertEq(version, 1);
    }

    function test_gas_consumption_analysis() public {
        // Measure gas for implementation update
        uint256 gasBefore = gasleft();
        vm.prank(owner);
        pointer.updateImplementation(address(parentToChildProver));
        uint256 updateGas = gasBefore - gasleft();
        
        console.log("Implementation update gas:", updateGas);
        
        // Measure gas for version check
        gasBefore = gasleft();
        uint256 version = pointer.version();
        uint256 versionGas = gasBefore - gasleft();
        
        console.log("Version check gas:", versionGas);
        
        // Ensure reasonable gas consumption
        assertTrue(updateGas < 100000, "Update gas too high");
        assertTrue(versionGas < 10000, "Version check gas too high");
    }

    function test_pointer_with_different_prover_types() public {
        // Test pointer with ParentToChildProver
        vm.prank(owner);
        pointer.updateImplementation(address(parentToChildProver));
        
        uint256 version1 = IBlockHashProver(address(pointer)).version();
        assertEq(version1, 1);
        
        // Test pointer with ChildToParentProver
        vm.prank(owner);
        pointer.updateImplementation(address(childToParentProver));
        
        uint256 version2 = IBlockHashProver(address(pointer)).version();
        assertEq(version2, 1); // Both provers have version 1
        
        // Verify pointer version incremented
        assertEq(pointer.version(), 2);
    }

    function test_pointer_state_consistency() public {
        // Test that pointer state remains consistent across operations
        vm.startPrank(owner);
        
        // Initial state
        assertEq(pointer.version(), 0);
        assertEq(pointer.implementationAddress(), address(0));
        
        // First update
        pointer.updateImplementation(address(parentToChildProver));
        assertEq(pointer.version(), 1);
        assertEq(pointer.implementationAddress(), address(parentToChildProver));
        
        // Second update
        pointer.updateImplementation(address(childToParentProver));
        assertEq(pointer.version(), 2);
        assertEq(pointer.implementationAddress(), address(childToParentProver));
        
        // Third update (back to first)
        pointer.updateImplementation(address(parentToChildProver));
        assertEq(pointer.version(), 3);
        assertEq(pointer.implementationAddress(), address(parentToChildProver));
        
        vm.stopPrank();
    }

    function test_pointer_events() public {
        // Test that events are emitted correctly
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IBlockHashProverPointer.ImplementationUpdated(address(parentToChildProver), 1);
        pointer.updateImplementation(address(parentToChildProver));
    }

    function test_pointer_upgrade_path() public {
        // Simulate a realistic upgrade path
        vm.startPrank(owner);
        
        // Deploy v1 prover
        ParentToChildProver v1Prover = new ParentToChildProver(address(outbox), 3);
        pointer.updateImplementation(address(v1Prover));
        assertEq(pointer.version(), 1);
        
        // Deploy v2 prover (simulated upgrade)
        ParentToChildProver v2Prover = new ParentToChildProver(address(outbox), 3);
        pointer.updateImplementation(address(v2Prover));
        assertEq(pointer.version(), 2);
        
        // Deploy v3 prover (another upgrade)
        ParentToChildProver v3Prover = new ParentToChildProver(address(outbox), 3);
        pointer.updateImplementation(address(v3Prover));
        assertEq(pointer.version(), 3);
        
        // Verify final state
        assertEq(pointer.implementationAddress(), address(v3Prover));
        
        vm.stopPrank();
    }

    function test_pointer_with_invalid_prover() public {
        // Test pointer with a contract that doesn't implement IBlockHashProver
        address invalidProver = address(0x1234567890123456789012345678901234567890);
        
        vm.prank(owner);
        pointer.updateImplementation(invalidProver);
        
        // This should succeed (pointer doesn't validate interface compliance)
        assertEq(pointer.implementationAddress(), invalidProver);
        
        // But calling prover functions should fail
        vm.expectRevert();
        IBlockHashProver(address(pointer)).version();
    }

    function test_pointer_owner_transfer() public {
        // Test transferring ownership
        vm.prank(owner);
        pointer.transferOwnership(newOwner);
        
        assertEq(pointer.owner(), newOwner);
        
        // Old owner should not be able to update
        vm.prank(owner);
        vm.expectRevert();
        pointer.updateImplementation(address(parentToChildProver));
        
        // New owner should be able to update
        vm.prank(newOwner);
        pointer.updateImplementation(address(parentToChildProver));
        assertEq(pointer.implementationAddress(), address(parentToChildProver));
    }
}
