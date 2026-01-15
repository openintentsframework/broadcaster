// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IL2ScrollMessenger} from "@scroll-tech/scroll-contracts/L2/IL2ScrollMessenger.sol";

contract MockL2ScrollMessenger is IL2ScrollMessenger {
    address private _xDomainMessageSender;

    function sendMessage(address _to, uint256 _value, bytes memory _message, uint256 _gasLimit)
        external
        payable
        override
    {
        // no-op
        emit SentMessage(msg.sender, _to, _value, _message.length, _gasLimit, _message);
    }

    function sendMessage(address _to, uint256 _value, bytes memory _message, uint256 _gasLimit, address _refundAddress)
        external
        payable
        override
    {
        // no-op
        emit SentMessage(msg.sender, _to, _value, _message.length, _gasLimit, _message);
    }

    function xDomainMessageSender() external view override returns (address) {
        return _xDomainMessageSender;
    }

    function relayMessage(address from, address to, uint256 value, uint256 nonce, bytes calldata message) external {
        _xDomainMessageSender = from;

        (bool success,) = to.call{value: value}(message);

        if (success) {
            emit RelayedMessage(keccak256(message));
        } else {
            emit FailedRelayedMessage(keccak256(message));
        }

        _xDomainMessageSender = address(0);
    }
}
