// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {StateProverPointer} from "../src/contracts/StateProverPointer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockProver} from "./mocks/MockProver.sol";

contract StateProverPointerTest is Test {
    StateProverPointer public stateProverPointer;
    MockProver public mockProver;
    address public owner = makeAddr("owner");

    function setUp() public {
        stateProverPointer = new StateProverPointer(owner);
        mockProver = new MockProver();
    }

    function test_checkOwner() public view {
        assertEq(stateProverPointer.owner(), owner);
    }

    function test_setImplementationAddress() public {
        vm.prank(owner);
        stateProverPointer.setImplementationAddress(address(mockProver));
        assertEq(stateProverPointer.implementationAddress(), address(mockProver));
        assertEq(stateProverPointer.implementationCodeHash(), address(mockProver).codehash);
    }

    function test_setImplementationAddress_reverts_if_not_owner() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, makeAddr("notOwner")));
        stateProverPointer.setImplementationAddress(address(mockProver));
    }

    function test_setImplementationAddress_reverts_if_version_is_not_increasing() public {
        vm.prank(owner);
        stateProverPointer.setImplementationAddress(address(mockProver));
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(StateProverPointer.NonIncreasingVersion.selector, 1, 1));
        stateProverPointer.setImplementationAddress(address(mockProver));
    }

    function test_setImplementationAddress_reverts_if_implementation_address_is_invalid() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(StateProverPointer.InvalidImplementationAddress.selector));
        stateProverPointer.setImplementationAddress(address(0));
    }

    function test_setImplementationAddress_reverts_if_implementation_address_is_invalid_eoa() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(StateProverPointer.InvalidImplementationAddress.selector));
        stateProverPointer.setImplementationAddress(makeAddr("invalid"));
    }
}

