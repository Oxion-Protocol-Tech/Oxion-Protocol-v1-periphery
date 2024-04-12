// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 Oxion Protocol
pragma solidity ^0.8.24;

import {IOxionStorage} from "Oxion-Protocol-v1-core/src/interfaces/IOxionStorage.sol";
import {IPoolManager} from "Oxion-Protocol-v1-core/src/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "Oxion-Protocol-v1-core/src/types/Currency.sol";
import {PeripheryPayments} from "./base/PeripheryPayments.sol";
import {PeripheryValidation} from "./base/PeripheryValidation.sol";
import {PeripheryImmutableState} from "./base/PeripheryImmutableState.sol";
import {Multicall} from "./base/Multicall.sol";
import {SelfPermit} from "./SelfPermit.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {PoolKey} from "Oxion-Protocol-v1-core/src/types/PoolKey.sol";
import {BalanceDelta} from "Oxion-Protocol-v1-core/src/types/BalanceDelta.sol";
import {TickMath} from "Oxion-Protocol-v1-core/src/libraries/TickMath.sol";

contract SwapRouter is
    ISwapRouter,
    PeripheryPayments,
    PeripheryValidation,
    Multicall,
    SelfPermit
{
    using CurrencyLibrary for Currency;

    error NotOxionStorage();

    enum SwapType {
        ExactInput,
        ExactInputSingle,
        ExactOutput,
        ExactOutputSingle
    }

    struct ExactInputState {
        uint256 pathLength;
        uint128 amountOut;
        PoolKey poolKey;
        bool zeroForOne;
    }

    struct ExactOutputState {
        uint256 pathLength;
        uint128 amountIn;
        PoolKey poolKey;
        bool oneForZero;
    }

    struct SwapInfo {
        SwapType swapType;
        address msgSender;
        bytes params;
    }

    constructor(IOxionStorage _oxionStorage, IPoolManager _PoolManager, address _WETH9)
        PeripheryImmutableState(_oxionStorage, _PoolManager, _WETH9)
    {}

    modifier oxionStorageOnly() {
        if (msg.sender != address(oxionStorage)) revert NotOxionStorage();
        _;
    }

    function exactInputSingle(ExactInputSingleParams calldata params, uint256 deadline)
        external
        payable
        checkDeadline(deadline)
        returns (uint256 amountOut)
    {
        amountOut = abi.decode(
            oxionStorage.lock(abi.encode(SwapInfo(SwapType.ExactInputSingle, msg.sender, abi.encode(params)))), (uint256)
        );
    }

    function exactInput(ExactInputParams calldata params, uint256 deadline)
        external
        payable
        checkDeadline(deadline)
        returns (uint256 amountOut)
    {
        amountOut =
            abi.decode(oxionStorage.lock(abi.encode(SwapInfo(SwapType.ExactInput, msg.sender, abi.encode(params)))), (uint256));
    }

    function exactOutputSingle(ExactOutputSingleParams calldata params, uint256 deadline)
        external
        payable
        checkDeadline(deadline)
        returns (uint256 amountIn)
    {
        amountIn = abi.decode(
            oxionStorage.lock(abi.encode(SwapInfo(SwapType.ExactOutputSingle, msg.sender, abi.encode(params)))), (uint256)
        );
    }

    function exactOutput(ExactOutputParams calldata params, uint256 deadline)
        external
        payable
        checkDeadline(deadline)
        returns (uint256 amountIn)
    {
        amountIn = abi.decode(
            oxionStorage.lock(abi.encode(SwapInfo(SwapType.ExactOutput, msg.sender, abi.encode(params)))), (uint256)
        );
    }

    function lockAcquired(bytes calldata encodedSwapInfo) external oxionStorageOnly returns (bytes memory) {
        SwapInfo memory swapInfo = abi.decode(encodedSwapInfo, (SwapInfo));

        if (swapInfo.swapType == SwapType.ExactInput) {
            return abi.encode(
                _v1SwapExactInput(abi.decode(swapInfo.params, (ExactInputParams)), swapInfo.msgSender, true, true)
            );
        } else if (swapInfo.swapType == SwapType.ExactInputSingle) {
            return abi.encode(
                _v1SwapExactInputSingle(
                    abi.decode(swapInfo.params, (ExactInputSingleParams)), swapInfo.msgSender, true, true
                )
            );
        } else if (swapInfo.swapType == SwapType.ExactOutput) {
            return abi.encode(
                _v1SwapExactOutput(
                    abi.decode(swapInfo.params, (ExactOutputParams)), swapInfo.msgSender, true, true
                )
            );
        } else if (swapInfo.swapType == SwapType.ExactOutputSingle) {
            return abi.encode(
                _v1SwapExactOutputSingle(
                    abi.decode(swapInfo.params, (ExactOutputSingleParams)), swapInfo.msgSender, true, true
                )
            );
        } else {
            revert InvalidSwapType();
        }
    }

    function _payAndSettle(Currency currency, address msgSender, int128 settleAmount) internal virtual {
        _pay(currency, msgSender, address(oxionStorage), uint256(uint128(settleAmount)));
        oxionStorage.settleAndMintRefund(currency, msgSender);
    }

    function _pay(Currency currency, address payer, address recipient, uint256 amount) internal virtual {
        pay(currency, payer, recipient, amount);
    }

    function _v1SwapExactInputSingle(
        ExactInputSingleParams memory params,
        address msgSender,
        bool settle,
        bool take
    ) internal returns (uint256 amountOut) {
        amountOut = uint128(
            -_swapExactPrivate(
                params.poolKey,
                params.zeroForOne,
                int256(int128(params.amountIn)),
                params.sqrtPriceLimitX96,
                msgSender,
                params.recipient,
                settle,
                take
            )
        );
        if (amountOut < params.amountOutMinimum) revert TooLittleReceived();
    }

    function _v1SwapExactInput(ExactInputParams memory params, address msgSender, bool settle, bool take)
        internal
        returns (uint256)
    {
        unchecked {
            ExactInputState memory state;
            state.pathLength = params.path.length;

            for (uint256 i = 0; i < state.pathLength; i++) {
                (state.poolKey, state.zeroForOne) = _getPoolAndSwapDirection(params.path[i], params.currencyIn);
                state.amountOut = uint128(
                    -_swapExactPrivate(
                        state.poolKey,
                        state.zeroForOne,
                        int256(int128(params.amountIn)),
                        0,
                        msgSender,
                        params.recipient,
                        i == 0 && settle,
                        i == state.pathLength - 1 && take
                    )
                );

                params.amountIn = state.amountOut;
                params.currencyIn = params.path[i].intermediateCurrency;
            }

            if (state.amountOut < params.amountOutMinimum) revert TooLittleReceived();

            return state.amountOut;
        }
    }

    function _v1SwapExactOutputSingle(
        ExactOutputSingleParams memory params,
        address msgSender,
        bool settle,
        bool take
    ) internal returns (uint256 amountIn) {
        amountIn = uint128(
            _swapExactPrivate(
                params.poolKey,
                params.zeroForOne,
                -int256(int128(params.amountOut)),
                params.sqrtPriceLimitX96,
                msgSender,
                params.recipient,
                settle,
                take
            )
        );
        if (amountIn > params.amountInMaximum) revert TooMuchRequested();
    }

    function _v1SwapExactOutput(ExactOutputParams memory params, address msgSender, bool settle, bool take)
        internal
        returns (uint256)
    {
        unchecked {
            ExactOutputState memory state;
            state.pathLength = params.path.length;

            for (uint256 i = state.pathLength; i > 0; i--) {
                (state.poolKey, state.oneForZero) = _getPoolAndSwapDirection(params.path[i - 1], params.currencyOut);
                state.amountIn = uint128(
                    _swapExactPrivate(
                        state.poolKey,
                        !state.oneForZero,
                        -int256(int128(params.amountOut)),
                        0,
                        msgSender,
                        params.recipient,
                        i == 1 && settle,
                        i == state.pathLength && take
                    )
                );

                params.amountOut = state.amountIn;
                params.currencyOut = params.path[i - 1].intermediateCurrency;
            }
            if (state.amountIn > params.amountInMaximum) revert TooMuchRequested();

            return state.amountIn;
        }
    }

    function _swapExactPrivate(
        PoolKey memory poolKey,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        address msgSender,
        address recipient,
        bool settle,
        bool take
    ) private returns (int128 reciprocalAmount) {
        BalanceDelta delta = poolManager.swap(
            poolKey,
            IPoolManager.SwapParams(
                zeroForOne,
                amountSpecified,
                sqrtPriceLimitX96 == 0
                    ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                    : sqrtPriceLimitX96
            )
        );

        if (zeroForOne) {
            reciprocalAmount = amountSpecified > 0 ? delta.amount1() : delta.amount0();
            if (settle) _payAndSettle(poolKey.currency0, msgSender, delta.amount0());
            if (take) oxionStorage.take(poolKey.currency1, recipient, uint128(-delta.amount1()));
        } else {
            reciprocalAmount = amountSpecified > 0 ? delta.amount0() : delta.amount1();
            if (settle) _payAndSettle(poolKey.currency1, msgSender, delta.amount1());
            if (take) oxionStorage.take(poolKey.currency0, recipient, uint128(-delta.amount0()));
        }
    }

    function _getPoolAndSwapDirection(PathKey memory params, Currency currencyIn)
        internal
        pure
        returns (PoolKey memory poolKey, bool zeroForOne)
    {
        (Currency currency0, Currency currency1) = currencyIn < params.intermediateCurrency
            ? (currencyIn, params.intermediateCurrency)
            : (params.intermediateCurrency, currencyIn);

        zeroForOne = currencyIn == currency0;
        poolKey = PoolKey(currency0, currency1, params.poolManager, params.fee);
    }
}