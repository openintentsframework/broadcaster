// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LineaBuffer} from "src/contracts/block-hash-pusher/linea/LineaBuffer.sol";
import {ScrollBuffer} from "src/contracts/block-hash-pusher/scroll/ScrollBuffer.sol";
import {ZkSyncBuffer} from "src/contracts/block-hash-pusher/zksync/ZkSyncBuffer.sol";
import {OptimismBuffer} from "src/contracts/block-hash-pusher/optimism/OptimismBuffer.sol";
import {DeployBase} from "../DeployBase.s.sol";

contract DeployBuffers is DeployBase {
    function run() public {
        string memory chainType = vm.envString("CHAIN_TYPE");

        uint256 parentChainId = vm.envUint("PARENT_CHAIN_ID");
        uint256 childChainId = vm.envUint("CHILD_CHAIN_ID");
        string memory parentChain = _chainName(parentChainId);
        string memory childChain = _chainName(childChainId);

        address pusherAddress = _getPusherAddress(parentChain, childChain);
        if (pusherAddress == address(0)) {
            revert InvalidPusherAddress();
        }

        address messenger;
        address buffer;

        vm.startBroadcast();
        if (_isContractDeployed("buffer")) {
            console.log("Buffer already deployed on chain ", _chainName(block.chainid));
            return;
        }

        if (keccak256(bytes(chainType)) == keccak256(bytes("zksync"))) {
            buffer = address(new ZkSyncBuffer(pusherAddress));
        } else {
            messenger = vm.envAddress("MESSENGER");

            if (keccak256(bytes(chainType)) == keccak256(bytes("linea"))) {
                buffer = address(new LineaBuffer(messenger, pusherAddress));
            } else if (keccak256(bytes(chainType)) == keccak256(bytes("scroll"))) {
                buffer = address(new ScrollBuffer(messenger, pusherAddress));
            } else if (
                keccak256(bytes(chainType)) == keccak256(bytes("optimism"))
                    || keccak256(bytes(chainType)) == keccak256(bytes("base"))
                    || keccak256(bytes(chainType)) == keccak256(bytes("unichain"))
                    || keccak256(bytes(chainType)) == keccak256(bytes("worldchain"))
            ) {
                buffer = address(new OptimismBuffer(messenger, pusherAddress));
            } else {
                revert("Invalid chain type");
            }
        }
        vm.stopBroadcast();

        if (buffer != address(0)) {
            _writeContract("buffer", buffer);
        } else {
            console.log("Failed to deploy buffer on chain ", _chainName(block.chainid));
        }
    }
}
