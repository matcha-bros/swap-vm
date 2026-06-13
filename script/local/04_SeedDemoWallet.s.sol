// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

import { console2 } from "forge-std/Script.sol";

import { TokenMock } from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";

import { LocalAquaScript } from "./base/LocalAquaScript.sol";

contract SeedDemoWalletScript is LocalAquaScript {
    function run() external {
        address deployer = _deployer();
        address seedWallet = _seedWallet();
        uint256 tokenAmount = _seedTokenAmount();
        uint256 ethAmount = _seedEthAmount();

        TokenMock tokenA = _tokenA();
        TokenMock tokenB = _tokenB();

        vm.startBroadcast();
        tokenA.mint(seedWallet, tokenAmount);
        tokenB.mint(seedWallet, tokenAmount);

        if (ethAmount > 0 && seedWallet != deployer) {
            (bool success,) = payable(seedWallet).call{ value: ethAmount }("");
            require(success, "ETH seed failed");
        }
        vm.stopBroadcast();

        console2.log("Seeded demo wallet:", seedWallet);
        console2.log("TokenA:", address(tokenA));
        console2.log("TokenB:", address(tokenB));
        console2.log("Token amount each:", tokenAmount);
        console2.log("ETH amount:", ethAmount);
        console2.log("Seed wallet TokenA balance:", tokenA.balanceOf(seedWallet));
        console2.log("Seed wallet TokenB balance:", tokenB.balanceOf(seedWallet));
        console2.log("Seed wallet ETH balance:", seedWallet.balance);
    }
}
