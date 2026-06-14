// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { console2 } from "forge-std/Script.sol";

import { LocalFairDammScript } from "./base/LocalFairDammScript.sol";
import { LocalDeployments } from "./libraries/LocalDeployments.sol";

contract SetFairDammManagerFeeScript is LocalFairDammScript {
    function run() external {
        vm.startBroadcast();
        FAIR_AUCTION_MANAGER.setManagerFee(_fairPoolId(), LocalDeployments.FAIR_MANAGER_FEE_BPS);
        vm.stopBroadcast();

        console2.log("Set Fair DAMM manager fee");
        console2.log("Fee bps:", LocalDeployments.FAIR_MANAGER_FEE_BPS);
        _logFairPool();
    }
}
