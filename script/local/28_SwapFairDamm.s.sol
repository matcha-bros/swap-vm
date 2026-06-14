// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { console2 } from "forge-std/Script.sol";

import { LocalFairDammScript } from "./base/LocalFairDammScript.sol";
import { LocalDeployments } from "./libraries/LocalDeployments.sol";

contract SwapFairDammScript is LocalFairDammScript {
    function run() external {
        address taker = _deployer();
        address maker = _maker();
        bytes memory takerData = _buildExactInTakerData(taker, 0);

        vm.startBroadcast();
        _tokenA().mint(taker, LocalDeployments.SWAP_AMOUNT_IN);
        _tokenA().approve(address(ROUTER), LocalDeployments.SWAP_AMOUNT_IN);
        ROUTER.swap(
            _buildFairDammOrder(maker, LocalDeployments.FAIR_DEFAULT_POSITION_SALT),
            address(_tokenA()),
            address(_tokenB()),
            LocalDeployments.SWAP_AMOUNT_IN,
            takerData
        );
        vm.stopBroadcast();

        console2.log("Swapped through Fair DAMM pool");
        console2.log("Amount in:", LocalDeployments.SWAP_AMOUNT_IN);
        _logFairPool();
    }
}
