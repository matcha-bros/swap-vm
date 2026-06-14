// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { AquaRouter } from "@1inch/aqua/src/AquaRouter.sol";

import { FairAuctionManager } from "../../../src/local/fair/FairAuctionManager.sol";
import { MockFeeValueOracle } from "../../../src/local/fair/mocks/MockFeeValueOracle.sol";
import { LocalAquaSwapVMRouter } from "../../../src/local/mocks/LocalAquaSwapVMRouter.sol";
import { LocalERC20Mock } from "../../../src/local/mocks/LocalERC20Mock.sol";
import { LocalSwapVMExecutor } from "../../../src/local/mocks/LocalSwapVMExecutor.sol";
import { LocalTychoRouter } from "../../../src/local/mocks/LocalTychoRouter.sol";
import { WETHMock } from "../../../src/local/mocks/WETHMock.sol";
import { Create2Utils } from "../utils/Create2Utils.sol";

library LocalDeployments {
    address internal constant DEFAULT_OWNER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    bytes32 internal constant AQUA_ROUTER_SALT = keccak256("riverswap.local.aqua-router.v1");
    bytes32 internal constant WETH_SALT = keccak256("riverswap.local.weth.v1");
    bytes32 internal constant SWAP_VM_ROUTER_SALT = keccak256("riverswap.local.aqua-swap-vm-router.v1");
    bytes32 internal constant TYCHO_ROUTER_SALT = keccak256("riverswap.local.tycho-router.v1");
    bytes32 internal constant AQUA_SWAP_VM_EXECUTOR_SALT = keccak256("riverswap.local.aqua-swap-vm-executor.v1");
    bytes32 internal constant FAIR_AUCTION_MANAGER_SALT = keccak256("riverswap.local.fair-auction-manager.v1");
    bytes32 internal constant FAIR_FEE_VALUE_ORACLE_SALT = keccak256("riverswap.local.fair-fee-value-oracle.v1");
    bytes32 internal constant FAIR_POOL_SALT = keccak256("riverswap.local.fair-pool.v1");
    bytes32 internal constant FAIR_DEFAULT_POSITION_SALT = keccak256("riverswap.local.fair-damm-position.default");
    bytes32 internal constant TOKEN_A_SALT = bytes32(0);
    bytes32 internal constant TOKEN_B_SALT = bytes32(0);
    bytes32 internal constant USDC_SALT = keccak256("riverswap.local.usdc.v1");
    bytes32 internal constant WBTC_SALT = keccak256("riverswap.local.wbtc.v1");
    bytes32 internal constant WIDE_POOL_SALT = bytes32(uint256(1));
    bytes32 internal constant STABLE_POOL_SALT = bytes32(uint256(2));
    bytes32 internal constant ROUTE_A_WETH_WIDE_SALT = keccak256("riverswap.local.route.a-weth.wide.v1");
    bytes32 internal constant ROUTE_A_WETH_STABLE_SALT = keccak256("riverswap.local.route.a-weth.stable.v1");
    bytes32 internal constant ROUTE_WETH_B_WIDE_SALT = keccak256("riverswap.local.route.weth-b.wide.v1");
    bytes32 internal constant ROUTE_WETH_B_STABLE_SALT = keccak256("riverswap.local.route.weth-b.stable.v1");
    bytes32 internal constant ROUTE_A_USDC_WIDE_SALT = keccak256("riverswap.local.route.a-usdc.wide.v1");
    bytes32 internal constant ROUTE_A_USDC_STABLE_SALT = keccak256("riverswap.local.route.a-usdc.stable.v1");
    bytes32 internal constant ROUTE_USDC_B_WIDE_SALT = keccak256("riverswap.local.route.usdc-b.wide.v1");
    bytes32 internal constant ROUTE_USDC_B_STABLE_SALT = keccak256("riverswap.local.route.usdc-b.stable.v1");
    bytes32 internal constant ROUTE_A_WBTC_WIDE_SALT = keccak256("riverswap.local.route.a-wbtc.wide.v1");
    bytes32 internal constant ROUTE_A_WBTC_STABLE_SALT = keccak256("riverswap.local.route.a-wbtc.stable.v1");
    bytes32 internal constant ROUTE_WBTC_B_WIDE_SALT = keccak256("riverswap.local.route.wbtc-b.wide.v1");
    bytes32 internal constant ROUTE_WBTC_B_STABLE_SALT = keccak256("riverswap.local.route.wbtc-b.stable.v1");

    uint256 internal constant WIDE_SQRT_PRICE_MIN_X18 = 707106781186547524;
    uint256 internal constant WIDE_SQRT_PRICE_MAX_X18 = 1414213562373095048;
    uint256 internal constant STABLE_SQRT_PRICE_MIN_X18 = 989949493661166534;
    uint256 internal constant STABLE_SQRT_PRICE_MAX_X18 = 1009950493836207795;
    uint256 internal constant POOL_BALANCE_A = 1000e18;
    uint256 internal constant POOL_BALANCE_B = 100e18;
    uint256 internal constant ROUTE_POOL_BALANCE_A = 1000e18;
    uint256 internal constant ROUTE_POOL_BALANCE_B = 1000e18;
    uint256 internal constant ROUTE_POOL_BALANCE_WETH = 1000e18;
    uint256 internal constant ROUTE_POOL_BALANCE_USDC = 1000e18;
    uint256 internal constant ROUTE_POOL_BALANCE_WBTC = 1000e18;
    uint256 internal constant ADD_LIQUIDITY_A = 100e18;
    uint256 internal constant ADD_LIQUIDITY_B = 100e18;
    uint256 internal constant SWAP_AMOUNT_IN = 10e18;
    uint256 internal constant FAIR_BID_RENT = 10e18;
    uint32 internal constant FAIR_MIN_FEE_BPS = 100_000;
    uint32 internal constant FAIR_DEFAULT_FEE_BPS = 3_000_000;
    uint32 internal constant FAIR_MAX_FEE_BPS = 10_000_000;
    uint32 internal constant FAIR_MANAGER_FEE_BPS = 6_000_000;
    uint64 internal constant FAIR_EPOCH_LENGTH_BLOCKS = 7_200;
    uint256 internal constant FAIR_TOKEN_A_PRICE_X18 = 1e18;
    uint256 internal constant FAIR_TOKEN_B_PRICE_X18 = 1e18;

    function aquaInitCode() internal pure returns (bytes memory) {
        return abi.encodePacked(type(AquaRouter).creationCode, abi.encode(DEFAULT_OWNER));
    }

    function wethInitCode() internal pure returns (bytes memory) {
        return type(WETHMock).creationCode;
    }

    function swapVmRouterInitCode() internal pure returns (bytes memory) {
        return type(LocalAquaSwapVMRouter).creationCode;
    }

    function tychoRouterInitCode() internal pure returns (bytes memory) {
        return abi.encodePacked(type(LocalTychoRouter).creationCode, abi.encode(DEFAULT_OWNER));
    }

    function aquaSwapVmExecutorInitCode() internal pure returns (bytes memory) {
        return type(LocalSwapVMExecutor).creationCode;
    }

    function tokenAInitCode() internal pure returns (bytes memory) {
        return abi.encodePacked(type(LocalERC20Mock).creationCode, abi.encode("Token A", "A", uint8(18)));
    }

    function tokenBInitCode() internal pure returns (bytes memory) {
        return abi.encodePacked(type(LocalERC20Mock).creationCode, abi.encode("Token B", "B", uint8(18)));
    }

    function usdcInitCode() internal pure returns (bytes memory) {
        return abi.encodePacked(type(LocalERC20Mock).creationCode, abi.encode("USD Coin", "USDC", uint8(6)));
    }

    function wbtcInitCode() internal pure returns (bytes memory) {
        return abi.encodePacked(type(LocalERC20Mock).creationCode, abi.encode("Wrapped Bitcoin", "WBTC", uint8(8)));
    }

    function fairAuctionManagerInitCode() internal pure returns (bytes memory) {
        return type(FairAuctionManager).creationCode;
    }

    function fairFeeValueOracleInitCode() internal pure returns (bytes memory) {
        return abi.encodePacked(type(MockFeeValueOracle).creationCode, abi.encode(DEFAULT_OWNER));
    }

    function aqua() internal pure returns (address) {
        return Create2Utils.getAddress(aquaInitCode(), AQUA_ROUTER_SALT);
    }

    function weth() internal pure returns (address) {
        return Create2Utils.getAddress(wethInitCode(), WETH_SALT);
    }

    function swapVmRouter() internal pure returns (address) {
        return Create2Utils.getAddress(swapVmRouterInitCode(), SWAP_VM_ROUTER_SALT);
    }

    function tychoRouter() internal pure returns (address) {
        return Create2Utils.getAddress(tychoRouterInitCode(), TYCHO_ROUTER_SALT);
    }

    function aquaSwapVmExecutor() internal pure returns (address) {
        return Create2Utils.getAddress(aquaSwapVmExecutorInitCode(), AQUA_SWAP_VM_EXECUTOR_SALT);
    }

    function tokenA() internal pure returns (address) {
        return Create2Utils.getAddress(tokenAInitCode(), TOKEN_A_SALT);
    }

    function tokenB() internal pure returns (address) {
        return Create2Utils.getAddress(tokenBInitCode(), TOKEN_B_SALT);
    }

    function usdc() internal pure returns (address) {
        return Create2Utils.getAddress(usdcInitCode(), USDC_SALT);
    }

    function wbtc() internal pure returns (address) {
        return Create2Utils.getAddress(wbtcInitCode(), WBTC_SALT);
    }

    function fairAuctionManager() internal pure returns (address) {
        return Create2Utils.getAddress(fairAuctionManagerInitCode(), FAIR_AUCTION_MANAGER_SALT);
    }

    function fairFeeValueOracle() internal pure returns (address) {
        return Create2Utils.getAddress(fairFeeValueOracleInitCode(), FAIR_FEE_VALUE_ORACLE_SALT);
    }
}
