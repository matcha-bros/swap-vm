// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { console2 } from "forge-std/Script.sol";

import { LocalFairDammScript } from "./base/LocalFairDammScript.sol";

contract ClaimFairDammRentScript is LocalFairDammScript {
    function run() external {
        uint64 epoch = FAIR_AUCTION_MANAGER.currentEpoch(_fairPoolId());

        vm.startBroadcast();
        uint256 amount = FAIR_AUCTION_MANAGER.claimRent(_fairPoolId(), 1, epoch);
        vm.stopBroadcast();

        console2.log("Claimed Fair DAMM rent");
        console2.log("Epoch:", epoch);
        console2.log("Position id:", uint256(1));
        console2.log("Amount:", amount);
    }
}
