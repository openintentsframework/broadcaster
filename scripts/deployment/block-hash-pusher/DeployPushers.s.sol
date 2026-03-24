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
        address opL1CrossDomainMessengerProxy = vm.envAddress("OPTIMISM_L1_CROSS_DOMAIN_MESSENGER_PROXY");

        uint256 lineaChainId = vm.envUint("LINEA_CHAIN_ID");
        uint256 scrollChainId = vm.envUint("SCROLL_CHAIN_ID");
        uint256 zksyncChainId = vm.envUint("ZKSYNC_CHAIN_ID");
        uint256 optimismChainId = vm.envUint("OPTIMISM_CHAIN_ID");

        string memory lineaName = _chainName(lineaChainId);
        string memory scrollName = _chainName(scrollChainId);
        string memory zksyncName = _chainName(zksyncChainId);
        string memory optimismName = _chainName(optimismChainId);

        vm.startBroadcast();
        if (!_isPusherDeployed(lineaName)) {
            LineaPusher lineaPusher = new LineaPusher(lineaRollup);
            _writePusher(lineaName, address(lineaPusher));
            _writeContractAtChain(lineaChainId, "pusher", address(lineaPusher));
        }
        if (!_isPusherDeployed(scrollName)) {
            ScrollPusher scrollPusher = new ScrollPusher(l1ScrollMessenger);
            _writePusher(scrollName, address(scrollPusher));
            _writeContractAtChain(scrollChainId, "pusher", address(scrollPusher));
        }
        if (!_isPusherDeployed(zksyncName)) {
            ZkSyncPusher zksyncPusher = new ZkSyncPusher(zkSyncDiamond);
            _writePusher(zksyncName, address(zksyncPusher));
            _writeContractAtChain(zksyncChainId, "pusher", address(zksyncPusher));
        }
        if (!_isPusherDeployed(optimismName)) {
            OptimismPusher optimismPusher = new OptimismPusher(opL1CrossDomainMessengerProxy);
            _writePusher(optimismName, address(optimismPusher));
            _writeContractAtChain(optimismChainId, "pusher", address(optimismPusher));
        }
        vm.stopBroadcast();
    }
}
