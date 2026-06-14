// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script, console2 } from "forge-std/Script.sol";
import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";
import { AquaSwapVMRouter } from "../../../src/routers/AquaSwapVMRouter.sol";
import { ISwapVM } from "../../../src/interfaces/ISwapVM.sol";
import { MakerTraitsLib } from "../../../src/libs/MakerTraits.sol";
import { TakerTraitsLib } from "../../../src/libs/TakerTraits.sol";
import { Context } from "../../../src/libs/VM.sol";
import { AquaOpcodes } from "../../../src/opcodes/AquaOpcodes.sol";
import { XYCConcentrate, XYCConcentrateArgsBuilder } from "../../../src/instructions/XYCConcentrate.sol";
import { Controls, ControlsArgsBuilder } from "../../../src/instructions/Controls.sol";
import { LocalERC20Mock as MockERC20 } from "../../../src/local/mocks/LocalERC20Mock.sol";
import { WETHMock } from "../../../src/local/mocks/WETHMock.sol";

import { LocalDeployments } from "../libraries/LocalDeployments.sol";

struct LocalProgram {
    function(Context memory, bytes calldata) internal[] opcodes;
}

library LocalProgramBuilder {
    error OpcodeNotFound();

    function init(function(Context memory, bytes calldata) internal[] memory opcodes)
        internal
        pure
        returns (LocalProgram memory)
    {
        return LocalProgram({ opcodes: opcodes });
    }

    function build(
        LocalProgram memory self,
        function(Context memory, bytes calldata) internal instruction
    )
        internal
        pure
        returns (bytes memory)
    {
        return build(self, instruction, "");
    }

    function build(
        LocalProgram memory self,
        function(Context memory, bytes calldata) internal instruction,
        bytes memory args
    )
        internal
        pure
        returns (bytes memory)
    {
        uint8 opcode = findOpcode(self, instruction);
        return abi.encodePacked(opcode, uint8(args.length), args);
    }

    function findOpcode(
        LocalProgram memory self,
        function(Context memory, bytes calldata) internal targetOpcode
    )
        internal
        pure
        returns (uint8)
    {
        for (uint256 i = 0; i < self.opcodes.length; i++) {
            require(i <= type(uint8).max, "opcode index overflow");
            if (self.opcodes[i] == targetOpcode) {
                // forge-lint: disable-next-line(unsafe-typecast)
                return uint8(i);
            }
        }
        revert OpcodeNotFound();
    }
}

