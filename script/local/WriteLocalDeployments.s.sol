// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script, console2 } from "forge-std/Script.sol";

import { LocalDeployments } from "./libraries/LocalDeployments.sol";

contract WriteLocalDeploymentsScript is Script {
    function run() external {
        string memory object = "local";
        vm.serializeUint(object, "chainId", block.chainid);
        vm.serializeUint(object, "deploymentBlock", block.number);
        vm.serializeAddress(object, "owner", LocalDeployments.DEFAULT_OWNER);
        vm.serializeAddress(object, "aquaRouter", LocalDeployments.aqua());
        vm.serializeAddress(object, "weth", LocalDeployments.weth());
        vm.serializeAddress(object, "aquaSwapVmRouter", LocalDeployments.swapVmRouter());
        vm.serializeAddress(object, "tychoRouter", LocalDeployments.tychoRouter());
        vm.serializeAddress(object, "aquaSwapVmExecutor", LocalDeployments.aquaSwapVmExecutor());
        vm.serializeAddress(object, "fairAuctionManager", LocalDeployments.fairAuctionManager());
        vm.serializeAddress(object, "fairFeeValueOracle", LocalDeployments.fairFeeValueOracle());
        vm.serializeAddress(object, "tokenA", LocalDeployments.tokenA());
        vm.serializeAddress(object, "tokenB", LocalDeployments.tokenB());
        vm.serializeAddress(object, "usdc", LocalDeployments.usdc());
        string memory json = vm.serializeAddress(object, "wbtc", LocalDeployments.wbtc());

        string memory path = string.concat(vm.projectRoot(), "/deployments/local.json");
        vm.writeJson(json, path);
        console2.log("Wrote local deployments:", path);
    }
}
