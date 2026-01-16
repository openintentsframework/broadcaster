// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IMessageService} from "@linea-contracts/messaging/interfaces/IMessageService.sol";
import {IClaimMessageV1} from "@linea-contracts/messaging/interfaces/IClaimMessageV1.sol";

contract MockLineaMessageService is IMessageService, IClaimMessageV1 {
    error ZeroAddressNotAllowed();

    address transient TRANSIENT_MESSAGE_SENDER;

    function sendMessage(address _to, uint256 _fee, bytes calldata _calldata) external payable {
        if (_to == address(0)) {
            revert ZeroAddressNotAllowed();
        }

        if (_fee > msg.value) {
            revert ValueSentTooLow();
        }

        bytes32 messageHash = keccak256(abi.encode(msg.sender, _to, _fee, msg.value - _fee, 0, _calldata));

        emit MessageSent(msg.sender, _to, _fee, msg.value - _fee, 0, _calldata, messageHash);

        // no-op
    }

    function sender() external view returns (address) {
        return TRANSIENT_MESSAGE_SENDER;
    }

    function claimMessage(
        address _from,
        address _to,
        uint256 _fee,
        uint256 _value,
        address payable _feeRecipient,
        bytes calldata _calldata,
        uint256 _nonce
    ) external {
        TRANSIENT_MESSAGE_SENDER = _from;

        (bool callSuccess, bytes memory returnData) = _to.call{value: _value}(_calldata);
        if (!callSuccess) {
            if (returnData.length > 0) {
                assembly {
                    let data_size := mload(returnData)
                    revert(add(32, returnData), data_size)
                }
            } else {
                revert MessageSendingFailed(_to);
            }
        }

        TRANSIENT_MESSAGE_SENDER = address(0);

        bytes32 messageHash = keccak256(abi.encode(_calldata));

        emit MessageClaimed(messageHash);
    }
}
