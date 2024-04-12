// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 Oxion Protocol
pragma solidity ^0.8.24;

import {IOxionStorage} from "Oxion-Protocol-v1-core/src/interfaces/IOxionStorage.sol";
import {IPoolManager} from "Oxion-Protocol-v1-core/src/interfaces/IPoolManager.sol";

/// @title Immutable state
/// @notice Functions that return immutable state of the router
interface IPeripheryImmutableState {
    /// @return Returns the address of the Oxion Protocol V1 oxion Storage
    function oxionStorage() external view returns (IOxionStorage);

    /// @return Returns the address of the Oxion Protocol V1 pool manager
    function poolManager() external view returns (IPoolManager);

    /// @return Returns the address of WETH9
    function WETH9() external view returns (address);
}
