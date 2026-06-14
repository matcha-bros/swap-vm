// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { console2 } from "forge-std/Script.sol";

import { LocalFairDammScript } from "./base/LocalFairDammScript.sol";

contract RollFairDammEpochScript is LocalFairDammScript {
    function run() external {
        vm.startBroadcast();
        FAIR_AUCTION_MANAGER.rollEpoch(_fairPoolId());
        vm.stopBroadcast();

        console2.log("Rolled Fair DAMM epoch");
        _logFairPool();
    }
}
