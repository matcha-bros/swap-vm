// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface ILocalERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ILocalSwapVMExecutorData {
    function decodeTransferData(bytes calldata data)
        external
        pure
        returns (address swapVMRouter, address tokenIn, address tokenOut);
}

interface ILocalTychoExecutor {
    function swap(uint256 amountIn, bytes calldata data, address receiver) external payable;
}

struct LocalClientFeeParams {
    uint16 clientFeeBps;
    address clientFeeReceiver;
    uint256 maxClientContribution;
    uint256 deadline;
    bytes clientSignature;
}

error LocalTychoRouterAddressZero();
error LocalTychoRouterNotOwner();
error LocalTychoRouterUnapprovedExecutor(address executor);
error LocalTychoRouterInvalidSwapData();
error LocalTychoRouterTransferFailed();
error LocalTychoRouterNegativeSlippage(uint256 amountOut, uint256 minAmountOut);

contract LocalTychoRouter {
    address public immutable owner;
    mapping(address => uint256) public executorsActivationTimestamp;

    event ExecutorSet(address indexed executor, uint256 timelockExpiresAt);
    event ExecutorRemoved(address indexed executor);

    constructor(address owner_) {
        if (owner_ == address(0)) revert LocalTychoRouterAddressZero();
        owner = owner_;
    }

    function setExecutors(address[] memory targets) external onlyOwner {
        for (uint256 i = 0; i < targets.length; i++) {
            address target = targets[i];
            if (target == address(0)) revert LocalTychoRouterAddressZero();
            executorsActivationTimestamp[target] = block.timestamp;
            emit ExecutorSet(target, block.timestamp);
        }
    }

    function removeExecutor(address target) external onlyOwner {
        delete executorsActivationTimestamp[target];
        emit ExecutorRemoved(target);
    }

    function singleSwap(
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        uint256 minAmountOut,
        address receiver,
        LocalClientFeeParams calldata,
        bytes calldata swapData
    ) external payable returns (uint256 amountOut) {
        if (receiver == address(0)) revert LocalTychoRouterAddressZero();
        if (swapData.length < 21) revert LocalTychoRouterInvalidSwapData();

        address executor = address(bytes20(swapData[0:20]));
        if (executorsActivationTimestamp[executor] == 0) revert LocalTychoRouterUnapprovedExecutor(executor);

        bytes calldata protocolData = swapData[20:];
        (address swapVMRouter, address executorTokenIn, address executorTokenOut) =
            ILocalSwapVMExecutorData(executor).decodeTransferData(protocolData);
        if (executorTokenIn != tokenIn || executorTokenOut != tokenOut) revert LocalTychoRouterInvalidSwapData();

        _safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        _forceApprove(tokenIn, swapVMRouter, amountIn);

        uint256 balanceBefore = ILocalERC20(tokenOut).balanceOf(address(this));
        (bool success, bytes memory result) =
            executor.delegatecall(abi.encodeWithSelector(ILocalTychoExecutor.swap.selector, amountIn, protocolData, receiver));
        if (!success) {
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }
        amountOut = ILocalERC20(tokenOut).balanceOf(address(this)) - balanceBefore;
        if (amountOut < minAmountOut) revert LocalTychoRouterNegativeSlippage(amountOut, minAmountOut);
        _safeTransfer(tokenOut, receiver, amountOut);
    }

    function splitSwap(
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 nTokens,
        address receiver,
        LocalClientFeeParams calldata,
        bytes calldata swaps
    ) external payable returns (uint256 amountOut) {
        if (receiver == address(0) || tokenIn == address(0) || tokenOut == address(0)) {
            revert LocalTychoRouterAddressZero();
        }
        if (amountIn == 0 || minAmountOut == 0 || swaps.length == 0 || nTokens < 2) {
            revert LocalTychoRouterInvalidSwapData();
        }

        address[] memory tokenByIndex = new address[](nTokens);
        uint256[] memory amounts = new uint256[](nTokens);
        uint256[] memory remainingAmounts = new uint256[](nTokens);
        tokenByIndex[0] = tokenIn;
        tokenByIndex[nTokens - 1] = tokenOut;
        amounts[0] = amountIn;
        remainingAmounts[0] = amountIn;

        _safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);

        uint256 cursor;
        while (cursor < swaps.length) {
            uint256 legLength = _readUint16(swaps, cursor);
            cursor += 2;
            if (legLength < 25 || cursor + legLength > swaps.length) revert LocalTychoRouterInvalidSwapData();

            uint8 tokenInIndex = uint8(swaps[cursor]);
            uint8 tokenOutIndex = uint8(swaps[cursor + 1]);
            uint24 split = _readUint24(swaps, cursor + 2);
            address executor = address(bytes20(swaps[cursor + 5:cursor + 25]));
            bytes calldata protocolData = swaps[cursor + 25:cursor + legLength];
            cursor += legLength;

            if (tokenInIndex >= nTokens || tokenOutIndex >= nTokens) revert LocalTychoRouterInvalidSwapData();
            if (executorsActivationTimestamp[executor] == 0) revert LocalTychoRouterUnapprovedExecutor(executor);

            (address swapVMRouter, address executorTokenIn, address executorTokenOut) =
                ILocalSwapVMExecutorData(executor).decodeTransferData(protocolData);
            _bindTokenIndex(tokenByIndex, tokenInIndex, executorTokenIn);
            _bindTokenIndex(tokenByIndex, tokenOutIndex, executorTokenOut);

            uint256 currentAmountIn = split > 0
                ? (amounts[tokenInIndex] * uint256(split)) / 0xffffff
                : remainingAmounts[tokenInIndex];
            if (currentAmountIn == 0 || remainingAmounts[tokenInIndex] < currentAmountIn) {
                revert LocalTychoRouterInvalidSwapData();
            }

            _forceApprove(executorTokenIn, swapVMRouter, currentAmountIn);
            uint256 balanceBefore = ILocalERC20(executorTokenOut).balanceOf(address(this));
            (bool success, bytes memory result) =
                executor.delegatecall(abi.encodeWithSelector(ILocalTychoExecutor.swap.selector, currentAmountIn, protocolData, address(this)));
            if (!success) {
                assembly {
                    revert(add(result, 0x20), mload(result))
                }
            }

            uint256 currentAmountOut = ILocalERC20(executorTokenOut).balanceOf(address(this)) - balanceBefore;
            amounts[tokenOutIndex] += currentAmountOut;
            remainingAmounts[tokenOutIndex] += currentAmountOut;
            remainingAmounts[tokenInIndex] -= currentAmountIn;
        }

        amountOut = amounts[nTokens - 1];
        if (amountOut < minAmountOut) revert LocalTychoRouterNegativeSlippage(amountOut, minAmountOut);
        _safeTransfer(tokenOut, receiver, amountOut);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert LocalTychoRouterNotOwner();
        _;
    }

    function _bindTokenIndex(address[] memory tokenByIndex, uint8 index, address token) internal pure {
        address existing = tokenByIndex[index];
        if (existing == address(0)) {
            tokenByIndex[index] = token;
        } else if (existing != token) {
            revert LocalTychoRouterInvalidSwapData();
        }
    }

    function _readUint16(bytes calldata data, uint256 offset) internal pure returns (uint16 value) {
        if (offset + 2 > data.length) revert LocalTychoRouterInvalidSwapData();
        value = (uint16(uint8(data[offset])) << 8) | uint16(uint8(data[offset + 1]));
    }

    function _readUint24(bytes calldata data, uint256 offset) internal pure returns (uint24 value) {
        if (offset + 3 > data.length) revert LocalTychoRouterInvalidSwapData();
        value = (uint24(uint8(data[offset])) << 16) | (uint24(uint8(data[offset + 1])) << 8) | uint24(uint8(data[offset + 2]));
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _safeApprove(token, spender, 0);
        _safeApprove(token, spender, amount);
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory result) = token.call(abi.encodeCall(ILocalERC20.approve, (spender, amount)));
        if (!success || (result.length != 0 && !abi.decode(result, (bool)))) revert LocalTychoRouterTransferFailed();
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory result) = token.call(abi.encodeCall(ILocalERC20.transfer, (to, amount)));
        if (!success || (result.length != 0 && !abi.decode(result, (bool)))) revert LocalTychoRouterTransferFailed();
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory result) = token.call(abi.encodeCall(ILocalERC20.transferFrom, (from, to, amount)));
        if (!success || (result.length != 0 && !abi.decode(result, (bool)))) revert LocalTychoRouterTransferFailed();
    }
}
