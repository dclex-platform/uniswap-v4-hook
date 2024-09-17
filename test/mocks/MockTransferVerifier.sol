// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TransferVerifier} from "../../src/TransferVerifier.sol";

contract MockTransferVerifier is TransferVerifier {
    bool public allowTransfers = true;

    function setAllowTransfers(bool value) public {
        allowTransfers = value;
    }

    function verifyTransfer(address from, address to, uint256 amount) public override view returns (bool) {
        return allowTransfers;
    }
}
