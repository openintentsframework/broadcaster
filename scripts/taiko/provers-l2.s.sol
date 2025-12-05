// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { ChildToParentProver as TaikoChildToParentProver } from "../../src/contracts/provers/taiko/ChildToParentProver.sol";
import { BlockHashProverPointer } from "../../src/contracts/BlockHashProverPointer.sol";

/// @notice Deploy ChildToParentProver on L2 (Taiko Child Chain)
/// @dev This script deploys the prover that allows reading L1 state from L2
///      Configuration is read from environment variables (source scripts/taiko/config.sh)
contract DeployL2Prover is Script {
    function run() public {
        address signalServiceL2 = vm.envAddress("L2_SIGNAL_SERVICE");
        uint256 checkpointsSlot = vm.envUint("CHECKPOINTS_SLOT");
        uint256 homeChainId = vm.envUint("L2_CHAIN_ID");
        address owner = vm.envAddress("TAIKO_DEPLOYER_ADDRESS");

        vm.startBroadcast();
        
        TaikoChildToParentProver childToParentProver = new TaikoChildToParentProver(
            signalServiceL2, 
            checkpointsSlot, 
            homeChainId
        );
        
        BlockHashProverPointer blockHashProverPointer = new BlockHashProverPointer(owner);
        blockHashProverPointer.setImplementationAddress(address(childToParentProver));
        
        vm.stopBroadcast();

        console.log("ChildToParentProver:", address(childToParentProver));
        console.log("L2ProverPointer:", address(blockHashProverPointer));
    }
}

