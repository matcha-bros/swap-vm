// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/main/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { Script, console2 } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";

import { AquaSwapVMRouter } from "../../src/routers/AquaSwapVMRouter.sol";
import { ISwapVM } from "../../src/interfaces/ISwapVM.sol";
import { MakerTraitsLib } from "../../src/libs/MakerTraits.sol";
import { ControlsArgsBuilder } from "../../src/instructions/Controls.sol";
import { FeeArgsBuilder } from "../../src/instructions/Fee.sol";
import { XYCConcentrateArgsBuilder } from "../../src/instructions/XYCConcentrate.sol";
import { FairAuctionManager } from "../../src/strategies/fair-damm/FairAuctionManager.sol";
import { IFeeValueOracle } from "../../src/strategies/fair-damm/interfaces/IFeeValueOracle.sol";

interface IFairDammLocalERC20 {
    function mint(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
}

contract LocalFeeValueOracle is IFeeValueOracle {
    mapping(address token => uint256 priceX18) public prices;

    function setPrice(address token, uint256 priceX18) external {
        prices[token] = priceX18;
    }

    function valueOf(address baseToken, uint256 baseAmount, address quoteToken) external view returns (uint256 quoteAmount) {
        uint256 basePrice = prices[baseToken];
        uint256 quotePrice = prices[quoteToken];
        require(basePrice > 0, "missing base price");
        require(quotePrice > 0, "missing quote price");

        uint8 baseDecimals = IERC20Metadata(baseToken).decimals();
        uint8 quoteDecimals = IERC20Metadata(quoteToken).decimals();
        uint256 valueX18 = Math.mulDiv(baseAmount, basePrice, 10 ** baseDecimals);
        quoteAmount = Math.mulDiv(valueX18, 10 ** quoteDecimals, quotePrice);
    }
}

contract CreateFairDammOrderScript is Script {
    uint8 internal constant AQUA_ACCOUNTED_DYNAMIC_FEE_AMOUNT_IN_XD = 33;
    uint8 internal constant XYC_CONCENTRATE_GROW_LIQUIDITY_2D = 18;
    uint8 internal constant SALT = 20;
    uint256 internal constant DEFAULT_BALANCE_A = 1_000e18;
    uint256 internal constant DEFAULT_BALANCE_B = 1_000e18;
    uint256 internal constant DEFAULT_SQRT_PRICE_MIN_X18 = 707106781186547524;
    uint256 internal constant DEFAULT_SQRT_PRICE_MAX_X18 = 1414213562373095048;

    function run() external {
        address maker = _maker();
        require(maker == _deployer(), "run with maker key");

        IAqua aqua = IAqua(vm.envAddress("LOCAL_AQUA_ADDRESS"));
        AquaSwapVMRouter router = AquaSwapVMRouter(payable(vm.envAddress("LOCAL_AQUA_SWAP_VM_ROUTER_ADDRESS")));
        IFairDammLocalERC20 tokenA = IFairDammLocalERC20(vm.envAddress("LOCAL_TOKEN_A_ADDRESS"));
        IFairDammLocalERC20 tokenB = IFairDammLocalERC20(vm.envAddress("LOCAL_TOKEN_B_ADDRESS"));

        vm.startBroadcast();
        LocalFeeValueOracle feeValueOracle = new LocalFeeValueOracle();
        feeValueOracle.setPrice(address(tokenA), vm.envOr("LOCAL_TOKEN_A_PRICE_X18", uint256(1e18)));
        feeValueOracle.setPrice(address(tokenB), vm.envOr("LOCAL_TOKEN_B_PRICE_X18", uint256(1e18)));

        FairAuctionManager fairAuctionManager = new FairAuctionManager();
        bytes32 poolId = fairAuctionManager.createPool(FairAuctionManager.PoolInit({
            aqua: aqua,
            router: ISwapVM(address(router)),
            tokenA: address(tokenA),
            tokenB: address(tokenB),
            rentToken: IERC20(address(tokenA)),
            feeValueOracle: feeValueOracle,
            minFeeBps: uint32(vm.envOr("LOCAL_FAIR_MIN_FEE_BPS", uint256(100_000))),
            defaultFeeBps: uint32(vm.envOr("LOCAL_FAIR_DEFAULT_FEE_BPS", uint256(3_000_000))),
            maxFeeBps: uint32(vm.envOr("LOCAL_FAIR_MAX_FEE_BPS", uint256(10_000_000))),
            epochLengthBlocks: uint64(vm.envOr("LOCAL_FAIR_EPOCH_LENGTH_BLOCKS", uint256(7_200))),
            salt: vm.envOr("LOCAL_FAIR_POOL_SALT", bytes32("fair-damm-pool"))
        }));

        ISwapVM.Order memory order = _buildOrder(maker, _fairProgram(address(fairAuctionManager)));
        bytes32 orderHash = _ship(aqua, router, tokenA, tokenB, order);
        fairAuctionManager.registerPosition(poolId, order);
        vm.stopBroadcast();

        console2.log("Fair DAMM manager:", address(fairAuctionManager));
        console2.log("Fair DAMM fee oracle:", address(feeValueOracle));
        console2.log("Fair DAMM pool:");
        console2.logBytes32(poolId);
        console2.log("Fair DAMM order:");
        console2.logBytes32(orderHash);
    }

    function _fairProgram(address fairAuctionManager) internal view returns (bytes memory) {
        bytes memory feeArgs = FeeArgsBuilder.buildDynamicProtocolFee(fairAuctionManager);
        bytes memory concentrateArgs = XYCConcentrateArgsBuilder.build2D(
            vm.envOr("LOCAL_SQRT_PRICE_MIN_X18", DEFAULT_SQRT_PRICE_MIN_X18),
            vm.envOr("LOCAL_SQRT_PRICE_MAX_X18", DEFAULT_SQRT_PRICE_MAX_X18)
        );
        bytes memory saltArgs = ControlsArgsBuilder.buildSalt(
            abi.encodePacked(vm.envOr("LOCAL_FAIR_ORDER_SALT", bytes32("fair-damm-order")))
        );
        return bytes.concat(
            abi.encodePacked(AQUA_ACCOUNTED_DYNAMIC_FEE_AMOUNT_IN_XD, uint8(feeArgs.length), feeArgs),
            abi.encodePacked(XYC_CONCENTRATE_GROW_LIQUIDITY_2D, uint8(concentrateArgs.length), concentrateArgs),
            abi.encodePacked(SALT, uint8(saltArgs.length), saltArgs)
        );
    }

    function _buildOrder(address maker, bytes memory program) internal pure returns (ISwapVM.Order memory) {
        return MakerTraitsLib.build(MakerTraitsLib.Args({
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
        }));
    }

    function _ship(
        IAqua aqua,
        AquaSwapVMRouter router,
        IFairDammLocalERC20 tokenA,
        IFairDammLocalERC20 tokenB,
        ISwapVM.Order memory order
    )
        internal
        returns (bytes32 orderHash)
    {
        uint256 balanceA = vm.envOr("LOCAL_BALANCE_A", DEFAULT_BALANCE_A);
        uint256 balanceB = vm.envOr("LOCAL_BALANCE_B", DEFAULT_BALANCE_B);

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = balanceA;
        amounts[1] = balanceB;

        orderHash = router.hash(order);
        tokenA.mint(order.maker, balanceA);
        tokenB.mint(order.maker, balanceB);
        tokenA.approve(address(aqua), balanceA);
        tokenB.approve(address(aqua), balanceB);
        bytes32 strategyHash = aqua.ship(address(router), abi.encode(order), tokens, amounts);
        require(strategyHash == orderHash, "strategy hash mismatch");
    }

    function _deployer() internal returns (address) {
        address[] memory wallets = vm.getWallets();
        return wallets.length > 0 ? wallets[0] : msg.sender;
    }

    function _maker() internal returns (address) {
        return vm.envOr("LOCAL_MAKER_ADDRESS", _deployer());
    }
}
