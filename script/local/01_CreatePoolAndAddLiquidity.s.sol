// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

import { console2 } from "forge-std/Script.sol";

import { TokenMock } from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";

import { ISwapVM } from "../../src/interfaces/ISwapVM.sol";

import { LocalAquaScript } from "./base/LocalAquaScript.sol";

contract CreatePoolAndAddLiquidityScript is LocalAquaScript {
    uint256 public tokenAAmount = DEFAULT_POOL_BALANCE_A;
    uint256 public tokenBAmount = DEFAULT_POOL_BALANCE_B;

    function run() external {
        address maker = _maker();
        require(maker == _deployer(), "run with maker private key");

        TokenMock tokenA = _tokenA();
        TokenMock tokenB = _tokenB();
        ISwapVM.Order memory order = _buildConstantProductOrder(maker);
        bytes32 orderHash = router.hash(order);

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = tokenAAmount;
        amounts[1] = tokenBAmount;

        vm.startBroadcast();
        tokenA.mint(maker, tokenAAmount);
        tokenB.mint(maker, tokenBAmount);
        tokenA.approve(address(aqua), type(uint256).max);
        tokenB.approve(address(aqua), type(uint256).max);
        bytes32 strategyHash = aqua.ship(address(router), abi.encode(order), tokens, amounts);
        vm.stopBroadcast();

        require(strategyHash == orderHash, "strategy hash mismatch");

        console2.log("Created Aqua constant product pool");
        _logPool(maker, order, address(tokenA), address(tokenB));
    }
}
