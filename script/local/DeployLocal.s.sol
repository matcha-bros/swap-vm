// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { DeployLocalContractsScript } from "./00_DeployLocal.s.sol";
import { DeployFairDammScript } from "./22_DeployFairDamm.s.sol";
import { CreateFairDammPoolScript } from "./23_CreateFairDammPool.s.sol";
import { ShipAndRegisterFairDammLiquidityScript } from "./24_ShipAndRegisterFairDammLiquidity.s.sol";
import { WriteLocalDeploymentsScript } from "./WriteLocalDeployments.s.sol";

contract DeployLocalScript is DeployLocalContractsScript {
    function run() public override {
        super.run();
        new DeployFairDammScript().run();
        new CreateFairDammPoolScript().run();
        new ShipAndRegisterFairDammLiquidityScript().run();
        new WriteLocalDeploymentsScript().run();
    }
}
