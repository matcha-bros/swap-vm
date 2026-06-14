// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script, console2 } from "forge-std/Script.sol";

import { MockFeeValueOracle } from "../../src/local/fair/mocks/MockFeeValueOracle.sol";
import { Create2Utils } from "./utils/Create2Utils.sol";
import { LocalDeployments } from "./libraries/LocalDeployments.sol";

contract DeployFairDammScript is Script {
    function run() external {
        vm.startBroadcast();
        (address auctionManager, bool auctionManagerExists) =
            Create2Utils.getOrDeploy(LocalDeployments.fairAuctionManagerInitCode(), LocalDeployments.FAIR_AUCTION_MANAGER_SALT);
        (address feeValueOracle, bool feeValueOracleExists) =
            Create2Utils.getOrDeploy(LocalDeployments.fairFeeValueOracleInitCode(), LocalDeployments.FAIR_FEE_VALUE_ORACLE_SALT);

        MockFeeValueOracle oracle = MockFeeValueOracle(feeValueOracle);
        oracle.setPrice(LocalDeployments.tokenA(), LocalDeployments.FAIR_TOKEN_A_PRICE_X18);
        oracle.setPrice(LocalDeployments.tokenB(), LocalDeployments.FAIR_TOKEN_B_PRICE_X18);
        vm.stopBroadcast();

        _log("Fair DAMM AuctionManager", auctionManager, auctionManagerExists);
        _log("Fair DAMM FeeValueOracle", feeValueOracle, feeValueOracleExists);
    }

    function _log(string memory label, address deployed, bool existed) internal pure {
        console2.log(label, deployed);
        console2.log(existed ? "  status: existing" : "  status: deployed");
    }
}
