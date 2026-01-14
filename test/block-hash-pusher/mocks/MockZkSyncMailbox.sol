// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IMailbox {
    function requestL2Transaction(
        address _contractL2,
        uint256 _l2Value,
        bytes calldata _calldata,
        uint256 _l2GasLimit,
        uint256 _l2GasPerPubdataByteLimit,
        bytes[] calldata _factoryDeps,
        address _refundRecipient
    ) external payable returns (bytes32 canonicalTxHash);
}

contract MockZkSyncMailbox is IMailbox {
    uint256 public constant REQUIRED_L2_GAS_PRICE_PER_PUBDATA = 800;

    function requestL2Transaction(
        address _contractL2,
        uint256 _l2Value,
        bytes calldata _calldata,
        uint256 _l2GasLimit,
        uint256 _l2GasPerPubdataByteLimit,
        bytes[] calldata _factoryDeps,
        address _refundRecipient
    ) external payable returns (bytes32 canonicalTxHash) {
        if (_l2GasPerPubdataByteLimit != REQUIRED_L2_GAS_PRICE_PER_PUBDATA) {
            revert();
        }

        if (_l2GasLimit == 0) {
            return bytes32(0);
        }

        return keccak256(abi.encode(block.number)); // random bytes32
    }
}
