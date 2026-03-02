// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DeployBase} from "../DeployBase.s.sol";

import {console} from "forge-std/console.sol";
import {ChildToParentProver} from "src/contracts/provers/arbitrum/ChildToParentProver.sol";
import {StateProverPointer} from "src/contracts/StateProverPointer.sol";

contract DeployArbitrumChildToParent is DeployBase {
    function run() public {
        uint256 homeChainId = vm.envUint("HOME_CHAIN_ID");
        uint256 targetChainId = vm.envUint("TARGET_CHAIN_ID");
        address owner = vm.envAddress("OWNER");

        address prover;
        address pointer;
        if (block.chainid == targetChainId) {
            return;
        }
        vm.startBroadcast();

        if (
            (block.chainid == homeChainId && _isProverDeployed(_chainName(targetChainId)))
                || (block.chainid != homeChainId && _isCopyDeployed(_chainName(homeChainId), _chainName(targetChainId)))
        ) {
            vm.stopBroadcast();
            console.log("Prover or copy already deployed on chain ", _chainName(block.chainid));
            return;
        }

        bytes memory proverCreationCode =
            abi.encodePacked(type(ChildToParentProver).creationCode, abi.encode(homeChainId));
        prover = _deploy(proverCreationCode, bytes32(0));

        if (prover == address(0)) {
            console.log("Failed to deploy prover on chain ", _chainName(block.chainid));
            vm.stopBroadcast();
            revert DeploymentFailed();
        }

        // Only deploy the pointer on the "canonical" chain, i.e., the chain where the pointer will be called from the receiver directly.
        // The other prover deployments are copies.
        if (block.chainid == homeChainId) {
            bytes memory pointerCreationCode =
                abi.encodePacked(type(StateProverPointer).creationCode, abi.encode(owner));
            pointer = _deploy(pointerCreationCode, bytes32(targetChainId));

            if (pointer != address(0)) {
                if (StateProverPointer(pointer).implementationAddress() == address(0)) {
                    // This will only work if `msg.sender` is the owner of the pointer.
                    StateProverPointer(pointer).setImplementationAddress(address(prover));
                }
            }
        }
        vm.stopBroadcast();

        if (pointer == address(0)) {
            // If the pointer is not deployed, it means that this is a copy of the prover deployed in a different chain.
            _writeCopy(_chainName(homeChainId), _chainName(targetChainId), prover);
        }else {
            _writeProver(_chainName(targetChainId), address(pointer), address(prover));
        }
    }
}
