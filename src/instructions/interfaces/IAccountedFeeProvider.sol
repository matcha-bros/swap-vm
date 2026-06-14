// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @notice Accounted dynamic fee provider interface.
interface IAccountedFeeProvider {
    /// @notice Returns fee execution and accounting routing data for the given order.
    /// @param orderHash The order or Aqua strategy hash.
    /// @param maker The liquidity provider.
    /// @param taker The swap taker.
    /// @param tokenIn The token paid by the taker.
    /// @param tokenOut The token received by the taker.
    /// @param isExactIn Whether the taker specified the input amount.
    /// @return feeBps Fee in bps where 1e9 = 100%.
    /// @return recipient Recipient for externally pulled fee tokens, or zero to reinvest.
    /// @return recordTarget Optional target that receives realized fee accounting.
    /// @return accountingKey Opaque key passed through to the record target.
    function getAccountedFeeState(
        bytes32 orderHash,
        address maker,
        address taker,
        address tokenIn,
        address tokenOut,
        bool isExactIn
    )
        external
        view
        returns (uint32 feeBps, address recipient, address recordTarget, bytes32 accountingKey);
}
