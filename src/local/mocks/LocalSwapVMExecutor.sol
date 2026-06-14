// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface ILocalAquaSwapVMRouter {
    struct Order {
        address maker;
        uint256 traits;
        bytes data;
    }

    function swap(
        Order calldata order,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        bytes calldata takerTraitsAndData
    ) external returns (uint256 amountIn, uint256 amountOut, bytes32 orderHash);
}

interface ILocalTychoExecutor {
    function swap(uint256 amountIn, bytes calldata data, address receiver) external payable;
}

error LocalSwapVMExecutorInvalidDataLength();
error LocalSwapVMExecutorUnsupportedVersion(uint8 version);
error LocalSwapVMExecutorZeroAddress();

contract LocalSwapVMExecutor is ILocalTychoExecutor {
    uint256 private constant _MIN_DATA_LENGTH = 114;
    uint8 private constant _VERSION_1 = 1;

    bytes private constant _EXACT_IN_AQUA_PUSH_TAKER_TRAITS =
        hex"00000000000000000000000000000000000000000041";

    function swap(uint256 amountIn, bytes calldata data, address) external payable {
        (
            address swapVMRouter,
            address maker,
            uint256 orderTraits,
            address tokenIn,
            address tokenOut,
            bytes calldata orderData
        ) = _decodeData(data);

        ILocalAquaSwapVMRouter(swapVMRouter).swap(
            ILocalAquaSwapVMRouter.Order({ maker: maker, traits: orderTraits, data: orderData }),
            tokenIn,
            tokenOut,
            amountIn,
            _EXACT_IN_AQUA_PUSH_TAKER_TRAITS
        );
    }

    function decodeTransferData(bytes calldata data)
        external
        pure
        returns (address swapVMRouter, address tokenIn, address tokenOut)
    {
        (swapVMRouter,,, tokenIn, tokenOut,) = _decodeData(data);
    }

    function _decodeData(bytes calldata data)
        internal
        pure
        returns (
            address swapVMRouter,
            address maker,
            uint256 orderTraits,
            address tokenIn,
            address tokenOut,
            bytes calldata orderData
        )
    {
        if (data.length < _MIN_DATA_LENGTH) revert LocalSwapVMExecutorInvalidDataLength();

        uint8 version = uint8(data[0]);
        if (version != _VERSION_1) revert LocalSwapVMExecutorUnsupportedVersion(version);

        swapVMRouter = address(bytes20(data[1:21]));
        maker = address(bytes20(data[21:41]));
        orderTraits = uint256(bytes32(data[41:73]));
        tokenIn = address(bytes20(data[73:93]));
        tokenOut = address(bytes20(data[93:113]));
        orderData = data[113:];

        if (swapVMRouter == address(0) || maker == address(0) || tokenIn == address(0) || tokenOut == address(0)) {
            revert LocalSwapVMExecutorZeroAddress();
        }
    }
}
