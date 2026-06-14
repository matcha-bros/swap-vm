// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { console2 } from "forge-std/Script.sol";
import { ISwapVM } from "../../src/interfaces/ISwapVM.sol";
import { LocalERC20Mock as MockERC20 } from "../../src/local/mocks/LocalERC20Mock.sol";

import { LocalFairDammScript } from "./base/LocalFairDammScript.sol";
import { LocalDeployments } from "./libraries/LocalDeployments.sol";

contract ShipAndRegisterFairDammLiquidityScript is LocalFairDammScript {
    function run() external {
        address maker = _maker();
        MockERC20 tokenA = _tokenA();
        MockERC20 tokenB = _tokenB();

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = LocalDeployments.POOL_BALANCE_A;
        amounts[1] = LocalDeployments.POOL_BALANCE_B;

        vm.startBroadcast();
        tokenA.mint(maker, LocalDeployments.POOL_BALANCE_A);
        tokenB.mint(maker, LocalDeployments.POOL_BALANCE_B);
        tokenA.approve(address(AQUA), type(uint256).max);
        tokenB.approve(address(AQUA), type(uint256).max);

        bytes32 positionSalt = LocalDeployments.FAIR_DEFAULT_POSITION_SALT;
        ISwapVM.Order memory order = _buildFairDammOrder(maker, positionSalt);
        bytes32 strategyHash = ROUTER.hash(order);
        (, uint8 tokensCount) = AQUA.rawBalances(maker, address(ROUTER), strategyHash, address(tokenA));
        if (tokensCount == 0) {
            bytes32 shippedStrategyHash = AQUA.ship(address(ROUTER), abi.encode(order), tokens, amounts);
            require(shippedStrategyHash == strategyHash, "strategy hash mismatch");
        }
        uint256 positionId = 0;
        if (!FAIR_AUCTION_MANAGER.isRegisteredOrder(_fairPoolId(), strategyHash)) {
            positionId = FAIR_AUCTION_MANAGER.registerPosition(_fairPoolId(), order);
        }
        vm.stopBroadcast();

        console2.log("Shipped and registered Fair DAMM liquidity");
        console2.log("Position id:", positionId);
        console2.log("Strategy hash:");
        console2.logBytes32(strategyHash);
        _logPool(maker, order, address(tokenA), address(tokenB));
    }
}
