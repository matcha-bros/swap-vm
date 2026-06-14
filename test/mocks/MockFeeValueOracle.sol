// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IFeeValueOracle } from "../../src/strategies/fair-damm/interfaces/IFeeValueOracle.sol";

contract MockFeeValueOracle is IFeeValueOracle, Ownable {
    uint256 internal constant PRICE_SCALE = 1e18;

    mapping(address token => uint256 priceX18) public prices;

    event PriceSet(address indexed token, uint256 priceX18);

    error MissingPrice(address token);

    constructor(address owner_) Ownable(owner_) {}

    function setPrice(address token, uint256 priceX18) external onlyOwner {
        prices[token] = priceX18;
        emit PriceSet(token, priceX18);
    }

    function valueOf(address baseToken, uint256 baseAmount, address quoteToken) external view returns (uint256 quoteAmount) {
        uint256 basePrice = prices[baseToken];
        uint256 quotePrice = prices[quoteToken];
        require(basePrice > 0, MissingPrice(baseToken));
        require(quotePrice > 0, MissingPrice(quoteToken));

        uint8 baseDecimals = IERC20Metadata(baseToken).decimals();
        uint8 quoteDecimals = IERC20Metadata(quoteToken).decimals();
        uint256 valueX18 = Math.mulDiv(baseAmount, basePrice, 10 ** baseDecimals);
        quoteAmount = Math.mulDiv(valueX18, 10 ** quoteDecimals, quotePrice);
    }
}
