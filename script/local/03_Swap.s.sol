// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

import { console2 } from "forge-std/Script.sol";

import { TokenMock } from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";

import { ISwapVM } from "../../src/interfaces/ISwapVM.sol";

import { LocalAquaScript } from "./base/LocalAquaScript.sol";

contract SwapScript is LocalAquaScript {
    uint256 public amountIn = DEFAULT_SWAP_AMOUNT_IN;
    uint256 public amountOutMin = 0;

    function run() external {
        address maker = _maker();
        address taker = _deployer();

        TokenMock tokenA = _tokenA();
        TokenMock tokenB = _tokenB();
        ISwapVM.Order memory order = _buildConstantProductOrder(maker);
        bytes memory takerData = _buildExactInTakerData(taker, amountOutMin);

        (uint256 quotedIn, uint256 quotedOut,) = router.asView().quote(
            order,
            address(tokenA),
            address(tokenB),
            amountIn,
            takerData
        );

        vm.startBroadcast();
        tokenA.mint(taker, amountIn);
        tokenA.approve(address(router), type(uint256).max);
        (uint256 actualIn, uint256 actualOut,) = router.swap(
            order,
            address(tokenA),
            address(tokenB),
            amountIn,
            takerData
        );
        vm.stopBroadcast();

        console2.log("Swapped TokenA for TokenB");
        console2.log("Taker:", taker);
        console2.log("Quoted amount in:", quotedIn);
        console2.log("Quoted amount out:", quotedOut);
        console2.log("Actual amount in:", actualIn);
        console2.log("Actual amount out:", actualOut);
        console2.log("Taker TokenA balance:", tokenA.balanceOf(taker));
        console2.log("Taker TokenB balance:", tokenB.balanceOf(taker));
        _logPool(maker, order, address(tokenA), address(tokenB));
    }
}
