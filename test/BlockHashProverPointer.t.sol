// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {StateProverPointer} from "../src/contracts/StateProverPointer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockProver} from "./mocks/MockProver.sol";

contract StateProverPointerTest is Test {
    StateProverPointer public blockHashProverPointer;
    MockProver public mockProver;
    address public owner = makeAddr("owner");

    function setUp() public {
        blockHashProverPointer = new StateProverPointer(owner);
        mockProver = new MockProver();
    }

    function test_checkOwner() public view {
        assertEq(blockHashProverPointer.owner(), owner);
    }

    function test_setImplementationAddress() public {
        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(mockProver));
        assertEq(blockHashProverPointer.implementationAddress(), address(mockProver));
        assertEq(blockHashProverPointer.implementationCodeHash(), address(mockProver).codehash);
    }

    function test_setImplementationAddress_reverts_if_not_owner() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, makeAddr("notOwner")));
        blockHashProverPointer.setImplementationAddress(address(mockProver));
    }

    function test_setImplementationAddress_reverts_if_version_is_not_increasing() public {
        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(mockProver));
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(StateProverPointer.NonIncreasingVersion.selector, 1, 1));
        blockHashProverPointer.setImplementationAddress(address(mockProver));
    }

    function test_setImplementationAddress_reverts_if_implementation_address_is_invalid() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(StateProverPointer.InvalidImplementationAddress.selector));
        blockHashProverPointer.setImplementationAddress(address(0));
    }

    function test_setImplementationAddress_reverts_if_implementation_address_is_invalid_eoa() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(StateProverPointer.InvalidImplementationAddress.selector));
        blockHashProverPointer.setImplementationAddress(makeAddr("invalid"));
    }
}

