// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BasePusher} from "../BasePusher.sol";


contract ZkSyncBuffer is BaseBuffer {
    constructor(address _zkSyncDiamond){
        zkSyncDiamond = _zkSyncDiamond;
    }

    function receiveHashes(uint256 firstBlockNumber, bytes32[] calldata blockHashes) external {
        _receiveHashes(firstBlockNumber, blockHashes);
    }
}
