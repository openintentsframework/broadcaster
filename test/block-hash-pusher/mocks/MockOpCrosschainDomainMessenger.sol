// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ICrossDomainMessenger} from "@eth-optimism/contracts/libraries/bridge/ICrossDomainMessenger.sol";
import {IL2CrossDomainMessenger} from "@eth-optimism/contracts/L2/messaging/IL2CrossDomainMessenger.sol";

contract MockOpCrosschainDomainMessenger is IL2CrossDomainMessenger {
    address transient TRANSIENT_MESSAGE_SENDER;

    function sendMessage(address _to, bytes calldata _message, uint32 _gasLimit) external override {
        // no-op

        emit SentMessage(_to, msg.sender, _message, 0, _gasLimit);
    }

    function xDomainMessageSender() external view override returns (address) {
        return TRANSIENT_MESSAGE_SENDER;
    }

    function relayMessage(address _target, address _sender, bytes calldata _message, uint256 _messageNonce)
        external
        override
    {
        TRANSIENT_MESSAGE_SENDER = _sender;

        (bool callSuccess, bytes memory returnData) = _target.call(_message);
        if (!callSuccess) {
            revert("Message sending failed");
        }

        TRANSIENT_MESSAGE_SENDER = address(0);
    }
}
