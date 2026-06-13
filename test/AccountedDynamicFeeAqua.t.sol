// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/main/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { AquaSwapVMTest } from "./base/AquaSwapVMTest.sol";

import { ISwapVM } from "../src/interfaces/ISwapVM.sol";
import { BPS, Fee, FeeArgsBuilder } from "../src/instructions/Fee.sol";
import { XYCSwap } from "../src/instructions/XYCSwap.sol";
import { XYCConcentrate } from "../src/instructions/XYCConcentrate.sol";
import { Controls } from "../src/instructions/Controls.sol";
import { PeggedSwap } from "../src/instructions/PeggedSwap.sol";
import { Extruction } from "../src/instructions/Extruction.sol";
import { IAccountedFeeProvider } from "../src/instructions/interfaces/IAccountedFeeProvider.sol";
import { IAccountedFeeRecorder } from "../src/instructions/interfaces/IAccountedFeeRecorder.sol";
import { Context } from "../src/libs/VM.sol";
import { Program, ProgramBuilder } from "./utils/ProgramBuilder.sol";

contract AccountedFeeTargetMock is IAccountedFeeProvider, IAccountedFeeRecorder {
    uint32 public feeBps;
    address public recipient;
    address public recordTarget;
    bytes32 public accountingKey;
    bool public shouldRevertState;
    bool public shouldRevertRecord;
    bytes public reenterCalldata;
    address public reenterTarget;

    uint256 public stateCallCount;
    uint256 public recordCallCount;
    bytes32 public lastAccountingKey;
    bytes32 public lastOrderHash;
    address public lastMaker;
    address public lastTaker;
    address public lastTokenIn;
    address public lastTokenOut;
    address public lastFeeToken;
    uint256 public lastFeeAmount;
    uint256 public lastAmountIn;
    uint256 public lastAmountOut;

    function setFeeState(uint32 feeBps_, address recipient_, address recordTarget_, bytes32 accountingKey_) external {
        feeBps = feeBps_;
        recipient = recipient_;
        recordTarget = recordTarget_;
        accountingKey = accountingKey_;
    }

    function setShouldRevertState(bool shouldRevertState_) external {
        shouldRevertState = shouldRevertState_;
    }

    function setShouldRevertRecord(bool shouldRevertRecord_) external {
        shouldRevertRecord = shouldRevertRecord_;
    }

    function setReenter(address target, bytes calldata data) external {
        reenterTarget = target;
        reenterCalldata = data;
    }

    function getAccountedFeeState(
        bytes32,
        address,
        address,
        address,
        address,
        bool
    )
        external
        view
        returns (uint32, address, address, bytes32)
    {
        if (shouldRevertState) revert("fee state failed");
        return (feeBps, recipient, recordTarget, accountingKey);
    }

    function recordAccountedFee(
        bytes32 accountingKey_,
        bytes32 orderHash,
        address maker,
        address taker,
        address tokenIn,
        address tokenOut,
        address feeToken,
        uint256 feeAmount,
        uint256 amountIn,
        uint256 amountOut
    )
        external
    {
        if (shouldRevertRecord) revert("record failed");
        if (reenterTarget != address(0)) {
            (bool success,) = reenterTarget.call(reenterCalldata);
            require(!success, "reentry succeeded");
        }

        recordCallCount++;
        lastAccountingKey = accountingKey_;
        lastOrderHash = orderHash;
        lastMaker = maker;
        lastTaker = taker;
        lastTokenIn = tokenIn;
        lastTokenOut = tokenOut;
        lastFeeToken = feeToken;
        lastFeeAmount = feeAmount;
        lastAmountIn = amountIn;
        lastAmountOut = amountOut;
    }
}

contract MalformedAccountedFeeTargetMock {
    fallback() external payable {
        assembly ("memory-safe") {
            mstore(0, 1)
            return(0, 32)
        }
    }
}

