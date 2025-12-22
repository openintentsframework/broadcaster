// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { DeployBase } from "../DeployBase.s.sol";


import { console } from "forge-std/console.sol";
import { ParentToChildProver } from "src/contracts/provers/optimism/ParentToChildProver.sol";
import { BlockHashProverPointer } from "src/contracts/BlockHashProverPointer.sol";


contract DeployArbitrumParentToChild is DeployBase {

    function run() public {


        address anchorStateRegistry = vm.envAddress("ANCHOR_STATE_REGISTRY");
        address owner = vm.envAddress("OWNER");

        uint256 homeChainId = vm.envUint("HOME_CHAIN_ID");
        uint256 targetChainId = vm.envUint("TARGET_CHAIN_ID");

        address prover;
        address pointer;
        if(block.chainid == targetChainId){
            return;
        }
        vm.startBroadcast();
        prover = address(new ParentToChildProver(anchorStateRegistry));

        // Only deploy the pointer on the "canonical" chain, i.e., the chain where the pointer will be called from the receiver directly. 
        // The other prover deployments are copies.
        if(block.chainid == homeChainId){
            pointer = address(new BlockHashProverPointer(owner));

            // This will only work if `msg.sender` is the owner of the pointer.
            BlockHashProverPointer(pointer).setImplementationAddress(address(prover));
        }
        vm.stopBroadcast();

        if(pointer == address(0)){
            // If the pointer is not deployed, it means that this is a copy of the prover deployed in a different chain.
            _writeCopy(_chainName(homeChainId), _chainName(targetChainId), address(prover));

        }

        else {
            _writeProver(_chainName(targetChainId), address(pointer), address(prover));
        }
        
    }
}