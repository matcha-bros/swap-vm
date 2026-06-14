// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/main/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { AquaSwapVMTest } from "./base/AquaSwapVMTest.sol";
import { ISwapVM } from "../src/interfaces/ISwapVM.sol";
import { Fee, FeeArgsBuilder, BPS } from "../src/instructions/Fee.sol";
import { XYCConcentrate, XYCConcentrateArgsBuilder } from "../src/instructions/XYCConcentrate.sol";
import { Controls, ControlsArgsBuilder } from "../src/instructions/Controls.sol";
import { FairAuctionManager } from "../src/strategies/fair-damm/FairAuctionManager.sol";
import { MockFeeValueOracle } from "./mocks/MockFeeValueOracle.sol";
import { Program, ProgramBuilder } from "./utils/ProgramBuilder.sol";

contract FairAuctionManagerTest is AquaSwapVMTest {
    using ProgramBuilder for Program;

    uint32 private constant MIN_FEE_BPS = 0.01e9;
    uint32 private constant DEFAULT_FEE_BPS = 0.02e9;
    uint32 private constant MANAGER_FEE_BPS = 0.10e9;
    uint32 private constant MAX_FEE_BPS = 0.20e9;
    uint64 private constant EPOCH_LENGTH_BLOCKS = 1;

    FairAuctionManager private fairAuctionManager;
    MockFeeValueOracle private feeValueOracle;
    bytes32 private poolId;
    address private manager;

    function setUp() public override {
        super.setUp();

        manager = vm.addr(0xB1D);
        fairAuctionManager = new FairAuctionManager();
        feeValueOracle = new MockFeeValueOracle(address(this));
        feeValueOracle.setPrice(address(tokenA), 1e18);
        feeValueOracle.setPrice(address(tokenB), 1e18);

        poolId = fairAuctionManager.createPool(FairAuctionManager.PoolInit({
            aqua: aqua,
            router: ISwapVM(address(swapVM)),
            tokenA: address(tokenA),
            tokenB: address(tokenB),
            rentToken: IERC20(address(tokenA)),
            feeValueOracle: feeValueOracle,
            minFeeBps: MIN_FEE_BPS,
            defaultFeeBps: DEFAULT_FEE_BPS,
            maxFeeBps: MAX_FEE_BPS,
            epochLengthBlocks: EPOCH_LENGTH_BLOCKS,
            salt: bytes32("fair")
        }));
    }

    function test_FairAuction_DistributesRentByFeeContribution() public {
        ISwapVM.Order memory smallerPosition = _createAndRegisterPosition(bytes32("smaller"), INITIAL_BALANCE_A, INITIAL_BALANCE_B);
        ISwapVM.Order memory largerPosition = _createAndRegisterPosition(bytes32("larger"), INITIAL_BALANCE_A, INITIAL_BALANCE_B);
        uint256 smallerPositionId = fairAuctionManager.positionByOrderHash(swapVM.hash(smallerPosition));
        uint256 largerPositionId = fairAuctionManager.positionByOrderHash(swapVM.hash(largerPosition));

        uint256 rentAmount = 30e18;
        tokenA.mint(manager, rentAmount);
        vm.startPrank(manager);
        tokenA.approve(address(fairAuctionManager), rentAmount);
        fairAuctionManager.placeBid(poolId, rentAmount);
        vm.stopPrank();

        vm.roll(block.number + EPOCH_LENGTH_BLOCKS);
        fairAuctionManager.rollEpoch(poolId);
        vm.prank(manager);
        fairAuctionManager.setManagerFee(poolId, MANAGER_FEE_BPS);

        uint256 smallerSwapAmount = 100e18;
        uint256 largerSwapAmount = 300e18;
        _swapExactIn(smallerPosition, smallerSwapAmount);
        _swapExactIn(largerPosition, largerSwapAmount);

        uint256 smallerFeeValue = fairAuctionManager.positionFeeValue(smallerPositionId, 1);
        uint256 largerFeeValue = fairAuctionManager.positionFeeValue(largerPositionId, 1);
        uint256 totalFeeValue = fairAuctionManager.epochTotalFeeValue(poolId, 1);
        assertEq(smallerFeeValue, smallerSwapAmount * uint256(MANAGER_FEE_BPS) / BPS, "smaller fee contribution");
        assertEq(largerFeeValue, largerSwapAmount * uint256(MANAGER_FEE_BPS) / BPS, "larger fee contribution");
        assertEq(totalFeeValue, smallerFeeValue + largerFeeValue, "total fee value");
        assertEq(tokenA.balanceOf(manager), smallerFeeValue + largerFeeValue, "manager receives swap fees");

        vm.roll(block.number + EPOCH_LENGTH_BLOCKS);
        uint256 smallerRent = fairAuctionManager.claimableRent(poolId, smallerPositionId, 1);
        uint256 largerRent = fairAuctionManager.claimableRent(poolId, largerPositionId, 1);
        assertEq(smallerRent, Math.mulDiv(rentAmount, smallerFeeValue, totalFeeValue), "smaller rent share");
        assertEq(largerRent, Math.mulDiv(rentAmount, largerFeeValue, totalFeeValue), "larger rent share");
        assertEq(smallerRent + largerRent, rentAmount, "all rent distributed");
    }

    function test_FairAuction_DefaultFeeRecordsContributionWithoutManager() public {
        ISwapVM.Order memory order = _createAndRegisterPosition(bytes32("default"), INITIAL_BALANCE_A, INITIAL_BALANCE_B);
        uint256 positionId = fairAuctionManager.positionByOrderHash(swapVM.hash(order));

        _swapExactIn(order, 100e18);

        uint256 expectedFeeValue = 100e18 * uint256(DEFAULT_FEE_BPS) / BPS;
        assertEq(fairAuctionManager.positionFeeValue(positionId, 0), expectedFeeValue, "default fee contribution");
        assertEq(tokenA.balanceOf(address(0)), 0, "no external fee recipient before manager epoch");
    }

    function test_FairAuction_RejectsVanillaConcentratedOrder() public {
        ISwapVM.Order memory order = _createVanillaConcentratedOrder(bytes32("vanilla"));
        shipStrategy(order, tokenA, tokenB, INITIAL_BALANCE_A, INITIAL_BALANCE_B);

        vm.prank(maker);
        vm.expectRevert(FairAuctionManager.InvalidOrder.selector);
        fairAuctionManager.registerPosition(poolId, order);
    }

    function _createAndRegisterPosition(
        bytes32 salt,
        uint256 balanceA,
        uint256 balanceB
    )
        private
        returns (ISwapVM.Order memory order)
    {
        order = _createFairOrder(salt);
        bytes32 orderHash = shipStrategy(order, tokenA, tokenB, balanceA, balanceB);

        vm.prank(maker);
        uint256 positionId = fairAuctionManager.registerPosition(poolId, order);
        assertEq(fairAuctionManager.positionByOrderHash(orderHash), positionId, "registered position");
    }

    function _createFairOrder(bytes32 salt) private view returns (ISwapVM.Order memory) {
        Program memory p = ProgramBuilder.init(_opcodes());
        bytes memory program = bytes.concat(
            p.build(Fee._aquaAccountedDynamicFeeAmountInXD, FeeArgsBuilder.buildDynamicProtocolFee(address(fairAuctionManager))),
            p.build(
                XYCConcentrate._xycConcentrateGrowLiquidity2D,
                XYCConcentrateArgsBuilder.build2D(Math.sqrt(0.5e36), Math.sqrt(2e36))
            ),
            p.build(Controls._salt, ControlsArgsBuilder.buildSalt(abi.encodePacked(salt)))
        );

        return createStrategy(program);
    }

    function _createVanillaConcentratedOrder(bytes32 salt) private view returns (ISwapVM.Order memory) {
        Program memory p = ProgramBuilder.init(_opcodes());
        bytes memory program = bytes.concat(
            p.build(
                XYCConcentrate._xycConcentrateGrowLiquidity2D,
                XYCConcentrateArgsBuilder.build2D(Math.sqrt(0.5e36), Math.sqrt(2e36))
            ),
            p.build(Controls._salt, ControlsArgsBuilder.buildSalt(abi.encodePacked(salt)))
        );

        return createStrategy(program);
    }

    function _swapExactIn(ISwapVM.Order memory order, uint256 amountIn) private {
        SwapProgram memory swapProgram = SwapProgram({
            amount: amountIn,
            taker: taker,
            tokenA: tokenA,
            tokenB: tokenB,
            zeroForOne: true,
            isExactIn: true
        });
        mintTokenInToTaker(swapProgram);
        mintTokenInToMaker(swapProgram, amountIn);
        mintTokenOutToMaker(swapProgram, INITIAL_BALANCE_B);
        swap(swapProgram, order);
    }
}
