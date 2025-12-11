// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";


import { console } from "forge-std/console.sol";
import { BufferMock } from "../../test/mocks/BufferMock.sol";
import { Receiver } from "../../src/contracts/Receiver.sol";
import { BlockHashProverPointer } from "../../src/contracts/BlockHashProverPointer.sol";
import { ChildToParentProver as ZksyncChildToParentProver } from "../../src/contracts/provers/zksync/ChildToParentProver.sol";
import {ChildToParentProver as LineaChildToParentProver} from "../../src/contracts/provers/linea/ChildToParentProver.sol";
import {ChildToParentProver as ScrollChildToParentProver} from "../../src/contracts/provers/scroll/ChildToParentProver.sol";

import {ParentToChildProver as ArbParentToChildProver} from "../../src/contracts/provers/arbitrum/ParentToChildProver.sol";


contract Deploy is Script {
    function run() public {

        address outboxAddress = 0x65f07C7D521164a4d5DaC6eB8Fac8DA067A3B78F;
        uint256 rootsSlot = 3;

        uint256 zkSyncChainId = 300;
        uint256 lineaChainId = 59141;
        uint256 scrollChainId = 534351;

        vm.startBroadcast();
        BufferMock buffer = new BufferMock();
        Receiver receiver = new Receiver();

        address prover;

        if(block.chainid == zkSyncChainId) {
            prover = address(new ZksyncChildToParentProver(address(buffer), block.chainid));
        } else if(block.chainid == lineaChainId) {
            prover = address(new LineaChildToParentProver(address(buffer), block.chainid));
        } else if(block.chainid == scrollChainId) {
            prover = address(new ScrollChildToParentProver(address(buffer), block.chainid));
        } else{
            revert("Invalid chain id");
        }

        address owner = 0x9a56fFd72F4B526c523C733F1F74197A51c495E1;

        BlockHashProverPointer blockHashProverPointer = new BlockHashProverPointer(owner);

        blockHashProverPointer.setImplementationAddress(prover);

        ArbParentToChildProver arbParentToChildProverCopy = new ArbParentToChildProver(outboxAddress, rootsSlot);

        vm.stopBroadcast();

        if(block.chainid == zkSyncChainId) {
            console.log("ZKSYNC DEPLOYED");
        }
        else if(block.chainid == lineaChainId) {
            console.log("LINEA DEPLOYED");
        }
        else if(block.chainid == scrollChainId) {
            console.log("SCROLL DEPLOYED");
        }
        console.log("Buffer deployed to:", address(buffer));
        console.log("Receiver deployed to:", address(receiver));
        console.log("BlockHashProverPointer deployed to:", address(blockHashProverPointer));
        console.log("Prover deployed to:", address(prover));
        console.log("Arb prover copy deployed to:", address(arbParentToChildProverCopy));
    }
}