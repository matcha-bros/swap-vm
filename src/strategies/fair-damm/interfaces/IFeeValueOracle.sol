// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IFeeValueOracle {
    function valueOf(address baseToken, uint256 baseAmount, address quoteToken) external view returns (uint256 quoteAmount);
}
