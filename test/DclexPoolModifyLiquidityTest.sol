// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {PoolTestBase} from "v4-core/test/PoolTestBase.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

contract DclexPoolModifyLiquidityTest is PoolTestBase {
    using CurrencySettler for Currency;

    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

    struct CallbackData {
        address sender;
        PoolKey key;
        IPoolManager.ModifyLiquidityParams params;
        bytes hookData;
        bool settleUsingBurn;
        bool takeClaims;
        bool mintOneClaim;
    }

    function modifyLiquidity(
        address msgSender,
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        bytes memory hookData,
        bool takeClaims,
        bool mintOneClaim
    ) public payable returns (BalanceDelta delta) {
        delta = abi.decode(
            manager.unlock(abi.encode(CallbackData(msgSender, key, params, hookData, false, takeClaims, mintOneClaim))),
            (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msgSender, ethBalance);
        }
    }

    function modifyLiquidity(
        address msgSender,
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        bytes memory hookData,
        bool takeClaims
    ) public payable returns (BalanceDelta delta) {
        return modifyLiquidity(msgSender, key, params, hookData, takeClaims, false);
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));
        CallbackData memory data = abi.decode(rawData, (CallbackData));
        (BalanceDelta delta,) = manager.modifyLiquidity(data.key, data.params, data.hookData);
        (,, int256 delta0) = _fetchBalances(data.key.currency0, data.sender, address(this));
        (,, int256 delta1) = _fetchBalances(data.key.currency1, data.sender, address(this));

        if (delta0 < 0) data.key.currency0.settle(manager, data.sender, uint256(-delta0), data.settleUsingBurn);
        if (delta1 < 0) data.key.currency1.settle(manager, data.sender, uint256(-delta1), data.settleUsingBurn);
        if (data.mintOneClaim) {
            if (delta0 > 0) {
                data.key.currency0.take(manager, data.sender, 1, true);
                delta0--;
            }
            if (delta1 > 0){
                data.key.currency1.take(manager, data.sender, 1, true);
                delta1--;
            }
        }
        if (delta0 > 0) data.key.currency0.take(manager, data.sender, uint256(delta0), data.takeClaims);
        if (delta1 > 0) data.key.currency1.take(manager, data.sender, uint256(delta1), data.takeClaims);

        return abi.encode(delta);
    }
}
