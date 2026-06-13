// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @notice Receives realized fee accounting from an accounted dynamic fee opcode.
interface IAccountedFeeRecorder {
    /// @notice Records a realized fee after SwapVM has computed final swap amounts.
    /// @param accountingKey Opaque key returned by the fee provider.
    /// @param orderHash The order or Aqua strategy hash.
    /// @param maker The liquidity provider.
    /// @param taker The swap taker.
    /// @param tokenIn The token paid by the taker.
    /// @param tokenOut The token received by the taker.
    /// @param feeToken The token in which the fee was charged.
    /// @param feeAmount The realized fee amount.
    /// @param amountIn Final swap input amount.
    /// @param amountOut Final swap output amount.
    function recordAccountedFee(
        bytes32 accountingKey,
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
        external;
}
