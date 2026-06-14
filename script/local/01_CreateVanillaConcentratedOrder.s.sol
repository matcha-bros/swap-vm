// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/main/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { Script, console2 } from "forge-std/Script.sol";
import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";

import { AquaSwapVMRouter } from "../../src/routers/AquaSwapVMRouter.sol";
import { ISwapVM } from "../../src/interfaces/ISwapVM.sol";
import { MakerTraitsLib } from "../../src/libs/MakerTraits.sol";
import { ControlsArgsBuilder } from "../../src/instructions/Controls.sol";
import { XYCConcentrateArgsBuilder } from "../../src/instructions/XYCConcentrate.sol";

interface ILocalERC20 {
    function mint(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
}

contract CreateVanillaConcentratedOrderScript is Script {
    uint8 internal constant XYC_CONCENTRATE_GROW_LIQUIDITY_2D = 18;
    uint8 internal constant SALT = 20;
    uint256 internal constant DEFAULT_BALANCE_A = 1_000e18;
    uint256 internal constant DEFAULT_BALANCE_B = 1_000e18;
    uint256 internal constant DEFAULT_SQRT_PRICE_MIN_X18 = 707106781186547524;
    uint256 internal constant DEFAULT_SQRT_PRICE_MAX_X18 = 1414213562373095048;

    function run() external {
        address maker = _maker();
        require(maker == _deployer(), "run with maker key");

        IAqua aqua = IAqua(vm.envAddress("LOCAL_AQUA_ADDRESS"));
        AquaSwapVMRouter router = AquaSwapVMRouter(payable(vm.envAddress("LOCAL_AQUA_SWAP_VM_ROUTER_ADDRESS")));
        ILocalERC20 tokenA = ILocalERC20(vm.envAddress("LOCAL_TOKEN_A_ADDRESS"));
        ILocalERC20 tokenB = ILocalERC20(vm.envAddress("LOCAL_TOKEN_B_ADDRESS"));

        ISwapVM.Order memory order = _buildOrder(maker, _vanillaProgram());

        vm.startBroadcast();
        bytes32 orderHash = _ship(aqua, router, tokenA, tokenB, order);
        vm.stopBroadcast();

        console2.log("Vanilla concentrated order:");
        console2.logBytes32(orderHash);
    }

    function _vanillaProgram() internal view returns (bytes memory) {
        bytes memory concentrateArgs = XYCConcentrateArgsBuilder.build2D(
            vm.envOr("LOCAL_SQRT_PRICE_MIN_X18", DEFAULT_SQRT_PRICE_MIN_X18),
            vm.envOr("LOCAL_SQRT_PRICE_MAX_X18", DEFAULT_SQRT_PRICE_MAX_X18)
        );
        bytes memory saltArgs = ControlsArgsBuilder.buildSalt(
            abi.encodePacked(vm.envOr("LOCAL_VANILLA_ORDER_SALT", bytes32("vanilla-concentrated")))
        );
        return bytes.concat(
            abi.encodePacked(XYC_CONCENTRATE_GROW_LIQUIDITY_2D, uint8(concentrateArgs.length), concentrateArgs),
            abi.encodePacked(SALT, uint8(saltArgs.length), saltArgs)
        );
    }

    function _buildOrder(address maker, bytes memory program) internal pure returns (ISwapVM.Order memory) {
        return MakerTraitsLib.build(MakerTraitsLib.Args({
            maker: maker,
            shouldUnwrapWeth: false,
            useAquaInsteadOfSignature: true,
            allowZeroAmountIn: false,
            receiver: address(0),
            hasPreTransferInHook: false,
            hasPostTransferInHook: false,
            hasPreTransferOutHook: false,
            hasPostTransferOutHook: false,
            preTransferInTarget: address(0),
            preTransferInData: "",
            postTransferInTarget: address(0),
            postTransferInData: "",
            preTransferOutTarget: address(0),
            preTransferOutData: "",
            postTransferOutTarget: address(0),
            postTransferOutData: "",
            program: program
        }));
    }

    function _ship(
        IAqua aqua,
        AquaSwapVMRouter router,
        ILocalERC20 tokenA,
        ILocalERC20 tokenB,
        ISwapVM.Order memory order
    )
        internal
        returns (bytes32 orderHash)
    {
        uint256 balanceA = vm.envOr("LOCAL_BALANCE_A", DEFAULT_BALANCE_A);
        uint256 balanceB = vm.envOr("LOCAL_BALANCE_B", DEFAULT_BALANCE_B);

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = balanceA;
        amounts[1] = balanceB;

        orderHash = router.hash(order);
        tokenA.mint(order.maker, balanceA);
        tokenB.mint(order.maker, balanceB);
        tokenA.approve(address(aqua), balanceA);
        tokenB.approve(address(aqua), balanceB);
        bytes32 strategyHash = aqua.ship(address(router), abi.encode(order), tokens, amounts);
        require(strategyHash == orderHash, "strategy hash mismatch");
    }

    function _deployer() internal returns (address) {
        address[] memory wallets = vm.getWallets();
        return wallets.length > 0 ? wallets[0] : msg.sender;
    }

    function _maker() internal returns (address) {
        return vm.envOr("LOCAL_MAKER_ADDRESS", _deployer());
    }
}
