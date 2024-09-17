// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {StockToken} from "../src/StockToken.sol";
import {MockTransferVerifier} from "./mocks/MockTransferVerifier.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

contract TestStockToken is Test {
    event Transfer(address indexed from, address indexed to, uint256 amount);
    StockToken token;
    MockTransferVerifier verifier;
    address MANAGER = makeAddr("manager");
    address USER = makeAddr("user");
    address OTHER_ADDRESS = makeAddr("other");

    function setUp() public {
        verifier = new MockTransferVerifier();
        token = new StockToken("Apple", "AAPL", 18, address(verifier), MANAGER);
        token.mint(USER, 1000 ether);
    }

    function test_transferFromToPoolManagerWhenVerifierDisallowsWillRevert() public {
        verifier.setAllowTransfers(false);
        vm.prank(USER);
        token.approve(address(this), 1);
        vm.expectRevert(StockToken.TransferNotAllowed.selector);
        token.transferFrom(USER, MANAGER, 1);
    }

    function test_transferFromToPoolManagerWhenVerifierAllowsWillSucceed() public {
        verifier.setAllowTransfers(true);
        vm.prank(USER);
        token.approve(address(this), 1);
        vm.expectEmit(address(token));
        emit Transfer(USER, MANAGER, 1);
        token.transferFrom(USER, MANAGER, 1);
    }

    function test_transferFromToOtherAddressWhenVerifierDisallowsWillSucceed() public {
        verifier.setAllowTransfers(false);
        vm.prank(USER);
        token.approve(address(this), 1);
        vm.expectEmit(address(token));
        emit Transfer(USER, OTHER_ADDRESS, 1);
        token.transferFrom(USER, OTHER_ADDRESS, 1);
    }
}
