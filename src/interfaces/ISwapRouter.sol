// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 Oxion Protocol
pragma solidity ^0.8.24;

import {PoolKey} from "Oxion-Protocol-v1-core/src/types/PoolKey.sol";
import {Currency} from "Oxion-Protocol-v1-core/src/types/Currency.sol";
import {IPoolManager} from "Oxion-Protocol-v1-core/src/interfaces/IPoolManager.sol";

interface ISwapRouter {
    error InvalidSwapType();
    error TooLittleReceived();
    error TooMuchRequested();
    error DeadlineExceeded(uint256 deladline, uint256 now);

    struct ExactInputSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        address recipient;
        uint128 amountIn;
        uint128 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    struct ExactInputParams {
        Currency currencyIn;
        PathKey[] path;
        address recipient;
        uint128 amountIn;
        uint128 amountOutMinimum;
    }

    struct ExactOutputSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        address recipient;
        uint128 amountOut;
        uint128 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    struct ExactOutputParams {
        Currency currencyOut;
        PathKey[] path;
        address recipient;
        uint128 amountOut;
        uint128 amountInMaximum;
    }

    struct PathKey {
        Currency intermediateCurrency;
        uint24 fee;
        IPoolManager poolManager;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @param deadline A timestamp, the current blocktime must be less than or equal to this timestamp
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params, uint256 deadline)
        external
        payable
        returns (uint256 amountOut);

    /// @notice Swaps `amountIn` of one token for as much as possible of another along the specified path
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactInputParams` in calldata
    /// @param deadline A timestamp, the current blocktime must be less than or equal to this timestamp
    /// @return amountOut The amount of the received token
    function exactInput(ExactInputParams calldata params, uint256 deadline)
        external
        payable
        returns (uint256 amountOut);

    /// @notice Swaps as little as possible of one token for `amountOut` of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactOutputSingleParams` in calldata
    /// @param deadline A timestamp, the current blocktime must be less than or equal to this timestamp
    /// @return amountIn The amount of the input token
    function exactOutputSingle(ExactOutputSingleParams calldata params, uint256 deadline)
        external
        payable
        returns (uint256 amountIn);

    /// @notice Swaps as little as possible of one token for `amountOut` of another along the specified path (reversed)
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactOutputParams` in calldata
    /// @param deadline A timestamp, the current blocktime must be less than or equal to this timestamp
    /// @return amountIn The amount of the input token
    function exactOutput(ExactOutputParams calldata params, uint256 deadline)
        external
        payable
        returns (uint256 amountIn);
}