contract AccountedDynamicFeeAquaTest is AquaSwapVMTest {
    using ProgramBuilder for Program;

    AccountedFeeTargetMock internal feeTarget;
    MalformedAccountedFeeTargetMock internal malformedFeeTarget;
    bytes32 internal constant ACCOUNTING_KEY = keccak256("accounting-key");

    function setUp() public override {
        super.setUp();
        feeTarget = new AccountedFeeTargetMock();
        malformedFeeTarget = new MalformedAccountedFeeTargetMock();
    }

    function _order(address target) internal view returns (ISwapVM.Order memory) {
        Program memory p = ProgramBuilder.init(_opcodes());
        return createStrategy(bytes.concat(
            p.build(Fee._aquaAccountedDynamicFeeAmountInXD, FeeArgsBuilder.buildDynamicProtocolFee(target)),
            p.build(XYCSwap._xycSwapXD),
            p.build(Controls._salt, abi.encodePacked(bytes32("accounted-fee-test")))
        ));
    }

    function _swapProgram(uint256 amount, bool isExactIn) internal view returns (SwapProgram memory) {
        return SwapProgram({
            amount: amount,
            taker: taker,
            tokenA: tokenA,
            tokenB: tokenB,
            zeroForOne: true,
            isExactIn: isExactIn
        });
    }

    function _ship(ISwapVM.Order memory order) internal returns (bytes32 strategyHash) {
        strategyHash = shipStrategy(order, tokenA, tokenB, INITIAL_BALANCE_A, INITIAL_BALANCE_B);
    }

    function _mintFor(SwapProgram memory swapProgram, uint256 tokenInAmount, uint256 tokenOutAmount) internal {
        mintTokenInToTaker(swapProgram, tokenInAmount);
        mintTokenInToMaker(swapProgram, tokenInAmount);
        mintTokenOutToMaker(swapProgram, tokenOutAmount);
    }

    function test_AccountedDynamicFee_QuoteSkipsPullAndRecord() public {
        feeTarget.setFeeState(0.10e9, protocolFeeRecipient, address(feeTarget), ACCOUNTING_KEY);
        ISwapVM.Order memory order = _order(address(feeTarget));
        bytes32 strategyHash = _ship(order);
        SwapProgram memory swapProgram = _swapProgram(100e18, true);

        (uint256 makerBalanceABefore,) = getAquaBalances(strategyHash);
        uint256 recipientBalanceBefore = tokenA.balanceOf(protocolFeeRecipient);

        (uint256 amountIn, uint256 amountOut) = quote(swapProgram, order);

        (uint256 makerBalanceAAfter,) = getAquaBalances(strategyHash);
        assertEq(amountIn, 100e18);
        assertGt(amountOut, 0);
        assertEq(makerBalanceAAfter, makerBalanceABefore);
        assertEq(tokenA.balanceOf(protocolFeeRecipient), recipientBalanceBefore);
        assertEq(feeTarget.recordCallCount(), 0);
    }

    function test_AccountedDynamicFee_ExactIn_PullsFeeAndRecords() public {
        feeTarget.setFeeState(0.10e9, protocolFeeRecipient, address(feeTarget), ACCOUNTING_KEY);
        ISwapVM.Order memory order = _order(address(feeTarget));
        bytes32 strategyHash = _ship(order);
        SwapProgram memory swapProgram = _swapProgram(100e18, true);
        _mintFor(swapProgram, 100e18, 200e18);

        (uint256 makerBalanceABefore,) = getAquaBalances(strategyHash);
        uint256 recipientBalanceBefore = tokenA.balanceOf(protocolFeeRecipient);

        (uint256 amountIn, uint256 amountOut) = swap(swapProgram, order);

        uint256 expectedFee = amountIn * 0.10e9 / BPS;
        uint256 expectedAmountOut = INITIAL_BALANCE_B * (amountIn - expectedFee) / (INITIAL_BALANCE_A + amountIn - expectedFee);
        (uint256 makerBalanceAAfter,) = getAquaBalances(strategyHash);

        assertEq(amountIn, 100e18);
        assertEq(amountOut, expectedAmountOut);
        assertEq(tokenA.balanceOf(protocolFeeRecipient) - recipientBalanceBefore, expectedFee);
        assertEq(makerBalanceAAfter, makerBalanceABefore + amountIn - expectedFee);
        _assertRecord(order, amountIn, amountOut, expectedFee);
    }

    function test_AccountedDynamicFee_ExactOut_PullsFeeAndRecords() public {
        feeTarget.setFeeState(0.10e9, protocolFeeRecipient, address(feeTarget), ACCOUNTING_KEY);
        ISwapVM.Order memory order = _order(address(feeTarget));
        bytes32 strategyHash = _ship(order);
        SwapProgram memory swapProgram = _swapProgram(100e18, false);
        _mintFor(swapProgram, 400e18, 200e18);

        (uint256 makerBalanceABefore,) = getAquaBalances(strategyHash);
        uint256 recipientBalanceBefore = tokenA.balanceOf(protocolFeeRecipient);

        (uint256 amountIn, uint256 amountOut) = swap(swapProgram, order);

        uint256 baseAmountIn = Math.ceilDiv(INITIAL_BALANCE_A * amountOut, INITIAL_BALANCE_B - amountOut);
        uint256 expectedFee = baseAmountIn * 0.10e9 / (BPS - 0.10e9);
        (uint256 makerBalanceAAfter,) = getAquaBalances(strategyHash);

        assertApproxEqAbs(amountIn, baseAmountIn + expectedFee, 1);
        assertEq(amountOut, 100e18);
        assertApproxEqAbs(tokenA.balanceOf(protocolFeeRecipient) - recipientBalanceBefore, expectedFee, 1);
        assertApproxEqAbs(makerBalanceAAfter, makerBalanceABefore + amountIn - expectedFee, 1);
        _assertRecord(order, amountIn, amountOut, expectedFee);
    }

    function test_AccountedDynamicFee_RecipientZero_ReinvestsFeeAndRecords() public {
        feeTarget.setFeeState(0.10e9, address(0), address(feeTarget), ACCOUNTING_KEY);
        ISwapVM.Order memory order = _order(address(feeTarget));
        bytes32 strategyHash = _ship(order);
        SwapProgram memory swapProgram = _swapProgram(100e18, true);
        _mintFor(swapProgram, 100e18, 200e18);

        (uint256 makerBalanceABefore,) = getAquaBalances(strategyHash);

        (uint256 amountIn, uint256 amountOut) = swap(swapProgram, order);

        uint256 expectedFee = amountIn * 0.10e9 / BPS;
        (uint256 makerBalanceAAfter,) = getAquaBalances(strategyHash);

        assertEq(tokenA.balanceOf(protocolFeeRecipient), 0);
        assertEq(makerBalanceAAfter, makerBalanceABefore + amountIn);
        _assertRecord(order, amountIn, amountOut, expectedFee);
    }

    function test_AccountedDynamicFee_RecordTargetZero_SkipsRecord() public {
        feeTarget.setFeeState(0.10e9, protocolFeeRecipient, address(0), ACCOUNTING_KEY);
        ISwapVM.Order memory order = _order(address(feeTarget));
        SwapProgram memory swapProgram = _swapProgram(100e18, true);
        _ship(order);
        _mintFor(swapProgram, 100e18, 200e18);

        swap(swapProgram, order);

        assertGt(tokenA.balanceOf(protocolFeeRecipient), 0);
        assertEq(feeTarget.recordCallCount(), 0);
    }

    function test_AccountedDynamicFee_ZeroFee_CanRecordWithoutPull() public {
        feeTarget.setFeeState(0, protocolFeeRecipient, address(feeTarget), ACCOUNTING_KEY);
        ISwapVM.Order memory order = _order(address(feeTarget));
        SwapProgram memory swapProgram = _swapProgram(100e18, true);
        _ship(order);
        _mintFor(swapProgram, 100e18, 200e18);

        (uint256 amountIn, uint256 amountOut) = swap(swapProgram, order);

        assertEq(tokenA.balanceOf(protocolFeeRecipient), 0);
        _assertRecord(order, amountIn, amountOut, 0);
    }

    function test_AccountedDynamicFee_FeeStateRevert_Reverts() public {
        feeTarget.setShouldRevertState(true);
        ISwapVM.Order memory order = _order(address(feeTarget));
        SwapProgram memory swapProgram = _swapProgram(100e18, true);
        _ship(order);
        _mintFor(swapProgram, 100e18, 200e18);

        vm.expectRevert(Fee.FeeAccountedProviderFailedCall.selector);
        swap(swapProgram, order);
    }

    function test_AccountedDynamicFee_MalformedFeeState_Reverts() public {
        ISwapVM.Order memory order = _order(address(malformedFeeTarget));
        SwapProgram memory swapProgram = _swapProgram(100e18, true);
        _ship(order);
        _mintFor(swapProgram, 100e18, 200e18);

        vm.expectRevert(Fee.FeeAccountedProviderFailedCall.selector);
        swap(swapProgram, order);
    }

    function test_AccountedDynamicFee_FeeBpsOutOfRange_Reverts() public {
        feeTarget.setFeeState(uint32(BPS + 1), protocolFeeRecipient, address(feeTarget), ACCOUNTING_KEY);
        ISwapVM.Order memory order = _order(address(feeTarget));
        SwapProgram memory swapProgram = _swapProgram(100e18, true);
        _ship(order);
        _mintFor(swapProgram, 100e18, 200e18);

        vm.expectRevert(abi.encodeWithSelector(Fee.FeeBpsOutOfRange.selector, BPS + 1));
        swap(swapProgram, order);
    }

    function test_AccountedDynamicFee_RecordRevert_RollsBackFeePull() public {
        feeTarget.setFeeState(0.10e9, protocolFeeRecipient, address(feeTarget), ACCOUNTING_KEY);
        feeTarget.setShouldRevertRecord(true);
        ISwapVM.Order memory order = _order(address(feeTarget));
        bytes32 strategyHash = _ship(order);
        SwapProgram memory swapProgram = _swapProgram(100e18, true);
        _mintFor(swapProgram, 100e18, 200e18);

        (uint256 makerBalanceABefore,) = getAquaBalances(strategyHash);

        vm.expectRevert("record failed");
        swap(swapProgram, order);

        (uint256 makerBalanceAAfter,) = getAquaBalances(strategyHash);
        assertEq(tokenA.balanceOf(protocolFeeRecipient), 0);
        assertEq(makerBalanceAAfter, makerBalanceABefore);
    }

    function test_AccountedDynamicFee_RecorderSameOrderReentryFails() public {
        feeTarget.setFeeState(0.10e9, protocolFeeRecipient, address(feeTarget), ACCOUNTING_KEY);
        ISwapVM.Order memory order = _order(address(feeTarget));
        SwapProgram memory swapProgram = _swapProgram(100e18, true);
        _ship(order);
        _mintFor(swapProgram, 100e18, 200e18);

        bytes memory reenterData = abi.encodeCall(
            swapVM.swap,
            (order, address(tokenA), address(tokenB), uint256(1e18), takerData(address(feeTarget), true))
        );
        feeTarget.setReenter(address(swapVM), reenterData);

        swap(swapProgram, order);

        assertEq(feeTarget.recordCallCount(), 1);
    }

    function test_AccountedDynamicFee_AquaOpcodeIndicesAreStable() public view {
        Program memory p = ProgramBuilder.init(_opcodes());

        assertEq(uint8(p.build(XYCSwap._xycSwapXD)[0]), 17);
        assertEq(uint8(p.build(XYCConcentrate._xycConcentrateGrowLiquidity2D)[0]), 18);
        assertEq(uint8(p.build(Controls._salt)[0]), 20);
        assertEq(uint8(p.build(Fee._flatFeeAmountInXD)[0]), 21);
        assertEq(uint8(p.build(Fee._dynamicProtocolFeeAmountInXD)[0]), 29);
        assertEq(uint8(p.build(Fee._aquaDynamicProtocolFeeAmountInXD)[0]), 30);
        assertEq(uint8(p.build(PeggedSwap._peggedSwapGrowPriceRange2D)[0]), 31);
        assertEq(uint8(p.build(Extruction._extruction)[0]), 32);
        assertEq(uint8(p.build(Fee._aquaAccountedDynamicFeeAmountInXD)[0]), 33);
    }

    function _assertRecord(ISwapVM.Order memory order, uint256 amountIn, uint256 amountOut, uint256 feeAmount) internal view {
        assertEq(feeTarget.recordCallCount(), 1);
        assertEq(feeTarget.lastAccountingKey(), ACCOUNTING_KEY);
        assertEq(feeTarget.lastOrderHash(), swapVM.hash(order));
        assertEq(feeTarget.lastMaker(), maker);
        assertEq(feeTarget.lastTaker(), address(taker));
        assertEq(feeTarget.lastTokenIn(), address(tokenA));
        assertEq(feeTarget.lastTokenOut(), address(tokenB));
        assertEq(feeTarget.lastFeeToken(), address(tokenA));
        assertApproxEqAbs(feeTarget.lastFeeAmount(), feeAmount, 1);
        assertEq(feeTarget.lastAmountIn(), amountIn);
        assertEq(feeTarget.lastAmountOut(), amountOut);
    }
}
