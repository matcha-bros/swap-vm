// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

import { Script, console2 } from "forge-std/Script.sol";
import { TokenMock } from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";
import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";

import { AquaSwapVMRouter } from "../../../src/routers/AquaSwapVMRouter.sol";
import { ISwapVM } from "../../../src/interfaces/ISwapVM.sol";
import { MakerTraitsLib } from "../../../src/libs/MakerTraits.sol";
import { TakerTraitsLib } from "../../../src/libs/TakerTraits.sol";
import { Context } from "../../../src/libs/VM.sol";
import { AquaOpcodes } from "../../../src/opcodes/AquaOpcodes.sol";
import { XYCSwap } from "../../../src/instructions/XYCSwap.sol";
import { Controls, ControlsArgsBuilder } from "../../../src/instructions/Controls.sol";

struct LocalProgram {
    function(Context memory, bytes calldata) internal[] opcodes;
}

library LocalProgramBuilder {
    error OpcodeNotFound();

    function init(function(Context memory, bytes calldata) internal[] memory opcodes) internal pure returns (LocalProgram memory) {
        return LocalProgram({ opcodes: opcodes });
    }

    function build(LocalProgram memory self, function(Context memory, bytes calldata) internal instruction) internal pure returns (bytes memory) {
        return build(self, instruction, "");
    }

    function build(LocalProgram memory self, function(Context memory, bytes calldata) internal instruction, bytes memory args) internal pure returns (bytes memory) {
        uint8 opcode = findOpcode(self, instruction);
        return abi.encodePacked(opcode, uint8(args.length), args);
    }

    function findOpcode(LocalProgram memory self, function(Context memory, bytes calldata) internal targetOpcode) internal pure returns (uint8) {
        for (uint256 i = 0; i < self.opcodes.length; i++) {
            if (self.opcodes[i] == targetOpcode) return uint8(i);
        }
        revert OpcodeNotFound();
    }
}

abstract contract LocalAquaScript is Script, AquaOpcodes {
    using LocalProgramBuilder for LocalProgram;

    uint256 internal constant DEFAULT_POOL_BALANCE_A = 1_000e18;
    uint256 internal constant DEFAULT_POOL_BALANCE_B = 1_000e18;
    uint256 internal constant DEFAULT_ADD_LIQUIDITY_A = 100e18;
    uint256 internal constant DEFAULT_ADD_LIQUIDITY_B = 100e18;
    uint256 internal constant DEFAULT_SWAP_AMOUNT_IN = 10e18;
    bytes32 internal constant DEFAULT_POOL_SALT = bytes32(uint256(1));

    IAqua internal immutable aqua;
    AquaSwapVMRouter internal immutable router;

    constructor() AquaOpcodes(vm.envAddress("OPS_AQUA_ADDRESS")) {
        aqua = IAqua(vm.envAddress("OPS_AQUA_ADDRESS"));
        router = AquaSwapVMRouter(payable(vm.envAddress("OPS_AQUA_SWAP_VM_ROUTER_ADDRESS")));
    }

    function _deployer() internal returns (address) {
        address[] memory wallets = vm.getWallets();
        return wallets.length > 0 ? wallets[0] : msg.sender;
    }

    function _maker() internal returns (address) {
        return vm.envOr("OPS_MAKER_ADDRESS", _deployer());
    }

    function _tokenA() internal view returns (TokenMock) {
        return TokenMock(vm.envAddress("OPS_TOKEN_A_ADDRESS"));
    }

    function _tokenB() internal view returns (TokenMock) {
        return TokenMock(vm.envAddress("OPS_TOKEN_B_ADDRESS"));
    }

    function _poolSalt() internal view returns (bytes32) {
        return vm.envOr("LOCAL_POOL_SALT", DEFAULT_POOL_SALT);
    }

    function _buildConstantProductOrder(address maker) internal view returns (ISwapVM.Order memory) {
        LocalProgram memory p = LocalProgramBuilder.init(_opcodes());
        bytes memory program = bytes.concat(
            p.build(XYCSwap._xycSwapXD),
            p.build(Controls._salt, ControlsArgsBuilder.buildSalt(abi.encodePacked(_poolSalt())))
        );

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

    function _buildExactInTakerData(address taker, uint256 amountOutMin) internal pure returns (bytes memory) {
        bytes memory threshold = amountOutMin > 0 ? abi.encodePacked(bytes32(amountOutMin)) : bytes("");
        return TakerTraitsLib.build(TakerTraitsLib.Args({
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
        }));
    }

    function _logPool(address maker, ISwapVM.Order memory order, address tokenA, address tokenB) internal view {
        bytes32 orderHash = router.hash(order);
        (uint256 balanceA,) = aqua.rawBalances(maker, address(router), orderHash, tokenA);
        (uint256 balanceB,) = aqua.rawBalances(maker, address(router), orderHash, tokenB);

        console2.log("Aqua:", address(aqua));
        console2.log("AquaSwapVMRouter:", address(router));
        console2.log("Maker:", maker);
        console2.log("TokenA:", tokenA);
        console2.log("TokenB:", tokenB);
        console2.logBytes32(orderHash);
        console2.log("Aqua balance A:", balanceA);
        console2.log("Aqua balance B:", balanceB);
    }
}
