// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {PermissionedTokensHook} from "../src/PermissionedTokensHook.sol";
import {StockToken} from "../src/StockToken.sol";
import {DclexPoolModifyLiquidityTest} from "./DclexPoolModifyLiquidityTest.sol";
import {DclexPoolSwapTest} from "./DclexPoolSwapTest.sol";
import {DclexActionsTest, Actions} from "./DclexActionsTest.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";


contract TestPermissionedTokensHook is Test, Deployers {
	using CurrencyLibrary for Currency;

	Currency ethCurrency = Currency.wrap(address(0));
    StockToken stockTokenA;
    StockToken stockTokenB;
    MockERC20 otherToken;
	Currency stockTokenACurrency;
    Currency stockTokenBCurrency;
    Currency otherTokenCurrency;

	PermissionedTokensHook hook;
    DclexPoolModifyLiquidityTest liquidityRouter;
    DclexPoolSwapTest dclexSwapRouter;
    DclexActionsTest dclexActionsTest;
    address USER = makeAddr("user");
    address OTHER_ADDRESS = makeAddr("other");
    IPoolManager.ModifyLiquidityParams addLiquidityParams;
    IPoolManager.ModifyLiquidityParams removeLiquidityParams;
    uint256 addLiquidityAmount0Delta;
    PoolKey ethTokenAPoolKey;
    PoolKey ethTokenBPoolKey;
    PoolKey tokenBTokenAPoolKey;
    PoolKey tokenBotherTokenPoolKey;
    PoolKey nonHookPoolKey;

	function setUp() public {
		deployFreshManagerAndRouters();

        uint160 flags = uint160(
            Hooks.AFTER_ADD_LIQUIDITY_FLAG |
            Hooks.AFTER_REMOVE_LIQUIDITY_FLAG |
            Hooks.AFTER_SWAP_FLAG
        );
        deployCodeTo(
            "PermissionedTokensHook.sol",
            abi.encode(manager, address(this)),
            address(flags)
        );

        hook = PermissionedTokensHook(payable(address(flags)));
        liquidityRouter = new DclexPoolModifyLiquidityTest(manager);
        dclexSwapRouter = new DclexPoolSwapTest(manager);
        dclexActionsTest = new DclexActionsTest(manager);

        stockTokenA = new StockToken("Apple", "AAPL", 18, address(hook), address(manager));
        stockTokenB = new StockToken("Tesla", "TSLA", 18, address(hook), address(manager));
        otherToken = new MockERC20("Other Token", "TOKEN", 18);
        hook.addAuthorizedToken(address(stockTokenA));
        hook.addAuthorizedToken(address(stockTokenB));
        stockTokenACurrency = Currency.wrap(address(stockTokenA));
        stockTokenBCurrency = Currency.wrap(address(stockTokenB));
        otherTokenCurrency = Currency.wrap(address(otherToken));

        vm.deal(address(this), 1000 ether);
        stockTokenA.mint(address(this), 1000 ether);
        stockTokenB.mint(address(this), 1000 ether);
        otherToken.mint(address(this), 1000 ether);
        stockTokenA.approve(address(dclexActionsTest), type(uint256).max);
        stockTokenA.approve(address(liquidityRouter), type(uint256).max);
        stockTokenA.approve(address(dclexSwapRouter), type(uint256).max);
        stockTokenB.approve(address(dclexActionsTest), type(uint256).max);
        stockTokenB.approve(address(liquidityRouter), type(uint256).max);
        stockTokenB.approve(address(dclexSwapRouter), type(uint256).max);
        otherToken.approve(address(dclexActionsTest), type(uint256).max);
        otherToken.approve(address(liquidityRouter), type(uint256).max);
        otherToken.approve(address(dclexSwapRouter), type(uint256).max);
        vm.deal(address(flags), 1);

        (ethTokenAPoolKey, ) = initPool(
            ethCurrency,
            stockTokenACurrency,
            hook,
            3000,
            SQRT_PRICE_1_1,
            ZERO_BYTES
        );
        (ethTokenBPoolKey, ) = initPool(
            ethCurrency,
            stockTokenBCurrency,
            hook,
            3000,
            SQRT_PRICE_1_1,
            ZERO_BYTES
        );
        (tokenBTokenAPoolKey, ) = initPool(
            stockTokenBCurrency,
            stockTokenACurrency,
            hook,
            3000,
            SQRT_PRICE_1_1,
            ZERO_BYTES
        );
        (tokenBotherTokenPoolKey, ) = initPool(
            stockTokenBCurrency,
            otherTokenCurrency,
            hook,
            3000,
            SQRT_PRICE_1_1,
            ZERO_BYTES
        );
        (nonHookPoolKey, ) = initPool(
            ethCurrency,
            stockTokenACurrency,
            IHooks(Constants.ADDRESS_ZERO),
            3000,
            SQRT_PRICE_1_1,
            ZERO_BYTES
        );

        (uint256 amount0Delta, uint256 amount1Delta) = LiquidityAmounts
            .getAmountsForLiquidity(
                SQRT_PRICE_1_1,
                TickMath.getSqrtPriceAtTick(-60),
                TickMath.getSqrtPriceAtTick(60),
                1 ether
            );
        addLiquidityAmount0Delta = amount0Delta;
        addLiquidityParams = IPoolManager.ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1 ether,
            salt: bytes32(0)
        });
        removeLiquidityParams = IPoolManager.ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: -1 ether,
            salt: bytes32(0)
        });
	}

    function _addLiquidity() internal {
        liquidityRouter.modifyLiquidity{value: addLiquidityAmount0Delta + 1}(
            address(this), ethTokenAPoolKey, addLiquidityParams, "", false
        );
        liquidityRouter.modifyLiquidity{value: addLiquidityAmount0Delta + 1}(
            address(this), ethTokenBPoolKey, addLiquidityParams, "", false
        );
        liquidityRouter.modifyLiquidity(
            address(this), tokenBTokenAPoolKey, addLiquidityParams, "", false
        );
        liquidityRouter.modifyLiquidity(
            address(this), tokenBotherTokenPoolKey, addLiquidityParams, "", false
        );
    }

    function test_addingLiquidityToNonHookPoolReverts() public {
        vm.expectRevert();
        liquidityRouter.modifyLiquidity{value: addLiquidityAmount0Delta + 1}(
            address(this), nonHookPoolKey, addLiquidityParams, "", false
        );
    }

    function test_addingLiquidityToHookPoolIsSuccessful() public {
        liquidityRouter.modifyLiquidity{value: addLiquidityAmount0Delta + 1}(
            address(this), ethTokenAPoolKey, addLiquidityParams, "", false
        );
    }

    function test_removingLiquidityIsAllowedWhenTakingNotClaims() public {
        _addLiquidity();
        BalanceDelta delta = liquidityRouter.modifyLiquidity(
            address(this), ethTokenAPoolKey, removeLiquidityParams, "", false
        );
    }

    function test_removingLiquidityIsRevertedWhenTakingClaims() public {
        _addLiquidity();
        vm.expectRevert();
        BalanceDelta delta = liquidityRouter.modifyLiquidity(
            address(this), ethTokenAPoolKey, removeLiquidityParams, "", true
        );
    }

    function test_addingLiquidityIsRevertedWhenTryingToMintOneClaimToken() public {
        vm.expectRevert();
        BalanceDelta delta = liquidityRouter.modifyLiquidity(
            address(this), ethTokenAPoolKey, addLiquidityParams, "", false, true
        );
    }

    function test_removingLiquidityIsRevertedWhenTryingToMintOneClaimToken() public {
        _addLiquidity();
        vm.expectRevert();
        BalanceDelta delta = liquidityRouter.modifyLiquidity(
            address(this), ethTokenAPoolKey, removeLiquidityParams, "", false, true
        );
    }

    function test_etherExactInputSwapIsIsSuccessfulWhenNotTakingClaims() public {
        _addLiquidity();
        swapRouter.swap{value: 0.001 ether}(
            ethTokenAPoolKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ""
        );
    }

    function test_etherExactInputSwapIsIsRevertedWhenTakingClaims() public {
        _addLiquidity();
        vm.expectRevert();
        swapRouter.swap{value: 0.001 ether}(
            ethTokenAPoolKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: true,
                settleUsingBurn: false
            }),
            ""
        );
    }

    function test_stockExactOutputSwapIsAllowedWhenNotTakingClaims() public {
        _addLiquidity();
        uint256 tokenBalanceBefore = stockTokenACurrency.balanceOfSelf();

        swapRouter.swap{value: 0.0011 ether}(
            ethTokenAPoolKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: 0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ""
        );
        uint256 tokenBalanceAfter = stockTokenACurrency.balanceOfSelf();
        assertEq(manager.balanceOf(address(this), stockTokenACurrency.toId()), 0);
        assertTrue(int(tokenBalanceAfter - tokenBalanceBefore) > 0);
    }

    function test_stockExactOutputSwapIsRevertedWhenTryingToMintClaimTokens() public {
        _addLiquidity();
        vm.expectRevert();
        dclexSwapRouter.swap{value: 0.0011 ether}(
            ethTokenAPoolKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: 0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            DclexPoolSwapTest.TestSettings({
                takeClaims: true,
                mintOneClaim: false
            }),
            ""
        );
    }

    function test_stockExactOutputSwapIsRevertedWhenTryingToMintOneClaimToken() public {
        _addLiquidity();
        vm.expectRevert();
        dclexSwapRouter.swap{value: 0.0011 ether}(
            ethTokenAPoolKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: 0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            DclexPoolSwapTest.TestSettings({
                takeClaims: false,
                mintOneClaim: true
            }),
            ""
        );
    }

    function test_etherExactInputSwapIsRevertedWhenTryingToMintOneClaimToken() public {
        _addLiquidity();
        vm.expectRevert();
        dclexSwapRouter.swap{value: 0.001 ether}(
            ethTokenAPoolKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            DclexPoolSwapTest.TestSettings({
                takeClaims: false,
                mintOneClaim: true
            }),
            ""
        );
    }

    function test_stockExactInputSwapIsIsSuccessfulWhenNotTakingClaims() public {
        _addLiquidity();
        dclexSwapRouter.swap(
            ethTokenAPoolKey,
            IPoolManager.SwapParams({
                zeroForOne: false,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            DclexPoolSwapTest.TestSettings({
                takeClaims: false,
                mintOneClaim: false
            }),
            ""
        );
    }

    function test_stockExactInputSwapIsIsSuccessfulWhenTakingClaims() public {
        _addLiquidity();
        dclexSwapRouter.swap(
            ethTokenAPoolKey,
            IPoolManager.SwapParams({
                zeroForOne: false,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            DclexPoolSwapTest.TestSettings({
                takeClaims: true,
                mintOneClaim: false
            }),
            ""
        );
    }

    function test_etherExactOutputSwapIsIsSuccessfulWhenNotTakingClaims() public {
        _addLiquidity();
        dclexSwapRouter.swap(
            ethTokenAPoolKey,
            IPoolManager.SwapParams({
                zeroForOne: false,
                amountSpecified: 0.001 ether,
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            DclexPoolSwapTest.TestSettings({
                takeClaims: false,
                mintOneClaim: false
            }),
            ""
        );
    }

    function test_etherExactOutputSwapIsIsSuccessfulWhenTakingClaims() public {
        _addLiquidity();
        dclexSwapRouter.swap(
            ethTokenAPoolKey,
            IPoolManager.SwapParams({
                zeroForOne: false,
                amountSpecified: 0.001 ether,
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            DclexPoolSwapTest.TestSettings({
                takeClaims: true,
                mintOneClaim: false
            }),
            ""
        );
    }

    function test_swappingTwoTimesInTheSameTransactionIsSuccessful() public {
        _addLiquidity();
        Actions[] memory actions = new Actions[](4);
        bytes[] memory params = new bytes[](4);
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: 0.001 ether,
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });
        actions[0] = Actions.SWAP;
        params[0] = abi.encode(ethTokenAPoolKey, swapParams);
        actions[1] = Actions.SWAP;
        params[1] = abi.encode(ethTokenAPoolKey, swapParams);
        actions[2] = Actions.SETTLE;
        params[2] = abi.encode(ethTokenAPoolKey.currency1, address(this), 0);
        actions[3] = Actions.TAKE;
        params[3] = abi.encode(ethTokenAPoolKey.currency0, address(this), 0);
        dclexActionsTest.executeActions(actions, params);
    }
    
    function test_swappingAndAddingLiquidityInTheSameTransactionIsSuccessful() public {
        _addLiquidity();
        Actions[] memory actions = new Actions[](4);
        bytes[] memory params = new bytes[](4);
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: 0.001 ether,
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });
        actions[0] = Actions.SWAP;
        params[0] = abi.encode(ethTokenAPoolKey, swapParams);
        actions[1] = Actions.MODIFY_LIQUIDITY;
        params[1] = abi.encode(ethTokenAPoolKey, addLiquidityParams);
        actions[2] = Actions.SETTLE;
        params[2] = abi.encode(ethTokenAPoolKey.currency0, address(this), 0);
        actions[3] = Actions.SETTLE;
        params[3] = abi.encode(ethTokenAPoolKey.currency1, address(this), 0);
        dclexActionsTest.executeActions{value: addLiquidityAmount0Delta + 1}(actions, params);
    }

    function test_addingAndRemovingLiquidityInTheSameTransactionIsSuccessful() public {
        _addLiquidity();
        Actions[] memory actions = new Actions[](4);
        bytes[] memory params = new bytes[](4);
        actions[0] = Actions.MODIFY_LIQUIDITY;
        params[0] = abi.encode(ethTokenAPoolKey, addLiquidityParams);
        actions[1] = Actions.MODIFY_LIQUIDITY;
        params[1] = abi.encode(ethTokenAPoolKey, removeLiquidityParams);
        actions[2] = Actions.SETTLE;
        params[2] = abi.encode(ethTokenAPoolKey.currency0, address(this), 0);
        actions[3] = Actions.SETTLE;
        params[3] = abi.encode(ethTokenAPoolKey.currency1, address(this), 0);
        dclexActionsTest.executeActions{value: addLiquidityAmount0Delta + 1}(actions, params);
    }

    function test_transferDirectionIsVerified() public {
        _addLiquidity();
        Actions[] memory actions = new Actions[](4);
        bytes[] memory params = new bytes[](4);
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 0.001 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        actions[0] = Actions.SWAP;
        params[0] = abi.encode(ethTokenAPoolKey, swapParams);
        actions[1] = Actions.MINT_CLAIMS;
        params[1] = abi.encode(ethTokenAPoolKey.currency1, address(this), 0.002 ether);
        actions[2] = Actions.SETTLE;
        params[2] = abi.encode(ethTokenAPoolKey.currency1, address(this), 0);
        actions[3] = Actions.SETTLE;
        params[3] = abi.encode(ethTokenAPoolKey.currency0, address(this), 0);
        vm.expectRevert();
        dclexActionsTest.executeActions{value: 0.0011 ether}(actions, params);
    }

    function test_verifyTransferCanOnlyBeCalledByStockTokenContract() public {
        _addLiquidity();
        Actions[] memory actions = new Actions[](4);
        bytes[] memory params = new bytes[](4);
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 0.001 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        actions[0] = Actions.SWAP;
        params[0] = abi.encode(ethTokenAPoolKey, swapParams);
        actions[1] = Actions.VERIFY_TRANSFER;
        params[1] = abi.encode(hook, 0.001 ether);
        actions[2] = Actions.MINT_CLAIMS;
        params[2] = abi.encode(ethTokenAPoolKey.currency1, address(this), 0.001 ether);
        actions[3] = Actions.SETTLE;
        params[3] = abi.encode(ethTokenAPoolKey.currency0, address(this), 0);
        vm.expectRevert(PermissionedTokensHook.NotAuthorizedToken.selector);
        dclexActionsTest.executeActions{value: 0.0011 ether}(actions, params);
        assertEq(manager.balanceOf(address(this), stockTokenACurrency.toId()), 0);
    }

    function test_twoSwapsWithNeutralStockTokenResultAreAllowed() public {
        _addLiquidity();
        Actions[] memory actions = new Actions[](3);
        bytes[] memory params = new bytes[](3);
        IPoolManager.SwapParams memory swap1Params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 0.001 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        IPoolManager.SwapParams memory swap2Params = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: -0.001 ether,
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });
        actions[0] = Actions.SWAP;
        params[0] = abi.encode(ethTokenAPoolKey, swap1Params);
        actions[1] = Actions.SWAP;
        params[1] = abi.encode(ethTokenAPoolKey, swap2Params);
        actions[2] = Actions.SETTLE;
        params[2] = abi.encode(ethTokenAPoolKey.currency0, address(this), 0);
        dclexActionsTest.executeActions{value: 0.0011 ether}(actions, params);
    }

    function test_settlementsWithPartialTransfersAreAllowed() public {
        _addLiquidity();
        Actions[] memory actions = new Actions[](4);
        bytes[] memory params = new bytes[](4);
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: -0.001 ether,
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });
        actions[0] = Actions.SWAP;
        params[0] = abi.encode(ethTokenAPoolKey, swapParams);
        actions[1] = Actions.TAKE;
        params[1] = abi.encode(ethTokenAPoolKey.currency0, address(this), 0);
        actions[2] = Actions.SETTLE;
        params[2] = abi.encode(ethTokenAPoolKey.currency1, address(this), 0.0005 ether);
        actions[3] = Actions.SETTLE;
        params[3] = abi.encode(ethTokenAPoolKey.currency1, address(this), 0.0005 ether);
        dclexActionsTest.executeActions(actions, params);
    }

    function test_twoSwapsWithDifferentStockTokensAreAllowed() public {
        _addLiquidity();
        Actions[] memory actions = new Actions[](5);
        bytes[] memory params = new bytes[](5);
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 0.001 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        actions[0] = Actions.SWAP;
        params[0] = abi.encode(ethTokenAPoolKey, swapParams);
        actions[1] = Actions.SWAP;
        params[1] = abi.encode(ethTokenBPoolKey, swapParams);
        actions[2] = Actions.SETTLE;
        params[2] = abi.encode(ethCurrency, address(this), 0);
        actions[3] = Actions.TAKE;
        params[3] = abi.encode(stockTokenACurrency, address(this), 0);
        actions[4] = Actions.TAKE;
        params[4] = abi.encode(stockTokenBCurrency, address(this), 0);
        dclexActionsTest.executeActions{value: 0.0021 ether}(actions, params);
    }

    function test_swappingInPoolsWithTwoStockTokensIsSuccessful() public {
        _addLiquidity();
        dclexSwapRouter.swap(
            tokenBTokenAPoolKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            DclexPoolSwapTest.TestSettings({
                takeClaims: false,
                mintOneClaim: false
            }),
            ""
        );
    }

    function test_addingAndRemovingLiquidityInPoolsWithTwoStockTokensIsSuccessful() public {
        _addLiquidity();
        Actions[] memory actions = new Actions[](4);
        bytes[] memory params = new bytes[](4);
        actions[0] = Actions.MODIFY_LIQUIDITY;
        params[0] = abi.encode(tokenBTokenAPoolKey, addLiquidityParams);
        actions[1] = Actions.MODIFY_LIQUIDITY;
        params[1] = abi.encode(tokenBTokenAPoolKey, removeLiquidityParams);
        actions[2] = Actions.SETTLE;
        params[2] = abi.encode(tokenBTokenAPoolKey.currency0, address(this), 0);
        actions[3] = Actions.SETTLE;
        params[3] = abi.encode(tokenBTokenAPoolKey.currency1, address(this), 0);
        dclexActionsTest.executeActions{value: addLiquidityAmount0Delta + 1}(actions, params);
    }

    function test_swappingInPoolsWithStockTokenAndOtherTokenIsSuccessful() public {
        _addLiquidity();
        dclexSwapRouter.swap(
            tokenBotherTokenPoolKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            DclexPoolSwapTest.TestSettings({
                takeClaims: false,
                mintOneClaim: false
            }),
            ""
        );
    }

    function test_addingAndRemovingLiquidityInPoolsWithStockTokenAndOtherTokenIsSuccessful() public {
        _addLiquidity();
        Actions[] memory actions = new Actions[](4);
        bytes[] memory params = new bytes[](4);
        actions[0] = Actions.MODIFY_LIQUIDITY;
        params[0] = abi.encode(tokenBotherTokenPoolKey, addLiquidityParams);
        actions[1] = Actions.MODIFY_LIQUIDITY;
        params[1] = abi.encode(tokenBotherTokenPoolKey, removeLiquidityParams);
        actions[2] = Actions.SETTLE;
        params[2] = abi.encode(tokenBotherTokenPoolKey.currency0, address(this), 0);
        actions[3] = Actions.SETTLE;
        params[3] = abi.encode(tokenBotherTokenPoolKey.currency1, address(this), 0);
        dclexActionsTest.executeActions{value: addLiquidityAmount0Delta + 1}(actions, params);
    }

    function test_swapsWithNeutralStockTokenResultInPoolsWithTwoStockTokensAreSuccessful() public {
        _addLiquidity();
        Actions[] memory actions = new Actions[](3);
        bytes[] memory params = new bytes[](3);
        IPoolManager.SwapParams memory swap1Params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 0.001 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        IPoolManager.SwapParams memory swap2Params = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: -0.001 ether,
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });
        actions[0] = Actions.SWAP;
        params[0] = abi.encode(ethTokenAPoolKey, swap1Params);
        actions[1] = Actions.SWAP;
        params[1] = abi.encode(ethTokenAPoolKey, swap2Params);
        actions[2] = Actions.SETTLE;
        params[2] = abi.encode(ethTokenAPoolKey.currency0, address(this), 0);
        dclexActionsTest.executeActions{value: 0.0011 ether}(actions, params);
    }
 }
