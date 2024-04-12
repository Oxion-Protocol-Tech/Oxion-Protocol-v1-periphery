// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Currency, CurrencyLibrary} from "Oxion-Protocol-v1-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "Oxion-Protocol-v1-core/src/types/PoolId.sol";
import {PoolKey} from "Oxion-Protocol-v1-core/src/types/PoolKey.sol";
import {IOxionStorage} from "Oxion-Protocol-v1-core/src/interfaces/IOxionStorage.sol";
import {OxionStorage} from "Oxion-Protocol-v1-core/src/OxionStorage.sol";
import {IPoolManager} from "Oxion-Protocol-v1-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "Oxion-Protocol-v1-core/src/PoolManager.sol";
import {FullMath} from "Oxion-Protocol-v1-core/src/libraries/FullMath.sol";
import {PoolManagerRouter} from "Oxion-Protocol-v1-core/test/helpers/PoolManagerRouter.sol";
import {Pool} from "Oxion-Protocol-v1-core/src/libraries/Pool.sol";
import {TokenFixture} from "../helpers/TokenFixture.sol";
import {SwapRouter} from "../../src/SwapRouter.sol";
import {ISwapRouter} from "../../src/interfaces/ISwapRouter.sol";
import {PeripheryValidation} from "../../src/base/PeripheryValidation.sol";

