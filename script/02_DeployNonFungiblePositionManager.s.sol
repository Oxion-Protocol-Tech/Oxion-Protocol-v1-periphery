// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {BaseScript} from "./BaseScript.sol";
import {IOxionStorage} from "Oxion-Protocol-v1-core/src/interfaces/IOxionStorage.sol";
import {IPoolManager} from "Oxion-Protocol-v1-core/src/interfaces/IPoolManager.sol";
import {NonfungiblePositionManager} from "../src/NonfungiblePositionManager.sol";

/**
 * forge script script/02_DeployNonFungiblePositionManager.s.sol:DeployNonFungiblePositionManagerScript -vvv \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --slow \
 *     --verify
 */
contract DeployNonFungiblePositionManagerScript is BaseScript {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address oxionStorage = getAddressFromConfig("OxionStorage");
        emit log_named_address("OxionStorage", oxionStorage);

        address PoolManager = getAddressFromConfig("PoolManager");
        emit log_named_address("PoolManager", PoolManager);

        address tokenDescriptor = getAddressFromConfig("nonFungibleTokenPositionDescriptorOffChain");
        emit log_named_address("NonFungibleTokenPositionDescriptorOffChain", tokenDescriptor);

        address weth = getAddressFromConfig("weth");
        emit log_named_address("WETH", weth);

        NonfungiblePositionManager nonFungiblePositionManager =
            new NonfungiblePositionManager(IOxionStorage(oxionStorage), IPoolManager(PoolManager), tokenDescriptor, weth);
        emit log_named_address("NonFungiblePositionManager", address(nonFungiblePositionManager));

        vm.stopBroadcast();
    }
}
