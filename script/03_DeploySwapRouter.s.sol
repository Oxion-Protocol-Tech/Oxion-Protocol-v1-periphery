// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {BaseScript} from "./BaseScript.sol";
import {IOxionStorage} from "Oxion-Protocol-v1-core/src/interfaces/IOxionStorage.sol";
import {IPoolManager} from "Oxion-Protocol-v1-core/src/interfaces/IPoolManager.sol";
import {SwapRouter} from "../src/SwapRouter.sol";

/**
 * forge script script/03_DeployCLSwapRouter.s.sol:DeployCLSwapRouterScript -vvv \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --slow \
 *     --verify
 */
contract DeploySwapRouterScript is BaseScript {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address oxionStorage = getAddressFromConfig("oxionStorage");
        emit log_named_address("OxionStorage", oxionStorage);

        address PoolManager = getAddressFromConfig("PoolManager");
        emit log_named_address("PoolManager", PoolManager);

        address weth = getAddressFromConfig("weth");
        emit log_named_address("WETH", weth);

        SwapRouter SwapRouter = new SwapRouter(IOxionStorage(oxionStorage), IPoolManager(PoolManager), weth);
        emit log_named_address("SwapRouter", address(SwapRouter));

        vm.stopBroadcast();
    }
}
