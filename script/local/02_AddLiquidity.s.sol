// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

import { console2 } from "forge-std/Script.sol";

import { TokenMock } from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";

import { ISwapVM } from "../../src/interfaces/ISwapVM.sol";

import { LocalAquaScript } from "./base/LocalAquaScript.sol";

contract AddLiquidityScript is LocalAquaScript {
    uint256 public tokenAAmount = DEFAULT_ADD_LIQUIDITY_A;
    uint256 public tokenBAmount = DEFAULT_ADD_LIQUIDITY_B;

    function run() external {
        address maker = _maker();
        require(maker == _deployer(), "run with maker private key");

        TokenMock tokenA = _tokenA();
        TokenMock tokenB = _tokenB();
        ISwapVM.Order memory order = _buildConstantProductOrder(maker);
        bytes32 orderHash = router.hash(order);

        vm.startBroadcast();
        tokenA.mint(maker, tokenAAmount);
        tokenB.mint(maker, tokenBAmount);
        tokenA.approve(address(aqua), type(uint256).max);
        tokenB.approve(address(aqua), type(uint256).max);
        aqua.push(maker, address(router), orderHash, address(tokenA), tokenAAmount);
        aqua.push(maker, address(router), orderHash, address(tokenB), tokenBAmount);
        vm.stopBroadcast();

        console2.log("Added liquidity to Aqua constant product pool");
        _logPool(maker, order, address(tokenA), address(tokenB));
    }
}
