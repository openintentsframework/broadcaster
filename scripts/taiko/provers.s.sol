// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { ParentToChildProver as TaikoParentToChildProver } from "../../src/contracts/provers/taiko/ParentToChildProver.sol";
import { BlockHashProverPointer } from "../../src/contracts/BlockHashProverPointer.sol";

/// @notice Deploy ParentToChildProver on L1 (Ethereum/Taiko Parent Chain)
/// @dev This script deploys the prover that allows reading L2 state from L1
///      Configuration is read from environment variables (source scripts/taiko/config.sh)
contract DeployL1Prover is Script {
    function run() public {
        address signalServiceL1 = vm.envAddress("L1_SIGNAL_SERVICE");
        uint256 checkpointsSlot = vm.envUint("CHECKPOINTS_SLOT");
        uint256 homeChainId = vm.envUint("L1_CHAIN_ID");
        address owner = vm.envAddress("TAIKO_DEPLOYER_ADDRESS");

        vm.startBroadcast();
        
        TaikoParentToChildProver parentToChildProver = new TaikoParentToChildProver(
            signalServiceL1, 
            checkpointsSlot, 
            homeChainId
        );
        
        BlockHashProverPointer blockHashProverPointer = new BlockHashProverPointer(owner);
        blockHashProverPointer.setImplementationAddress(address(parentToChildProver));
        
        vm.stopBroadcast();

        console.log("ParentToChildProver:", address(parentToChildProver));
        console.log("L1ProverPointer:", address(blockHashProverPointer));
    }
}