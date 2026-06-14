// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { console2 } from "forge-std/Script.sol";
import { ISwapVM } from "../../../src/interfaces/ISwapVM.sol";
import { MakerTraitsLib } from "../../../src/libs/MakerTraits.sol";
import { Fee, FeeArgsBuilder } from "../../../src/instructions/Fee.sol";
import { XYCConcentrate, XYCConcentrateArgsBuilder } from "../../../src/instructions/XYCConcentrate.sol";
import { Controls, ControlsArgsBuilder } from "../../../src/instructions/Controls.sol";

import { FairAuctionManager } from "../../../src/local/fair/FairAuctionManager.sol";
import { MockFeeValueOracle } from "../../../src/local/fair/mocks/MockFeeValueOracle.sol";
import { LocalAquaScript, LocalProgram, LocalProgramBuilder } from "./LocalAquaScript.sol";
import { LocalDeployments } from "../libraries/LocalDeployments.sol";

abstract contract LocalFairDammScript is LocalAquaScript {
    using LocalProgramBuilder for LocalProgram;

    FairAuctionManager internal immutable FAIR_AUCTION_MANAGER;
    MockFeeValueOracle internal immutable FAIR_FEE_VALUE_ORACLE;

    constructor() {
        FAIR_AUCTION_MANAGER = FairAuctionManager(LocalDeployments.fairAuctionManager());
        FAIR_FEE_VALUE_ORACLE = MockFeeValueOracle(LocalDeployments.fairFeeValueOracle());
    }

    function _fairPoolId() internal pure returns (bytes32) {
        (address token0, address token1) = LocalDeployments.tokenA() < LocalDeployments.tokenB()
            ? (LocalDeployments.tokenA(), LocalDeployments.tokenB())
            : (LocalDeployments.tokenB(), LocalDeployments.tokenA());

        return keccak256(
            abi.encode(
                LocalDeployments.fairAuctionManager(),
                LocalDeployments.aqua(),
                LocalDeployments.swapVmRouter(),
                token0,
                token1,
                LocalDeployments.tokenA(),
                LocalDeployments.fairFeeValueOracle(),
                LocalDeployments.FAIR_MIN_FEE_BPS,
                LocalDeployments.FAIR_DEFAULT_FEE_BPS,
                LocalDeployments.FAIR_MAX_FEE_BPS,
                LocalDeployments.FAIR_EPOCH_LENGTH_BLOCKS,
                LocalDeployments.FAIR_POOL_SALT
            )
        );
    }

    function _buildFairDammOrder(address maker, bytes32 positionSalt) internal pure returns (ISwapVM.Order memory) {
        LocalProgram memory p = LocalProgramBuilder.init(_opcodes());
        bytes memory program = bytes.concat(
            p.build(Fee._aquaAccountedDynamicFeeAmountInXD, FeeArgsBuilder.buildDynamicProtocolFee(LocalDeployments.fairAuctionManager())),
            p.build(
                XYCConcentrate._xycConcentrateGrowLiquidity2D,
                XYCConcentrateArgsBuilder.build2D(
                    LocalDeployments.WIDE_SQRT_PRICE_MIN_X18,
                    LocalDeployments.WIDE_SQRT_PRICE_MAX_X18
                )
            ),
            p.build(Controls._salt, ControlsArgsBuilder.buildSalt(abi.encodePacked(positionSalt)))
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

    function _logFairPool() internal view {
        bytes32 poolId = _fairPoolId();
        console2.log("Fair DAMM AuctionManager:", address(FAIR_AUCTION_MANAGER));
        console2.log("Fair DAMM FeeValueOracle:", address(FAIR_FEE_VALUE_ORACLE));
        console2.log("Fair DAMM pool id:");
        console2.logBytes32(poolId);
        console2.log("Current epoch:", FAIR_AUCTION_MANAGER.currentEpoch(poolId));
        console2.log("Active manager:", FAIR_AUCTION_MANAGER.activeManager(poolId));
        console2.log("Active fee bps:", FAIR_AUCTION_MANAGER.activeFee(poolId));
    }
}
