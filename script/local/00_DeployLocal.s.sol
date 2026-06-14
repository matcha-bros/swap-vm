// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script, console2 } from "forge-std/Script.sol";

import { Create2Utils } from "./utils/Create2Utils.sol";
import { LocalDeployments } from "./libraries/LocalDeployments.sol";

contract DeployLocalContractsScript is Script {
    function run() public virtual {
        vm.startBroadcast();
        _deployAndLog("AquaRouter", LocalDeployments.aquaInitCode(), LocalDeployments.AQUA_ROUTER_SALT);
        _deployAndLog("WETH", LocalDeployments.wethInitCode(), LocalDeployments.WETH_SALT);
        _deployAndLog(
            "AquaSwapVMRouter internal adapter",
            LocalDeployments.swapVmRouterInitCode(),
            LocalDeployments.SWAP_VM_ROUTER_SALT
        );
        (address tychoRouter, bool tychoRouterExists) =
            Create2Utils.getOrDeploy(LocalDeployments.tychoRouterInitCode(), LocalDeployments.TYCHO_ROUTER_SALT);
        (address aquaSwapVmExecutor, bool aquaSwapVmExecutorExists) =
            Create2Utils.getOrDeploy(LocalDeployments.aquaSwapVmExecutorInitCode(), LocalDeployments.AQUA_SWAP_VM_EXECUTOR_SALT);
        _log("TychoRouter", tychoRouter, tychoRouterExists);
        _log("AquaSwapVMExecutor", aquaSwapVmExecutor, aquaSwapVmExecutorExists);
        _deployAndLog("Token A", LocalDeployments.tokenAInitCode(), LocalDeployments.TOKEN_A_SALT);
        _deployAndLog("Token B", LocalDeployments.tokenBInitCode(), LocalDeployments.TOKEN_B_SALT);
        _deployAndLog("USDC", LocalDeployments.usdcInitCode(), LocalDeployments.USDC_SALT);
        _deployAndLog("WBTC", LocalDeployments.wbtcInitCode(), LocalDeployments.WBTC_SALT);
        _registerExecutor(tychoRouter, aquaSwapVmExecutor);
        vm.stopBroadcast();
    }

    function _registerExecutor(address tychoRouter, address executor) internal {
        (bool ok, bytes memory result) =
            tychoRouter.staticcall(abi.encodeWithSignature("executorsActivationTimestamp(address)", executor));
        if (ok && result.length == 32 && abi.decode(result, (uint256)) != 0) return;

        address[] memory executors = new address[](1);
        executors[0] = executor;
        (bool success, bytes memory data) = tychoRouter.call(abi.encodeWithSignature("setExecutors(address[])", executors));
        if (!success) {
            assembly {
                revert(add(data, 0x20), mload(data))
            }
        }
    }

    function _log(string memory label, address deployed, bool existed) internal pure {
        console2.log(label, deployed);
        console2.log(existed ? "  status: existing" : "  status: deployed");
    }

    function _deployAndLog(string memory label, bytes memory initCode, bytes32 salt) internal {
        (address deployed, bool existed) = Create2Utils.getOrDeploy(initCode, salt);
        _log(label, deployed, existed);
    }
}
