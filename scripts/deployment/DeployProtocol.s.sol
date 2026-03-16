// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DeployBase} from "./DeployBase.s.sol";

import {console} from "forge-std/console.sol";
import {Broadcaster} from "src/contracts/Broadcaster.sol";
import {ZkSyncBroadcaster} from "src/contracts/ZkSyncBroadcaster.sol";
import {Receiver} from "src/contracts/Receiver.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

contract Deploy is DeployBase {
    function run() public {
        string memory chainType = vm.envString("CHAIN_TYPE");

        address broadcasterAddress;

        vm.startBroadcast();

        if (!_isContractDeployed("broadcaster")) {
            if (keccak256(bytes(chainType)) == keccak256(bytes("zksync"))) {
                address l1Messenger = 0x0000000000000000000000000000000000008008;
                bytes memory creationCode =
                    abi.encodePacked(type(ZkSyncBroadcaster).creationCode, abi.encode(l1Messenger));
                broadcasterAddress = _deploy(creationCode, bytes32(0));
            } else {
                bytes memory creationCode = type(Broadcaster).creationCode;
                broadcasterAddress = _deploy(creationCode, bytes32(0));
            }

            if (broadcasterAddress == address(0)) {
                console.log("Failed to deploy broadcaster on chain ", _chainName(block.chainid));
            } else {
                _writeContract("broadcaster", broadcasterAddress);
            }
        }

        if (!_isContractDeployed("receiver")) {
            bytes memory creationCode = type(Receiver).creationCode;
            address receiverAddress = _deploy(creationCode, bytes32(0));
            if (receiverAddress == address(0)) {
                console.log("Failed to deploy receiver on chain ", _chainName(block.chainid));
            } else {
                _writeContract("receiver", receiverAddress);
            }
        }

        vm.stopBroadcast();
    }
}