contract SwapRouterTest is TokenFixture, Test, GasSnapshot {
    using PoolIdLibrary for PoolKey;

    IOxionStorage public oxionStorage;
    IPoolManager public poolManager;
    PoolManagerRouter public positionManager;
    ISwapRouter public router;

    PoolKey public poolKey0;
    PoolKey public poolKey1;
    PoolKey public poolKey2;

    function setUp() public {
        WETH weth = new WETH();
        oxionStorage = new OxionStorage();
        poolManager = new PoolManager(oxionStorage, 3000);
        oxionStorage.registerPoolManager(address(poolManager));

        initializeTokens();
        vm.label(Currency.unwrap(currency0), "token0");
        vm.label(Currency.unwrap(currency1), "token1");
        vm.label(Currency.unwrap(currency2), "token2");

        positionManager = new PoolManagerRouter(oxionStorage, poolManager);
        IERC20(Currency.unwrap(currency0)).approve(address(positionManager), 1000 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(positionManager), 1000 ether);
        IERC20(Currency.unwrap(currency2)).approve(address(positionManager), 1000 ether);

        router = new SwapRouter(oxionStorage, poolManager, address(weth));
        IERC20(Currency.unwrap(currency0)).approve(address(router), 1000 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 1000 ether);
        IERC20(Currency.unwrap(currency2)).approve(address(router), 1000 ether);

        poolKey0 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            poolManager: poolManager,
            fee: uint24(500)
        });
        // price 100
        uint160 sqrtPriceX96_100 = uint160(10 * FullMath.Q96);
        poolManager.initialize(poolKey0, sqrtPriceX96_100);

        positionManager.modifyPosition(
            poolKey0,
            IPoolManager.ModifyLiquidityParams({tickLower: 46050, tickUpper: 46060, liquidityDelta: 1e4 ether})
        );

        poolKey1 = PoolKey({
            currency0: currency1,
            currency1: currency2,
            poolManager: poolManager,
            fee: uint24(500)
        });
        // price 1
        uint160 sqrtPriceX96_1 = uint160(1 * FullMath.Q96);
        poolManager.initialize(poolKey1, sqrtPriceX96_1);

        positionManager.modifyPosition(
            poolKey1,
            IPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 1e5 ether})
        );

        vm.deal(msg.sender, 25 ether);
        poolKey2 = PoolKey({
            currency0: CurrencyLibrary.NATIVE,
            currency1: currency0,
            poolManager: poolManager,
            fee: uint24(500)
        });
        // price 1
        uint160 sqrtPriceX96_2 = uint160(1 * FullMath.Q96);

        poolManager.initialize(poolKey2, sqrtPriceX96_2);

        positionManager.modifyPosition{value: 25 ether}(
            poolKey2,
            IPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 1e5 ether})
        );

        // token0-token1 amount 0.05 ether : 5 ether i.e. price = 100
        // token1-token2 amount 25 ether : 25 ether i.e. price = 1
        // eth-token0 amount 25 ether : 25 ether i.e. price = 1
    }

    function testExactInputSingle_EthPool_zeroForOne() external {
        address alice = makeAddr("alice");
        vm.startPrank(alice);
        vm.deal(alice, 0.01 ether);

        // before assertion
        assertEq(alice.balance, 0.01 ether);
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(alice), 0 ether);

        // swap
        uint256 amountOut = router.exactInputSingle{value: 0.01 ether}(
            ISwapRouter.ExactInputSingleParams({
                poolKey: poolKey2,
                zeroForOne: true,
                recipient: alice,
                amountIn: 0.01 ether,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            }),
            block.timestamp + 100
        );

        // after assertion
        assertEq(alice.balance, 0 ether);
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(alice), amountOut);
    }

    function testExactInputSingle_EthPool_OneForZero() external {
        // pre-req: mint and approve for alice
        address alice = makeAddr("alice");
        vm.startPrank(alice);
        MockERC20(Currency.unwrap(currency0)).mint(alice, 0.01 ether);
        IERC20(Currency.unwrap(currency0)).approve(address(router), 0.01 ether);

        // before assertion
        assertEq(alice.balance, 0 ether);
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(alice), 0.01 ether);

        // swap
        uint256 amountOut = router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                poolKey: poolKey2,
                zeroForOne: false,
                recipient: alice,
                amountIn: 0.01 ether,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            }),
            block.timestamp + 100
        );

        // after assertion
        assertEq(alice.balance, amountOut);
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(alice), 0);
    }

    function testExactInputSingle_zeroForOne() external {
        uint256 amountOut = router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                poolKey: poolKey0,
                zeroForOne: true,
                recipient: makeAddr("recipient"),
                amountIn: 0.01 ether,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            }),
            block.timestamp + 100
        );

        uint256 received = IERC20(Currency.unwrap(currency1)).balanceOf(makeAddr("recipient"));
        assertEq(received, amountOut);
        // considering slippage and fee, tolerance is 1%
        assertApproxEqAbs(amountOut, 1 ether, amountOut / 100);
    }

    function testExactInputSingle_oneForZero() external {
        uint256 amountOut = router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                poolKey: poolKey0,
                zeroForOne: false,
                recipient: makeAddr("recipient"),
                amountIn: 1 ether,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            }),
            block.timestamp + 100
        );

        uint256 received = IERC20(Currency.unwrap(currency0)).balanceOf(makeAddr("recipient"));
        assertEq(received, amountOut);
        // considering slippage and fee, tolerance is 1%
        assertApproxEqAbs(amountOut, 0.01 ether, amountOut / 100);
    }

    function testExactInputSingle_expired() external {
        uint256 deadline = block.timestamp + 100;
        vm.expectRevert(abi.encodeWithSelector(PeripheryValidation.TransactionTooOld.selector));
        skip(200);
        router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                poolKey: poolKey0,
                zeroForOne: true,
                recipient: makeAddr("recipient"),
                amountIn: 0.01 ether,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            }),
            deadline
        );
    }

    function testExactInputSingle_priceNotMatch() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                Pool.InvalidSqrtPriceLimit.selector, uint160(10 * FullMath.Q96), uint160(11 * FullMath.Q96)
            )
        );
        router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                poolKey: poolKey0,
                zeroForOne: true,
                recipient: makeAddr("recipient"),
                amountIn: 0.01 ether,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: uint160(11 * FullMath.Q96)
            }),
            block.timestamp + 100
        );
    }

    function testExactInputSingle_amountOutLessThanExpected() external {
        vm.expectRevert(ISwapRouter.TooLittleReceived.selector);
        router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                poolKey: poolKey0,
                zeroForOne: true,
                recipient: makeAddr("recipient"),
                amountIn: 0.01 ether,
                amountOutMinimum: 2 ether,
                sqrtPriceLimitX96: 0
            }),
            block.timestamp + 100
        );
    }

    function testExactInputSingle_gas() external {
        snapStart("SwapRouterTest#ExactInputSingle");
        router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                poolKey: poolKey0,
                zeroForOne: true,
                recipient: makeAddr("recipient"),
                amountIn: 0.01 ether,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            }),
            block.timestamp + 100
        );
        snapEnd();
    }

    function testExactInput() external {
        ISwapRouter.PathKey[] memory path = new ISwapRouter.PathKey[](2);
        path[0] = ISwapRouter.PathKey({
            intermediateCurrency: currency1,
            fee: uint24(3000),
            poolManager: poolManager
            
        });
        path[1] = ISwapRouter.PathKey({
            intermediateCurrency: currency2,
            fee: uint24(3000),
            poolManager: poolManager
            
        });

        uint256 amountOut = router.exactInput(
            ISwapRouter.ExactInputParams({
                currencyIn: currency0,
                path: path,
                recipient: makeAddr("recipient"),
                amountIn: 0.01 ether,
                amountOutMinimum: 0
            }),
            block.timestamp + 100
        );

        uint256 received = IERC20(Currency.unwrap(currency2)).balanceOf(makeAddr("recipient"));
        assertEq(received, amountOut);
        // considering slippage and fee, tolerance is 1%
        assertApproxEqAbs(amountOut, 1 ether, amountOut / 100);
    }

    function testExactInput_expired() external {
        uint256 deadline = block.timestamp + 100;
        vm.expectRevert(abi.encodeWithSelector(PeripheryValidation.TransactionTooOld.selector));
        skip(200);
        ISwapRouter.PathKey[] memory path = new ISwapRouter.PathKey[](2);
        path[0] = ISwapRouter.PathKey({
            intermediateCurrency: currency1,
            fee: uint24(3000),
            poolManager: poolManager
            
        });
        path[1] = ISwapRouter.PathKey({
            intermediateCurrency: currency2,
            fee: uint24(3000),
            poolManager: poolManager
            
        });

        router.exactInput(
            ISwapRouter.ExactInputParams({
                currencyIn: currency0,
                path: path,
                recipient: makeAddr("recipient"),
                amountIn: 0.01 ether,
                amountOutMinimum: 0
            }),
            deadline
        );
    }

    function testExactInput_amountOutLessThanExpected() external {
        vm.expectRevert(ISwapRouter.TooLittleReceived.selector);
        ISwapRouter.PathKey[] memory path = new ISwapRouter.PathKey[](2);
        path[0] = ISwapRouter.PathKey({
            intermediateCurrency: currency1,
            fee: uint24(3000),
            poolManager: poolManager
        });
        path[1] = ISwapRouter.PathKey({
            intermediateCurrency: currency2,
            fee: uint24(3000),
            poolManager: poolManager
        });

        router.exactInput(
            ISwapRouter.ExactInputParams({
                currencyIn: currency0,
                path: path,
                recipient: makeAddr("recipient"),
                amountIn: 0.01 ether,
                amountOutMinimum: 2 ether
            }),
            block.timestamp + 100
        );
    }

    function testExactInput_gas() external {
        ISwapRouter.PathKey[] memory path = new ISwapRouter.PathKey[](2);
        path[0] = ISwapRouter.PathKey({
            intermediateCurrency: currency1,
            fee: uint24(3000),
            poolManager: poolManager
        });
        path[1] = ISwapRouter.PathKey({
            intermediateCurrency: currency2,
            fee: uint24(3000),
            poolManager: poolManager
        });

        snapStart("SwapRouterTest#ExactInput");
        router.exactInput(
            ISwapRouter.ExactInputParams({
                currencyIn: currency0,
                path: path,
                recipient: makeAddr("recipient"),
                amountIn: 0.01 ether,
                amountOutMinimum: 0
            }),
            block.timestamp + 100
        );
        snapEnd();
    }

    function testExactOutputSingle_zeroForOne() external {
        uint256 balanceBefore = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 amountIn = router.exactOutputSingle(
            ISwapRouter.ExactOutputSingleParams({
                poolKey: poolKey0,
                zeroForOne: true,
                recipient: makeAddr("recipient"),
                amountOut: 1 ether,
                amountInMaximum: 0.0101 ether,
                sqrtPriceLimitX96: 0
            }),
            block.timestamp + 100
        );
        uint256 balanceAfter = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        uint256 paid = balanceBefore - balanceAfter;
        assertEq(paid, amountIn);
        // considering slippage and fee, tolerance is 1%
        assertApproxEqAbs(amountIn, 0.01 ether, amountIn / 100);
    }

    function testExactOutputSingle_oneForZero() external {
        uint256 balanceBefore = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 amountIn = router.exactOutputSingle(
            ISwapRouter.ExactOutputSingleParams({
                poolKey: poolKey0,
                zeroForOne: false,
                recipient: makeAddr("recipient"),
                amountOut: 0.01 ether,
                amountInMaximum: 1.01 ether,
                sqrtPriceLimitX96: 0
            }),
            block.timestamp + 100
        );
        uint256 balanceAfter = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        uint256 paid = balanceBefore - balanceAfter;
        assertEq(paid, amountIn);
        // considering slippage and fee, tolerance is 1%
        assertApproxEqAbs(amountIn, 1 ether, amountIn / 100);
    }

    function testExactOutputSingle_expired() external {
        uint256 deadline = block.timestamp + 100;
        vm.expectRevert(abi.encodeWithSelector(PeripheryValidation.TransactionTooOld.selector));
        skip(200);
        router.exactOutputSingle(
            ISwapRouter.ExactOutputSingleParams({
                poolKey: poolKey0,
                zeroForOne: true,
                recipient: makeAddr("recipient"),
                amountOut: 1 ether,
                amountInMaximum: 0.0101 ether,
                sqrtPriceLimitX96: 0
            }),
            deadline
        );
    }

    function testExactOutputSingle_priceNotMatch() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                Pool.InvalidSqrtPriceLimit.selector, uint160(10 * FullMath.Q96), uint160(11 * FullMath.Q96)
            )
        );

        router.exactOutputSingle(
            ISwapRouter.ExactOutputSingleParams({
                poolKey: poolKey0,
                zeroForOne: true,
                recipient: makeAddr("recipient"),
                amountOut: 1 ether,
                amountInMaximum: 0.0101 ether,
                sqrtPriceLimitX96: uint160(11 * FullMath.Q96)
            }),
            block.timestamp + 100
        );
    }

    function testExactOutputSingle_amountOutLessThanExpected() external {
        vm.expectRevert(ISwapRouter.TooMuchRequested.selector);

        router.exactOutputSingle(
            ISwapRouter.ExactOutputSingleParams({
                poolKey: poolKey0,
                zeroForOne: true,
                recipient: makeAddr("recipient"),
                amountOut: 1 ether,
                amountInMaximum: 0.01 ether,
                sqrtPriceLimitX96: 0
            }),
            block.timestamp + 100
        );
    }

    function testExactOutputSingle_gas() external {
        snapStart("SwapRouterTest#ExactOutputSingle");
        router.exactOutputSingle(
            ISwapRouter.ExactOutputSingleParams({
                poolKey: poolKey0,
                zeroForOne: true,
                recipient: makeAddr("recipient"),
                amountOut: 1 ether,
                amountInMaximum: 0.0101 ether,
                sqrtPriceLimitX96: 0
            }),
            block.timestamp + 100
        );
        snapEnd();
    }

    // -------

    function testExactOutput() external {
        uint256 balanceBefore = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        ISwapRouter.PathKey[] memory path = new ISwapRouter.PathKey[](2);
        path[0] = ISwapRouter.PathKey({
            intermediateCurrency: currency0,
            fee: uint24(3000),
            poolManager: poolManager
        });
        path[1] = ISwapRouter.PathKey({
            intermediateCurrency: currency1,
            fee: uint24(3000),
            poolManager: poolManager
        });

        uint256 amountIn = router.exactOutput(
            ISwapRouter.ExactOutputParams({
                currencyOut: currency2,
                path: path,
                recipient: makeAddr("recipient"),
                amountOut: 1 ether,
                amountInMaximum: 0.0101 ether
            }),
            block.timestamp + 100
        );

        uint256 balanceAfter = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 paid = balanceBefore - balanceAfter;

        assertEq(paid, amountIn);
        // considering slippage and fee, tolerance is 1%
        assertApproxEqAbs(amountIn, 0.01 ether, amountIn / 100);
    }

    function testExactOutput_expired() external {
        uint256 deadline = block.timestamp + 100;
        vm.expectRevert(abi.encodeWithSelector(PeripheryValidation.TransactionTooOld.selector));
        skip(200);
        ISwapRouter.PathKey[] memory path = new ISwapRouter.PathKey[](2);
        path[0] = ISwapRouter.PathKey({
            intermediateCurrency: currency0,
            fee: uint24(3000),
            poolManager: poolManager
        });
        path[1] = ISwapRouter.PathKey({
            intermediateCurrency: currency1,
            fee: uint24(3000),
            poolManager: poolManager
        });

        router.exactOutput(
            ISwapRouter.ExactOutputParams({
                currencyOut: currency2,
                path: path,
                recipient: makeAddr("recipient"),
                amountOut: 1 ether,
                amountInMaximum: 0.0101 ether
            }),
            deadline
        );
    }

    function testExactOutput_amountInMoreThanExpected() external {
        vm.expectRevert(ISwapRouter.TooMuchRequested.selector);

        ISwapRouter.PathKey[] memory path = new ISwapRouter.PathKey[](2);
        path[0] = ISwapRouter.PathKey({
            intermediateCurrency: currency0,
            fee: uint24(3000),
            poolManager: poolManager
        });
        path[1] = ISwapRouter.PathKey({
            intermediateCurrency: currency1,
            fee: uint24(3000),
            poolManager: poolManager
        });

        router.exactOutput(
            ISwapRouter.ExactOutputParams({
                currencyOut: currency2,
                path: path,
                recipient: makeAddr("recipient"),
                amountOut: 1 ether,
                amountInMaximum: 0.01 ether
            }),
            block.timestamp + 100
        );
    }

    function testExactOutput_gas() external {
        snapStart("CLSwapRouterTest#ExactOutput");
        ISwapRouter.PathKey[] memory path = new ISwapRouter.PathKey[](2);
        path[0] = ISwapRouter.PathKey({
            intermediateCurrency: currency0,
            fee: uint24(3000),
            poolManager: poolManager
        });
        path[1] = ISwapRouter.PathKey({
            intermediateCurrency: currency1,
            fee: uint24(3000),
            poolManager: poolManager
        });

        router.exactOutput(
            ISwapRouter.ExactOutputParams({
                currencyOut: currency2,
                path: path,
                recipient: makeAddr("recipient"),
                amountOut: 1 ether,
                amountInMaximum: 0.0101 ether
            }),
            block.timestamp + 100
        );
        snapEnd();
    }

    function testSettleAndMintRefund() external {
        // transfer excess token to oxionStorage
        uint256 excessTokenAmount = 1 ether;
        address hacker = address(1);
        MockERC20(Currency.unwrap(currency0)).mint(hacker, excessTokenAmount);
        vm.startPrank(hacker);
        MockERC20(Currency.unwrap(currency0)).transfer(address(oxionStorage), excessTokenAmount);
        vm.stopPrank();

        uint256 amountOut = router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                poolKey: poolKey0,
                zeroForOne: true,
                recipient: makeAddr("recipient"),
                amountIn: 0.01 ether,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            }),
            block.timestamp + 100
        );

        uint256 received = IERC20(Currency.unwrap(currency1)).balanceOf(makeAddr("recipient"));
        assertEq(received, amountOut);
        // considering slippage and fee, tolerance is 1%
        assertApproxEqAbs(amountOut, 1 ether, amountOut / 100);

        // check currency balance in oxionStorage
        {
            uint256 currency0Balance = oxionStorage.balanceOf(address(this), currency0);
            assertEq(currency0Balance, excessTokenAmount, "Unexpected currency0 balance in oxionStorage");
        }
    }

    // allow refund of ETH
    receive() external payable {}
}
