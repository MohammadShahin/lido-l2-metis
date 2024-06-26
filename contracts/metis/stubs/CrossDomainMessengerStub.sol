// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.10;

import {ICrossDomainMessengerMetis} from "../interfaces/ICrossDomainMessenger.sol";


contract CrossDomainMessengerStubMetis is ICrossDomainMessengerMetis {
    address public xDomainMessageSender;
    uint256 public messageNonce;

    uint256 internal constant DEFAULT_CHAINID = 1088;

    constructor() payable {}

    function setXDomainMessageSender(address value) external {
        xDomainMessageSender = value;
    }

    function sendMessage(
        address _target,
        bytes calldata _message,
        uint32 _gasLimit
    ) external payable {
        messageNonce += 1;
        emit SentMessage(
            _target,
            msg.sender,
            _message,
            messageNonce,
            _gasLimit,
            DEFAULT_CHAINID
        );
    }

    function sendMessageViaChainId(
        uint256 _chainId,
        address _target,
        bytes calldata _message,
        uint32 _gasLimit
    ) external payable {
        messageNonce += 1;
        emit SentMessage(
            _target,
            msg.sender,
            _message,
            messageNonce,
            _gasLimit,
            _chainId
        );
    }

    function relayMessage(
        address _target,
        address, // sender
        bytes memory _message,
        uint256 // _messageNonce
    ) public {
        (bool success, ) = _target.call(_message);
        require(success, "CALL_FAILED");
    }
}
