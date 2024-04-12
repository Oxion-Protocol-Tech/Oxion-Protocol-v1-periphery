// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 Oxion Protoocol
pragma solidity ^0.8.24;

import {IOxionStorage} from "Oxion-Protocol-v1-core/src/interfaces/IOxionStorage.sol";
import {IPoolManager} from "Oxion-Protocol-v1-core/src/interfaces/IPoolManager.sol";
import {IPeripheryImmutableState} from "../interfaces/IPeripheryImmutableState.sol";

/// @title Immutable state
/// @notice Immutable state used by periphery contracts
contract PeripheryImmutableState is IPeripheryImmutableState {
    IOxionStorage public immutable oxionStorage;
    IPoolManager public immutable poolManager;
    address public immutable WETH9;

    constructor(IOxionStorage _oxionStorage, IPoolManager _poolManager, address _WETH9) {
        oxionStorage = _oxionStorage;
        poolManager = _poolManager;
        WETH9 = _WETH9;
    }
}