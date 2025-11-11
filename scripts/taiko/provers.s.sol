// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { ParentToChildProver as TaikoParentToChildProver } from "../../src/contracts/provers/taiko/ParentToChildProver.sol";
import { BlockHashProverPointer } from "../../src/contracts/BlockHashProverPointer.sol";

/// @notice Deploy ParentToChildProver on L1 (Ethereum/Taiko Parent Chain)
/// @dev This script deploys the prover that allows reading L2 state from L1
contract DeployL1Prover is Script {
    function run() public {
        // Configuration for Taiko L1
        address signalServiceL1 = 0xbB128Fd4942e8143B8dc10f38CCfeADb32544264;
        uint256 checkpointsSlot = 254;
        uint256 homeChainId = 32382; // L1 chain ID
        address owner = 0xFABB0ac9d68B0B445fB7357272Ff202C5651694a;

        vm.startBroadcast();
        
        // Deploy ParentToChildProver on L1
        TaikoParentToChildProver parentToChildProver = new TaikoParentToChildProver(
            signalServiceL1, 
            checkpointsSlot, 
            homeChainId
        );
        
        // Deploy BlockHashProverPointer on L1
        BlockHashProverPointer blockHashProverPointer = new BlockHashProverPointer(owner);
        
        // Set the implementation address
        blockHashProverPointer.setImplementationAddress(address(parentToChildProver));
        
        vm.stopBroadcast();

        console.log("=== L1 Deployment Complete ===");
        console.log("ParentToChildProver deployed to:", address(parentToChildProver));
        console.log("BlockHashProverPointer deployed to:", address(blockHashProverPointer));
        console.log("Owner:", owner);
    }
}