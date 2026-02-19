// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BlockHashArrayBuilder} from "../BlockHashArrayBuilder.sol";
import {IBuffer} from "../interfaces/IBuffer.sol";
import {IPusher} from "../interfaces/IPusher.sol";
import {ICrossDomainMessenger} from "@eth-optimism/contracts/libraries/bridge/ICrossDomainMessenger.sol";

/// @title OPtimismPusher
/// @notice Implementation of IPusher for pushing block hashes to Optimism L2.
/// @dev This contract sends block hashes from Ethereum L1 to a OptimismBuffer contract on Optimism L2
///      via the Optimism L1CrossDomainMessenger's `sendMessage` function. The pusher must be configured
///      with the correct L1CrossDomainMessengerProxy address.
/// @custom:security-contact security@openzeppelin.com
contract OptimismPusher is BlockHashArrayBuilder, IPusher {
    /// @dev The address of the Optimism L1CrossDomainMessengerProxy contract on L1.
    address private immutable _l1CrossDomainMessengerProxy;

    /// @notice Parameters for the L2 transaction that will be executed on Optimism.
    /// @param gasLimit The gas limit for the L2 transaction.
    struct OptimismL2Transaction {
        uint32 gasLimit;
    }

    /// @notice Thrown when attempting to set an invalid L1CrossDomainMessengerProxy address.
    error InvalidL1CrossDomainMessengerProxyAddress();

    constructor(address l1CrossDomainMessengerProxy_) {
        if (l1CrossDomainMessengerProxy_ == address(0)) {
            revert InvalidL1CrossDomainMessengerProxyAddress();
        }

        _l1CrossDomainMessengerProxy = l1CrossDomainMessengerProxy_;
    }

    /// @inheritdoc IPusher
    function pushHashes(address buffer, uint256 firstBlockNumber, uint256 batchSize, bytes calldata l2TransactionData)
        external
        payable
    {
        require(buffer != address(0), InvalidBuffer(buffer));
        require(msg.value == 0, IncorrectMsgValue(0, msg.value));

        bytes32[] memory blockHashes = _buildBlockHashArray(firstBlockNumber, batchSize);
        bytes memory l2Calldata = abi.encodeCall(IBuffer.receiveHashes, (firstBlockNumber, blockHashes));

        OptimismL2Transaction memory l2Transaction = abi.decode(l2TransactionData, (OptimismL2Transaction));

        ICrossDomainMessenger(l1CrossDomainMessengerProxy()).sendMessage(buffer, l2Calldata, l2Transaction.gasLimit);

        emit BlockHashesPushed(firstBlockNumber, firstBlockNumber + batchSize - 1);
    }

    /// @notice The address of the Optimism L1CrossDomainMessengerProxy contract on L1.
    /// @return The address of the Optimism L1CrossDomainMessengerProxy contract on L1.
    function l1CrossDomainMessengerProxy() public view returns (address) {
        return _l1CrossDomainMessengerProxy;
    }
}
