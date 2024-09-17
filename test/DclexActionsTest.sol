// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {TransientStateLibrary} from "v4-core/libraries/TransientStateLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {PermissionedTokensHook} from "../src/PermissionedTokensHook.sol";

enum Actions {
    MODIFY_LIQUIDITY,
    SWAP,
    SETTLE,
    TAKE,
    MINT_CLAIMS,
    VERIFY_TRANSFER
}

contract DclexActionsTest is IUnlockCallback {
    using CurrencySettler for Currency;
    using TransientStateLibrary for IPoolManager;
    IPoolManager poolManager;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    function executeActions(Actions[] memory actions, bytes[] memory params) external payable {
        poolManager.unlock(abi.encode(actions, params));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        (Actions[] memory actions, bytes[] memory params) = abi.decode(data, (Actions[], bytes[]));
        for (uint256 i = 0; i < actions.length; i++) {
            Actions action = actions[i];
            bytes memory param = params[i];
            if (action == Actions.MODIFY_LIQUIDITY) {
                _modifyLiquidity(param);
            }
            if (action == Actions.SWAP) {
                _swap(param);
            }
            if (action == Actions.SETTLE) {
                _settle(param);
            }
            if (action == Actions.TAKE) {
                _take(param);
            }
            if (action == Actions.MINT_CLAIMS) {
                _mintClaims(param);
            }
            if (action == Actions.VERIFY_TRANSFER) {
                _verifyTransfer(param);
            }
        }
    }

    function _modifyLiquidity(bytes memory params) internal {
        (PoolKey memory poolKey, IPoolManager.ModifyLiquidityParams memory modifyLiquidityParams) = abi.decode(params, (PoolKey, IPoolManager.ModifyLiquidityParams));
        poolManager.modifyLiquidity(poolKey, modifyLiquidityParams, "");
    }

    function _swap(bytes memory params) internal {
        (PoolKey memory poolKey, IPoolManager.SwapParams memory swapParams) = abi.decode(params, (PoolKey, IPoolManager.SwapParams));
        poolManager.swap(poolKey, swapParams, "");
    }

    function _settle(bytes memory params) internal {
        (Currency currency, address sender, uint256 amount) = abi.decode(params, (Currency, address, uint256));
        if (amount == 0) {
            int256 delta = poolManager.currencyDelta(address(this), currency);
            require(delta < 0, "Delta expected to be negative");
            amount = uint256(-delta);
        }
        currency.settle(poolManager, sender, amount, false);
    }

    function _take(bytes memory params) internal {
        (Currency currency, address receiver, uint256 amount) = abi.decode(params, (Currency, address, uint256));
        if (amount == 0) {
            int256 delta = poolManager.currencyDelta(address(this), currency);
            require(delta > 0, "Delta expected to be positive");
            amount = uint256(delta);
        }
        currency.take(poolManager, receiver, amount, false);
    }

    function _mintClaims(bytes memory params) internal {
        (Currency currency, address receiver, uint256 amount) = abi.decode(params, (Currency, address, uint256));
        currency.take(poolManager, receiver, amount, true);
    }

    function _verifyTransfer(bytes memory params) internal {
        (PermissionedTokensHook hook, uint256 amount) = abi.decode(params, (PermissionedTokensHook, uint256));
        hook.verifyTransfer(address(poolManager), address(hook), amount);
    }
}
