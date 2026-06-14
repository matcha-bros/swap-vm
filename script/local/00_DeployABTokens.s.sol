// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/main/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { Script, console2 } from "forge-std/Script.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Create2Utils } from "./utils/Create2Utils.sol";

contract LocalERC20Mock is ERC20 {
    uint8 private immutable _tokenDecimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _tokenDecimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _tokenDecimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract DeployABTokensScript is Script {
    bytes32 internal constant TOKEN_A_SALT = keccak256("swap-vm.local.token-a.v1");
    bytes32 internal constant TOKEN_B_SALT = keccak256("swap-vm.local.token-b.v1");

    function run() external {
        bytes memory tokenAInitCode = abi.encodePacked(type(LocalERC20Mock).creationCode, abi.encode("Token A", "A", uint8(18)));
        bytes memory tokenBInitCode = abi.encodePacked(type(LocalERC20Mock).creationCode, abi.encode("Token B", "B", uint8(18)));

        vm.startBroadcast();
        (address tokenA, bool tokenAExisted) = Create2Utils.getOrDeploy(tokenAInitCode, TOKEN_A_SALT);
        (address tokenB, bool tokenBExisted) = Create2Utils.getOrDeploy(tokenBInitCode, TOKEN_B_SALT);
        vm.stopBroadcast();

        console2.log("Token A:", tokenA);
        console2.log("Token A existed:", tokenAExisted);
        console2.log("Token B:", tokenB);
        console2.log("Token B existed:", tokenBExisted);
        console2.log("Set LOCAL_TOKEN_A_ADDRESS and LOCAL_TOKEN_B_ADDRESS to these addresses.");
    }
}
