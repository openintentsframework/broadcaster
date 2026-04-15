// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.30;

// import {Test, console} from "forge-std/Test.sol";
// import {ParentToChildProver} from "../../../src/contracts/provers/optimism/ParentToChildProver.sol";

// contract OptimismParentToChildProverTest is Test {

//     address public anchorGameSlot = 2;
//     address anchorStateRegistry =

//     function setUp() public {

//     }

//     function test_getTargetStateCommitment() public {

//         ParentToChildProver prover = new ParentToChildProver(address(outbox), rootSlot, proverHomeChainId);
//         bytes32 result = prover.getTargetStateCommitment(abi.encode(sendRoot));
//         bytes32 expectedTargetBlockHash = 0xa97ce065a04d2abfec36a459db323721847718d3159d51c4256d271ee3b37e42;
//         assertEq(result, expectedTargetBlockHash, "getTargetStateCommitment should return correct Optimism block hash");
//     }
// }
