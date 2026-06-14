// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { console2 } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISwapVM } from "../../src/interfaces/ISwapVM.sol";

import { FairAuctionManager } from "../../src/local/fair/FairAuctionManager.sol";
import { IFeeValueOracle } from "../../src/local/fair/interfaces/IFeeValueOracle.sol";
import { LocalFairDammScript } from "./base/LocalFairDammScript.sol";
import { LocalDeployments } from "./libraries/LocalDeployments.sol";

contract CreateFairDammPoolScript is LocalFairDammScript {
    function run() external {
        bytes32 expectedPoolId = _fairPoolId();
        try FAIR_AUCTION_MANAGER.getPool(expectedPoolId) returns (FairAuctionManager.PoolConfig memory) {
            console2.log("Fair DAMM pool already exists:");
            console2.logBytes32(expectedPoolId);
            _logFairPool();
            return;
        } catch {}

        vm.startBroadcast();
        bytes32 poolId = FAIR_AUCTION_MANAGER.createPool(FairAuctionManager.PoolInit({
            aqua: AQUA,
            router: ISwapVM(address(ROUTER)),
            tokenA: LocalDeployments.tokenA(),
            tokenB: LocalDeployments.tokenB(),
            rentToken: IERC20(address(_tokenA())),
            feeValueOracle: IFeeValueOracle(LocalDeployments.fairFeeValueOracle()),
            minFeeBps: LocalDeployments.FAIR_MIN_FEE_BPS,
            defaultFeeBps: LocalDeployments.FAIR_DEFAULT_FEE_BPS,
            maxFeeBps: LocalDeployments.FAIR_MAX_FEE_BPS,
            epochLengthBlocks: LocalDeployments.FAIR_EPOCH_LENGTH_BLOCKS,
            salt: LocalDeployments.FAIR_POOL_SALT
        }));
        vm.stopBroadcast();

        require(poolId == expectedPoolId, "unexpected fair DAMM pool id");
        console2.log("Created Fair DAMM pool:");
        console2.logBytes32(poolId);
        _logFairPool();
    }
}
