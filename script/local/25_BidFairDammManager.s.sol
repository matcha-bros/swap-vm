// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { console2 } from "forge-std/Script.sol";
import { LocalERC20Mock as MockERC20 } from "../../src/local/mocks/LocalERC20Mock.sol";

import { LocalFairDammScript } from "./base/LocalFairDammScript.sol";
import { LocalDeployments } from "./libraries/LocalDeployments.sol";

contract BidFairDammManagerScript is LocalFairDammScript {
    function run() external {
        address bidder = _deployer();
        MockERC20 rentToken = _tokenA();

        vm.startBroadcast();
        rentToken.mint(bidder, LocalDeployments.FAIR_BID_RENT);
        rentToken.approve(address(FAIR_AUCTION_MANAGER), LocalDeployments.FAIR_BID_RENT);
        FAIR_AUCTION_MANAGER.placeBid(_fairPoolId(), LocalDeployments.FAIR_BID_RENT);
        vm.stopBroadcast();

        console2.log("Placed Fair DAMM manager bid");
        console2.log("Bidder:", bidder);
        console2.log("Rent amount:", LocalDeployments.FAIR_BID_RENT);
        _logFairPool();
    }
}
