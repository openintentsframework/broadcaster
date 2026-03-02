// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LineaPusher} from "src/contracts/block-hash-pusher/linea/LineaPusher.sol";
import {ScrollPusher} from "src/contracts/block-hash-pusher/scroll/ScrollPusher.sol";
import {ZkSyncPusher} from "src/contracts/block-hash-pusher/zksync/ZkSyncPusher.sol";
import {OptimismPusher} from "src/contracts/block-hash-pusher/optimism/OptimismPusher.sol";
import {DeployBase} from "../DeployBase.s.sol";

contract DeployPushers is DeployBase {
    function run() public {
        address lineaRollup = vm.envAddress("LINEA_ROLLUP");
        address l1ScrollMessenger = vm.envAddress("L1_SCROLL_MESSENGER");
        address zkSyncDiamond = vm.envAddress("ZKSYNC_DIAMOND");
        address opL1CrossDomainMessengerProxy = vm.envAddress("OP_L1_CROSS_DOMAIN_MESSENGER_PROXY");

        vm.startBroadcast();
        if (!_isPusherDeployed("linea-sepolia")) {
            LineaPusher lineaPusher = new LineaPusher(lineaRollup);
            _writePusher("linea-sepolia", address(lineaPusher));
        }
        if (!_isPusherDeployed("scroll-sepolia")) {
            ScrollPusher scrollPusher = new ScrollPusher(l1ScrollMessenger);
            _writePusher("scroll-sepolia", address(scrollPusher));
        }
        if (!_isPusherDeployed("zksync-sepolia")) {
            ZkSyncPusher zksyncPusher = new ZkSyncPusher(zkSyncDiamond);
            _writePusher("zksync-sepolia", address(zksyncPusher));
        }
        if (!_isPusherDeployed("optimism-sepolia")) {
            OptimismPusher optimismPusher = new OptimismPusher(opL1CrossDomainMessengerProxy);
            _writePusher("optimism-sepolia", address(optimismPusher));
        }
        vm.stopBroadcast();
    }
}
