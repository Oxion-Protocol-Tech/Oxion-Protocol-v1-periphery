// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PoolId, PoolIdLibrary} from "Oxion-Protocol-v1-core/src/types/PoolId.sol";
import {BalanceDelta, toBalanceDelta} from "Oxion-Protocol-v1-core/src/types/BalanceDelta.sol";
import {OxionStorage} from "Oxion-Protocol-v1-core/src/OxionStorage.sol";
import {PoolManager} from "Oxion-Protocol-v1-core/src/PoolManager.sol";
import {IPoolManager} from "Oxion-Protocol-v1-core/src/interfaces/IPoolManager.sol";
import {SortTokens} from "Oxion-Protocol-v1-core/test/helpers/SortTokens.sol";
import {IPoolManager} from "Oxion-Protocol-v1-core/src/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "Oxion-Protocol-v1-core/src/types/Currency.sol";
import {PoolKey} from "Oxion-Protocol-v1-core/src/types/PoolKey.sol";
import {IOxionStorage} from "Oxion-Protocol-v1-core/src/interfaces/IOxionStorage.sol";
import {Constants} from "Oxion-Protocol-v1-core/test/helpers/Constants.sol";

import {SwapRouter} from "../../src/SwapRouter.sol";
import {ISwapRouter} from "../../src/interfaces/ISwapRouter.sol";
import {NonfungiblePositionManager} from "../../src/NonfungiblePositionManager.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/INonfungiblePositionManager.sol";

contract SwapRouterHandler is Test {
    using PoolIdLibrary for PoolKey;

    PoolKey public poolKey;
    PoolKey public nativePoolKey;
    IOxionStorage public oxionStorage;
    SwapRouter public router;
    NonfungiblePositionManager public positionManager;
    IPoolManager public poolManager;

    address public alice = makeAddr("alice");

    MockERC20 public token0;
    MockERC20 public token1;
    Currency public currency0;
    Currency public currency1;
    uint256 public token0Minted;
    uint256 public token1Minted;
    uint256 public nativeTokenMinted;

    constructor() {
        WETH weth = new WETH();
        oxionStorage = new OxionStorage();
        poolManager = new PoolManager(oxionStorage, 3000);
        oxionStorage.registerPoolManager(address(poolManager));

        token0 = new MockERC20("TestA", "A", 18);
        token1 = new MockERC20("TestB", "B", 18);
        (token0, token1) = address(token0) > address(token1) ? (token1, token0) : (token0, token1);
        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));

        // router and position manager
        positionManager = new NonfungiblePositionManager(oxionStorage, poolManager, address(0), address(weth));
        router = new SwapRouter(oxionStorage, poolManager, address(weth));

        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            poolManager: poolManager,
            fee: uint24(3000)
        });
        poolManager.initialize(poolKey, Constants.SQRT_RATIO_1_1);

        nativePoolKey = PoolKey({
            currency0: CurrencyLibrary.NATIVE,
            currency1: currency1,
            poolManager: poolManager,
            fee: uint24(3000)
        });
        poolManager.initialize(nativePoolKey, Constants.SQRT_RATIO_1_1);

        vm.startPrank(alice);
        IERC20(Currency.unwrap(currency0)).approve(address(positionManager), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(positionManager), type(uint256).max);
        IERC20(Currency.unwrap(currency0)).approve(address(router), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    function exactSwapInputSingle(uint128 amtIn, bool isNativePool) public {
        // Ensure at least some liquidity minted and amoutOut when swap > 0
        amtIn = uint128(bound(amtIn, 10, 100 ether));

        // step 1: Mint token to alice for swap and add liquidity
        _mint(amtIn, isNativePool);

        // Step 2: Mint token for alice to swap
        isNativePool ? vm.deal(alice, amtIn) : token0.mint(alice, amtIn);
        isNativePool ? nativeTokenMinted += amtIn : token0Minted += amtIn;

        // Step 3: swap
        PoolKey memory pk = isNativePool ? nativePoolKey : poolKey;
        // if native pool, have to ensure call method with value
        uint256 value = isNativePool ? amtIn : 0;
        vm.prank(alice);
        router.exactInputSingle{value: value}(
            ISwapRouter.ExactInputSingleParams({
                poolKey: pk,
                zeroForOne: true,
                recipient: alice,
                amountIn: amtIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            }),
            block.timestamp + 100
        );
    }

    function exactSwapInput(uint128 amtIn, bool isNativePool) public {
        // Ensure at least some liquidity minted and amoutOut when swap > 0
        amtIn = uint128(bound(amtIn, 10, 100 ether));

        // step 1: Mint token to alice for swap and add liquidity
        _mint(amtIn, isNativePool);

        // Step 2: Mint token for alice to swap
        isNativePool ? vm.deal(alice, amtIn) : token0.mint(alice, amtIn);
        isNativePool ? nativeTokenMinted += amtIn : token0Minted += amtIn;

        // Step 3: swap
        PoolKey memory pk = isNativePool ? nativePoolKey : poolKey;
        vm.prank(alice);
        ISwapRouter.PathKey[] memory path = new ISwapRouter.PathKey[](1);
        path[0] = ISwapRouter.PathKey({
            intermediateCurrency: Currency.wrap(address(token1)),
            fee: pk.fee,
            poolManager: pk.poolManager
        });

        // if native pool, have to ensure call method with value
        uint256 value = isNativePool ? amtIn : 0;
        router.exactInput{value: value}(
            ISwapRouter.ExactInputParams({
                currencyIn: isNativePool ? CurrencyLibrary.NATIVE : currency0,
                path: path,
                recipient: alice,
                amountIn: amtIn,
                amountOutMinimum: 0
            }),
            block.timestamp + 100
        );
    }

    function exactSwapOutputSingle(uint128 amtIn, bool isNativePool) public {
        amtIn = uint128(bound(amtIn, 10, 100 ether));

        // step 1: Mint token to alice for swap and add liquidity
        _mint(amtIn, isNativePool);

        // Step 2: Mint token for alice to swap
        isNativePool ? vm.deal(alice, amtIn) : token0.mint(alice, amtIn);
        isNativePool ? nativeTokenMinted += amtIn : token0Minted += amtIn;

        // Step 3: swap
        PoolKey memory pk = isNativePool ? nativePoolKey : poolKey;
        // if native pool, have to ensure call method with value
        uint256 value = isNativePool ? amtIn : 0;
        vm.prank(alice);
        router.exactOutputSingle{value: value}(
            ISwapRouter.ExactOutputSingleParams({
                poolKey: pk,
                zeroForOne: true,
                recipient: alice,
                amountOut: amtIn / 2,
                amountInMaximum: amtIn,
                sqrtPriceLimitX96: 0
            }),
            block.timestamp + 100
        );
    }

    function exactSwapOutput(uint128 amtIn, bool isNativePool) public {
        amtIn = uint128(bound(amtIn, 10, 100 ether));

        // step 1: Mint token to alice for swap and add liquidity
        _mint(amtIn, isNativePool);

        // Step 2: Mint token for alice to swap
        isNativePool ? vm.deal(alice, amtIn) : token0.mint(alice, amtIn);
        isNativePool ? nativeTokenMinted += amtIn : token0Minted += amtIn;

        // Step 3: swap
        PoolKey memory pk = isNativePool ? nativePoolKey : poolKey;
        vm.prank(alice);
        ISwapRouter.PathKey[] memory path = new ISwapRouter.PathKey[](1);
        path[0] = ISwapRouter.PathKey({
            intermediateCurrency: isNativePool ? CurrencyLibrary.NATIVE : currency0,
            fee: pk.fee,
            poolManager: pk.poolManager
        });

        // if native pool, have to ensure call method with value
        uint256 value = isNativePool ? amtIn : 0;
        router.exactOutput{value: value}(
            ISwapRouter.ExactOutputParams({
                currencyOut: currency1,
                path: path,
                recipient: alice,
                amountOut: amtIn / 2,
                amountInMaximum: amtIn
            }),
            block.timestamp + 60
        );
    }

    function _mint(uint128 amt, bool isNativePool) private {
        /// @dev given that amt is cap at 100 ether, we can safely mint 5x the amount to reduce slippage in trading
        amt = amt * 10;

        // step 1: Mint token to alice for add liquidity
        isNativePool ? vm.deal(alice, amt) : token0.mint(alice, amt);
        isNativePool ? nativeTokenMinted += amt : token0Minted += amt;
        token1Minted += amt;
        token1.mint(alice, amt);

        vm.startPrank(alice);

        PoolKey memory pk = isNativePool ? nativePoolKey : poolKey;
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            poolKey: pk,
            tickLower: -10,
            tickUpper: 10,
            amount0Desired: amt,
            amount1Desired: amt,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        if (isNativePool) {
            positionManager.mint{value: amt}(mintParams);
        } else {
            positionManager.mint(mintParams);
        }
        vm.stopPrank();
    }
}