abstract contract LocalAquaScript is Script, AquaOpcodes {
    using LocalProgramBuilder for LocalProgram;

    IAqua internal immutable AQUA;
    AquaSwapVMRouter internal immutable ROUTER;

    constructor() AquaOpcodes(LocalDeployments.aqua()) {
        AQUA = IAqua(LocalDeployments.aqua());
        ROUTER = AquaSwapVMRouter(payable(LocalDeployments.swapVmRouter()));
    }

    function _deployer() internal returns (address) {
        address[] memory wallets = vm.getWallets();
        return wallets.length > 0 ? wallets[0] : msg.sender;
    }

    function _maker() internal pure returns (address) {
        return LocalDeployments.DEFAULT_OWNER;
    }

    function _tokenA() internal pure returns (MockERC20) {
        return MockERC20(LocalDeployments.tokenA());
    }

    function _tokenB() internal pure returns (MockERC20) {
        return MockERC20(LocalDeployments.tokenB());
    }

    function _weth() internal pure returns (WETHMock) {
        return WETHMock(payable(LocalDeployments.weth()));
    }

    function _usdc() internal pure returns (MockERC20) {
        return MockERC20(LocalDeployments.usdc());
    }

    function _wbtc() internal pure returns (MockERC20) {
        return MockERC20(LocalDeployments.wbtc());
    }

    function _buildConstantProductOrder(address maker) internal pure returns (ISwapVM.Order memory) {
        return _buildWidePoolOrder(maker);
    }

    function _buildWidePoolOrder(address maker) internal pure returns (ISwapVM.Order memory) {
        return _buildConcentratedPoolOrder(
            maker,
            LocalDeployments.WIDE_POOL_SALT,
            LocalDeployments.WIDE_SQRT_PRICE_MIN_X18,
            LocalDeployments.WIDE_SQRT_PRICE_MAX_X18
        );
    }

    function _buildStablePoolOrder(address maker) internal pure returns (ISwapVM.Order memory) {
        return _buildConcentratedPoolOrder(
            maker,
            LocalDeployments.STABLE_POOL_SALT,
            LocalDeployments.STABLE_SQRT_PRICE_MIN_X18,
            LocalDeployments.STABLE_SQRT_PRICE_MAX_X18
        );
    }

    function _buildConcentratedPoolOrder(
        address maker,
        bytes32 poolSalt,
        uint256 sqrtPriceMinX18,
        uint256 sqrtPriceMaxX18
    )
        internal
        pure
        returns (ISwapVM.Order memory)
    {
        LocalProgram memory p = LocalProgramBuilder.init(_opcodes());
        bytes memory program = bytes.concat(
            p.build(
                XYCConcentrate._xycConcentrateGrowLiquidity2D,
                XYCConcentrateArgsBuilder.build2D(
                    sqrtPriceMinX18,
                    sqrtPriceMaxX18
                )
            ),
            p.build(Controls._salt, ControlsArgsBuilder.buildSalt(abi.encodePacked(poolSalt)))
        );

        return MakerTraitsLib.build(
            MakerTraitsLib.Args({
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
            })
        );
    }

    function _buildExactInTakerData(address taker, uint256 amountOutMin) internal pure returns (bytes memory) {
        bytes memory threshold = amountOutMin > 0 ? abi.encodePacked(bytes32(amountOutMin)) : bytes("");
        return TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: taker,
                isExactIn: true,
                shouldUnwrapWeth: false,
                isStrictThresholdAmount: false,
                isFirstTransferFromTaker: false,
                useTransferFromAndAquaPush: true,
                threshold: threshold,
                to: address(0),
                deadline: 0,
                hasPreTransferInCallback: false,
                hasPreTransferOutCallback: false,
                preTransferInHookData: "",
                postTransferInHookData: "",
                preTransferOutHookData: "",
                postTransferOutHookData: "",
                preTransferInCallbackData: "",
                preTransferOutCallbackData: "",
                instructionsArgs: "",
                signature: ""
            })
        );
    }

    function _logDeployments() internal pure {
        console2.log("AquaRouter:", LocalDeployments.aqua());
        console2.log("WETH:", LocalDeployments.weth());
        console2.log("AquaSwapVMRouter:", LocalDeployments.swapVmRouter());
        console2.log("Token A:", LocalDeployments.tokenA());
        console2.log("Token B:", LocalDeployments.tokenB());
        console2.log("USDC:", LocalDeployments.usdc());
        console2.log("WBTC:", LocalDeployments.wbtc());
    }

    function _logPool(address maker, ISwapVM.Order memory order, address tokenA, address tokenB) internal view {
        bytes32 orderHash = ROUTER.hash(order);
        (uint256 balanceA,) = AQUA.rawBalances(maker, address(ROUTER), orderHash, tokenA);
        (uint256 balanceB,) = AQUA.rawBalances(maker, address(ROUTER), orderHash, tokenB);

        _logDeployments();
        console2.log("Maker:", maker);
        console2.logBytes32(orderHash);
        console2.log("Aqua balance Token A:", balanceA);
        console2.log("Aqua balance Token B:", balanceB);
    }

    function _logPairPool(
        string memory label,
        address maker,
        ISwapVM.Order memory order,
        address token0,
        address token1
    )
        internal
        view
    {
        bytes32 orderHash = ROUTER.hash(order);
        (uint256 balance0,) = AQUA.rawBalances(maker, address(ROUTER), orderHash, token0);
        (uint256 balance1,) = AQUA.rawBalances(maker, address(ROUTER), orderHash, token1);

        console2.log(label);
        console2.logBytes32(orderHash);
        console2.log("Token 0:", token0);
        console2.log("Token 1:", token1);
        console2.log("Aqua balance token 0:", balance0);
        console2.log("Aqua balance token 1:", balance1);
    }
}
