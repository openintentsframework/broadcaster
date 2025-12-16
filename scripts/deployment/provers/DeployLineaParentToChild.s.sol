// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { DeployBase } from "../DeployBase.s.sol";


import { console } from "forge-std/console.sol";
import { ParentToChildProver } from "src/contracts/provers/linea/ParentToChildProver.sol";
import { BlockHashProverPointer } from "src/contracts/BlockHashProverPointer.sol";


contract DeployArbitrumParentToChild is DeployBase {

    function run() public {


        address rollup = vm.envAddress("ROLLUP");
        uint256 stateRootHashesSlot = vm.envUint("STATE_ROOT_HASHES_SLOT");
        address owner = vm.envAddress("OWNER");

        uint256 homeChainId = vm.envUint("HOME_CHAIN_ID");
        uint256 targetChainId = vm.envUint("TARGET_CHAIN_ID");

        address prover;
        address pointer;
        if(block.chainid == targetChainId){
            return;
        }
        vm.startBroadcast();
        prover = address(new ParentToChildProver(rollup, stateRootHashesSlot, homeChainId));

        // Only deploy the pointer on the "canonical" chain, i.e., the chain where the pointer will be called from the receiver directly. 
        // The other prover deployments are copies.
        if(block.chainid == homeChainId){
            pointer = address(new BlockHashProverPointer(owner));

            // This will only work if `msg.sender` is the owner of the pointer.
            BlockHashProverPointer(pointer).setImplementationAddress(address(prover));
        }
        vm.stopBroadcast();

        if(pointer == address(0)){
            _writeCopy(_chainName(homeChainId), _chainName(targetChainId), address(prover));

        }

        else {
            _writeProver(_chainName(targetChainId), address(pointer), address(prover));
        }
        
    }
}