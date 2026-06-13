// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

import { Script, console2 } from "forge-std/Script.sol";
import { TokenMock } from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";

contract DeployMockTokensScript is Script {
    function run() external {
        vm.startBroadcast();
        TokenMock tokenA = new TokenMock("Token A", "TKA");
        TokenMock tokenB = new TokenMock("Token B", "TKB");
        vm.stopBroadcast();

        console2.log("TokenA:", address(tokenA));
        console2.log("TokenB:", address(tokenB));
        console2.log("Set OPS_TOKEN_A_ADDRESS and OPS_TOKEN_B_ADDRESS in swap-vm/.env");
    }
}
