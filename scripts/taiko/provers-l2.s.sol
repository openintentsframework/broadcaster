// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { ChildToParentProver as TaikoChildToParentProver } from "../../src/contracts/provers/taiko/ChildToParentProver.sol";
import { BlockHashProverPointer } from "../../src/contracts/BlockHashProverPointer.sol";

/// @notice Deploy ChildToParentProver on L2 (Taiko Child Chain)
/// @dev This script deploys the prover that allows reading L1 state from L2
contract DeployL2Prover is Script {
    function run() public {
        // Configuration for Taiko L2
        address signalServiceL2 = 0x1670010000000000000000000000000000000005;
        uint256 checkpointsSlot = 254;
        uint256 homeChainId = 167001; // L2 chain ID
        address owner = 0xFABB0ac9d68B0B445fB7357272Ff202C5651694a;

        vm.startBroadcast();
        
        // Deploy ChildToParentProver on L2
        TaikoChildToParentProver childToParentProver = new TaikoChildToParentProver(
            signalServiceL2, 
            checkpointsSlot, 
            homeChainId
        );
        
        // Deploy BlockHashProverPointer on L2
        BlockHashProverPointer blockHashProverPointer = new BlockHashProverPointer(owner);
        
        // Set the implementation address
        blockHashProverPointer.setImplementationAddress(address(childToParentProver));
        
        vm.stopBroadcast();

        console.log("=== L2 Deployment Complete ===");
        console.log("ChildToParentProver deployed to:", address(childToParentProver));
        console.log("BlockHashProverPointer deployed to:", address(blockHashProverPointer));
        console.log("Owner:", owner);
    }
}