contract SwapRouterInvariant is Test {
    SwapRouterHandler _handler;

    function setUp() public {
        // deploy necessary contract
        _handler = new SwapRouterHandler();

        // only call SwapRouterHandler
        targetContract(address(_handler));

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = SwapRouterHandler.exactSwapInputSingle.selector;
        selectors[1] = SwapRouterHandler.exactSwapOutputSingle.selector;
        selectors[2] = SwapRouterHandler.exactSwapInput.selector;
        selectors[3] = SwapRouterHandler.exactSwapOutput.selector;
        targetSelector(FuzzSelector({addr: address(_handler), selectors: selectors}));
    }

    /// @dev token minted should be either in oxionStorage or with alice
    function invariant_AllTokensInVaultOrUser() public {
        IOxionStorage oxionStorage = IOxionStorage(_handler.oxionStorage());

        // token0
        uint256 token0BalInOxionStorage = oxionStorage.reservesOfStorage(_handler.currency0());
        uint256 token0WithAlice = _handler.token0().balanceOf(_handler.alice());
        uint256 token0Reserve = oxionStorage.reservesOfPoolManager(_handler.poolManager(), _handler.currency0());
        assertEq(token0BalInOxionStorage + token0WithAlice, _handler.token0Minted());

        // token1
        uint256 token1BalInOxionStorage = oxionStorage.reservesOfStorage(_handler.currency1());
        uint256 token1WithAlice = _handler.token1().balanceOf(_handler.alice());
        assertEq(token1BalInOxionStorage + token1WithAlice, _handler.token1Minted());

        // Native ETH case will have spare ETH in router
        uint256 nativeTokenInOxionStorage = oxionStorage.reservesOfStorage(CurrencyLibrary.NATIVE);
        uint256 nativeTokenWithAlice = _handler.alice().balance;
        uint256 routerBalance = address(_handler.router()).balance;
        assertEq(nativeTokenInOxionStorage + nativeTokenWithAlice + routerBalance, _handler.nativeTokenMinted());
    }
}
