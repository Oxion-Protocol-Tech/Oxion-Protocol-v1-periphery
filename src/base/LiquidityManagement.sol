// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 Oxion Protocol
pragma solidity ^0.8.24;

import {IOxionStorage} from "Oxion-Protocol-v1-core/src/interfaces/IOxionStorage.sol";
import {IPoolManager} from "Oxion-Protocol-v1-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "Oxion-Protocol-v1-core/src/types/PoolKey.sol";
import {BalanceDelta} from "Oxion-Protocol-v1-core/src/types/BalanceDelta.sol";
import {Currency} from "Oxion-Protocol-v1-core/src/types/Currency.sol";
import {Position} from "Oxion-Protocol-v1-core/src/libraries/Position.sol";
import {TickMath} from "Oxion-Protocol-v1-core/src/libraries/TickMath.sol";
import {PoolIdLibrary} from "Oxion-Protocol-v1-core/src/types/PoolId.sol";
import {PeripheryPayments} from "./PeripheryPayments.sol";
import {PeripheryImmutableState} from "./PeripheryImmutableState.sol";
import {LiquidityAmounts} from "../libraries/LiquidityAmounts.sol";

/// @title Liquidity management functions
/// @notice Internal functions for safely managing liquidity in Oxion Protocol V1
abstract contract LiquidityManagement is PeripheryImmutableState, PeripheryPayments {
    using PoolIdLibrary for PoolKey;

    error PriceSlippageCheckFailed();

    struct AddLiquidityParams {
        PoolKey poolKey;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    struct RemoveLiquidityParams {
        PoolKey poolKey;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    /// @dev Since in v1 `modifyLiquidity` accumulated fee are claimed and
    // resynced by default, which can mixup with user's actual settlement
    // for update liquidity, we claim the fee before further action to avoid this.
    function resetAccumulatedFee(PoolKey memory poolKey, int24 tickLower, int24 tickUpper) internal {
        Position.Info memory poolManagerPositionInfo =
            poolManager.getPosition(poolKey.toId(), address(this), tickLower, tickUpper);

        if (poolManagerPositionInfo.liquidity > 0) {
            BalanceDelta delta =
                poolManager.modifyLiquidity(poolKey, IPoolManager.ModifyLiquidityParams(tickLower, tickUpper, 0));

            if (delta.amount0() < 0) {
                oxionStorage.mint(poolKey.currency0, address(this), uint256(int256(-delta.amount0())));
            }

            if (delta.amount1() < 0) {
                oxionStorage.mint(poolKey.currency1, address(this), uint256(int256(-delta.amount1())));
            }
        }
    }

    function addLiquidity(AddLiquidityParams memory params) internal returns (uint128 liquidity, BalanceDelta delta) {
        resetAccumulatedFee(params.poolKey, params.tickLower, params.tickUpper);

        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(params.poolKey.toId());
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(params.tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(params.tickUpper);
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, params.amount0Desired, params.amount1Desired
        );

        delta = poolManager.modifyLiquidity(
            params.poolKey,
            IPoolManager.ModifyLiquidityParams(params.tickLower, params.tickUpper, int256(uint256(liquidity)))
        );

        /// @dev amount0 & amount1 cant be negative here since LPing has been claimed
        if (
            uint256(uint128(delta.amount0())) < params.amount0Min
                || uint256(uint128(delta.amount1())) < params.amount1Min
        ) {
            revert PriceSlippageCheckFailed();
        }
    }

    function removeLiquidity(RemoveLiquidityParams memory params) internal returns (BalanceDelta delta) {
        resetAccumulatedFee(params.poolKey, params.tickLower, params.tickUpper);

        delta = poolManager.modifyLiquidity(
            params.poolKey,
            IPoolManager.ModifyLiquidityParams(params.tickLower, params.tickUpper, -int256(uint256(params.liquidity)))
        );

        /// @dev amount0 & amount1 must be negative here since LPing has been claimed
        if (
            uint256(uint128(-delta.amount0())) < params.amount0Min
                || uint256(uint128(-delta.amount1())) < params.amount1Min
        ) {
            revert PriceSlippageCheckFailed();
        }
    }

    function burnAndTake(Currency currency, address to, uint256 amount) internal {
        oxionStorage.burn(currency, amount);
        oxionStorage.take(currency, to, amount);
    }

    function settleDeltas(address sender, PoolKey memory poolKey, BalanceDelta delta) internal {
        if (delta.amount0() > 0) {
            pay(poolKey.currency0, sender, address(oxionStorage), uint256(int256(delta.amount0())));
            oxionStorage.settleAndMintRefund(poolKey.currency0, sender);
        } else if (delta.amount0() < 0) {
            oxionStorage.take(poolKey.currency0, sender, uint128(-delta.amount0()));
        }
        if (delta.amount1() > 0) {
            pay(poolKey.currency1, sender, address(oxionStorage), uint256(int256(delta.amount1())));
            oxionStorage.settleAndMintRefund(poolKey.currency1, sender);
        } else if (delta.amount1() < 0) {
            oxionStorage.take(poolKey.currency1, sender, uint128(-delta.amount1()));
        }
    }
}
