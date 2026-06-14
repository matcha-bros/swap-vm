// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";
import { ISwapVM } from "../../interfaces/ISwapVM.sol";
import { IAccountedFeeProvider } from "../../instructions/interfaces/IAccountedFeeProvider.sol";
import { IAccountedFeeRecorder } from "../../instructions/interfaces/IAccountedFeeRecorder.sol";
import { MakerTraits } from "../../libs/MakerTraits.sol";
import { MakerTraitsLib } from "../../libs/MakerTraits.sol";

import { IFeeValueOracle } from "./interfaces/IFeeValueOracle.sol";

contract FairAuctionManager is IAccountedFeeProvider, IAccountedFeeRecorder {
    using SafeERC20 for IERC20;
    using MakerTraitsLib for *;

    uint256 public constant SWAPVM_FEE_BPS = 1e9;
    uint8 internal constant AQUA_ACCOUNTED_DYNAMIC_FEE_AMOUNT_IN_XD = 33;
    uint8 internal constant XYC_CONCENTRATE_GROW_LIQUIDITY_2D = 18;
    uint8 internal constant SALT = 20;

    struct PoolConfig {
        IAqua aqua;
        ISwapVM router;
        address token0;
        address token1;
        IERC20 rentToken;
        IFeeValueOracle feeValueOracle;
        uint32 minFeeBps;
        uint32 defaultFeeBps;
        uint32 maxFeeBps;
        uint64 epochLengthBlocks;
        uint64 createdAtBlock;
        uint64 currentEpoch;
        bool exists;
    }

    struct PoolInit {
        IAqua aqua;
        ISwapVM router;
        address tokenA;
        address tokenB;
        IERC20 rentToken;
        IFeeValueOracle feeValueOracle;
        uint32 minFeeBps;
        uint32 defaultFeeBps;
        uint32 maxFeeBps;
        uint64 epochLengthBlocks;
        bytes32 salt;
    }

    struct Position {
        bytes32 poolId;
        address maker;
        bytes32 orderHash;
        uint256 sqrtPriceMinX18;
        uint256 sqrtPriceMaxX18;
        bool active;
    }

    struct Bid {
        address bidder;
        uint256 amount;
    }

    struct EpochState {
        address manager;
        uint256 rentAmount;
        uint32 feeBps;
    }

    mapping(bytes32 poolId => PoolConfig) private _pools;
    mapping(bytes32 orderHash => bytes32 poolId) public poolByOrderHash;
    mapping(bytes32 orderHash => uint256 positionId) public positionByOrderHash;
    mapping(bytes32 poolId => uint256[] positionIds) private _poolPositionIds;
    mapping(bytes32 poolId => mapping(bytes32 orderHash => bool)) public isRegisteredOrder;
    mapping(uint256 positionId => Position) public positions;
    mapping(bytes32 poolId => mapping(uint64 epoch => EpochState)) public epochs;
    mapping(bytes32 poolId => mapping(uint64 epoch => Bid)) public bids;
    mapping(address token => mapping(address account => uint256 amount)) public bidCredits;
    mapping(bytes32 poolId => mapping(uint64 epoch => mapping(address token => uint256 amount))) public epochRawFeeByToken;
    mapping(uint256 positionId => mapping(uint64 epoch => mapping(address token => uint256 amount))) public positionRawFeeByToken;
    mapping(bytes32 poolId => mapping(uint64 epoch => uint256 value)) public epochTotalFeeValue;
    mapping(uint256 positionId => mapping(uint64 epoch => uint256 value)) public positionFeeValue;
    mapping(uint256 positionId => mapping(uint64 epoch => bool claimed)) public rentClaimed;

    uint256 public nextPositionId = 1;

    event PoolCreated(bytes32 indexed poolId, address indexed router, address indexed rentToken, address feeValueOracle);
    event PositionRegistered(
        bytes32 indexed poolId,
        uint256 indexed positionId,
        address indexed maker,
        bytes32 orderHash,
        uint256 sqrtPriceMinX18,
        uint256 sqrtPriceMaxX18
    );
    event BidPlaced(bytes32 indexed poolId, uint64 indexed epoch, address indexed bidder, uint256 amount);
    event BidCreditWithdrawn(address indexed token, address indexed account, uint256 amount);
    event EpochRolled(bytes32 indexed poolId, uint64 indexed epoch, address indexed manager, uint256 rentAmount);
    event ManagerFeeSet(bytes32 indexed poolId, uint64 indexed epoch, address indexed manager, uint32 feeBps);
    event AccountedFeeRecorded(
        bytes32 indexed poolId,
        uint64 indexed epoch,
        uint256 indexed positionId,
        address feeToken,
        uint256 feeAmount,
        uint256 feeValue
    );
    event RentClaimed(bytes32 indexed poolId, uint64 indexed epoch, uint256 indexed positionId, address maker, uint256 amount);
    event RentCompounded(bytes32 indexed poolId, uint64 indexed epoch, uint256 indexed positionId, address maker, uint256 amount);

    error PoolNotFound(bytes32 poolId);
    error PoolAlreadyExists(bytes32 poolId);
    error InvalidPoolConfig();
    error InvalidOrder();
    error PositionAlreadyRegistered(bytes32 orderHash);
    error PositionNotFound(uint256 positionId);
    error PositionPoolMismatch(uint256 positionId, bytes32 poolId);
    error StrategyNotActive(bytes32 orderHash);
    error BidTooLow(uint256 amount, uint256 currentAmount);
    error EpochNotEnded(bytes32 poolId, uint64 epoch);
    error NotManager(address caller);
    error FeeOutsideRange(uint32 feeBps, uint32 minFeeBps, uint32 maxFeeBps);
    error RentAlreadyClaimed(uint256 positionId, uint64 epoch);
    error RentTokenNotInStrategy(address rentToken);
    error NothingToWithdraw();
    error OnlyRouter(address caller);
    error InvalidAccountingKey(bytes32 expected, bytes32 actual);
    error InvalidFeeToken(address feeToken);

    function createPool(PoolInit calldata init) external returns (bytes32 poolId) {
        require(
            address(init.aqua) != address(0) &&
                address(init.router) != address(0) &&
                address(init.rentToken) != address(0) &&
                address(init.feeValueOracle) != address(0) &&
                init.tokenA != address(0) &&
                init.tokenB != address(0) &&
                init.tokenA != init.tokenB &&
                init.minFeeBps <= init.defaultFeeBps &&
                init.defaultFeeBps <= init.maxFeeBps &&
                init.maxFeeBps <= SWAPVM_FEE_BPS &&
                init.epochLengthBlocks > 0,
            InvalidPoolConfig()
        );

        (address token0, address token1) = init.tokenA < init.tokenB ? (init.tokenA, init.tokenB) : (init.tokenB, init.tokenA);
        poolId = keccak256(
            abi.encode(
                address(this),
                address(init.aqua),
                address(init.router),
                token0,
                token1,
                address(init.rentToken),
                address(init.feeValueOracle),
                init.minFeeBps,
                init.defaultFeeBps,
                init.maxFeeBps,
                init.epochLengthBlocks,
                init.salt
            )
        );
        require(!_pools[poolId].exists, PoolAlreadyExists(poolId));

        _pools[poolId] = PoolConfig({
            aqua: init.aqua,
            router: init.router,
            token0: token0,
            token1: token1,
            rentToken: init.rentToken,
            feeValueOracle: init.feeValueOracle,
            minFeeBps: init.minFeeBps,
            defaultFeeBps: init.defaultFeeBps,
            maxFeeBps: init.maxFeeBps,
            epochLengthBlocks: init.epochLengthBlocks,
            createdAtBlock: uint64(block.number),
            currentEpoch: 0,
            exists: true
        });

        emit PoolCreated(poolId, address(init.router), address(init.rentToken), address(init.feeValueOracle));
    }

    function getPool(bytes32 poolId) external view returns (PoolConfig memory pool) {
        pool = _pool(poolId);
    }

    function poolPositionCount(bytes32 poolId) external view returns (uint256) {
        _pool(poolId);
        return _poolPositionIds[poolId].length;
    }

    function poolPositionId(bytes32 poolId, uint256 index) external view returns (uint256) {
        _pool(poolId);
        return _poolPositionIds[poolId][index];
    }

    function currentEpoch(bytes32 poolId) public view returns (uint64) {
        return _pool(poolId).currentEpoch;
    }

    function activeManager(bytes32 poolId) public view returns (address) {
        PoolConfig storage pool = _pool(poolId);
        return epochs[poolId][pool.currentEpoch].manager;
    }

    function activeFee(bytes32 poolId) public view returns (uint32) {
        PoolConfig storage pool = _pool(poolId);
        EpochState storage epoch = epochs[poolId][pool.currentEpoch];
        if (epoch.manager == address(0) || epoch.feeBps == 0) return pool.defaultFeeBps;
        return epoch.feeBps;
    }

    function registerPosition(bytes32 poolId, ISwapVM.Order calldata order) external returns (uint256 positionId) {
        PoolConfig storage pool = _pool(poolId);
        require(order.maker == msg.sender, InvalidOrder());
        require(order.traits.useAquaInsteadOfSignature(), InvalidOrder());
        require(MakerTraits.unwrap(order.traits) == MakerTraits.unwrap(_expectedTraits(order.maker)), InvalidOrder());
        (bool validProgram, uint256 sqrtPriceMinX18, uint256 sqrtPriceMaxX18) = _parseExpectedProgram(order.data);
        require(validProgram, InvalidOrder());

        bytes32 orderHash = pool.router.hash(order);
        require(!isRegisteredOrder[poolId][orderHash], PositionAlreadyRegistered(orderHash));
        _requireActiveStrategy(pool, order.maker, orderHash);

        positionId = nextPositionId++;
        positions[positionId] = Position({
            poolId: poolId,
            maker: order.maker,
            orderHash: orderHash,
            sqrtPriceMinX18: sqrtPriceMinX18,
            sqrtPriceMaxX18: sqrtPriceMaxX18,
            active: true
        });
        _poolPositionIds[poolId].push(positionId);
        isRegisteredOrder[poolId][orderHash] = true;
        poolByOrderHash[orderHash] = poolId;
        positionByOrderHash[orderHash] = positionId;

        emit PositionRegistered(poolId, positionId, order.maker, orderHash, sqrtPriceMinX18, sqrtPriceMaxX18);
    }

    function placeBid(bytes32 poolId, uint256 rentAmount) external {
        PoolConfig storage pool = _pool(poolId);
        uint64 epoch = pool.currentEpoch + 1;
        Bid storage currentBid = bids[poolId][epoch];
        require(rentAmount > currentBid.amount, BidTooLow(rentAmount, currentBid.amount));

        pool.rentToken.safeTransferFrom(msg.sender, address(this), rentAmount);
        if (currentBid.bidder != address(0)) {
            bidCredits[address(pool.rentToken)][currentBid.bidder] += currentBid.amount;
        }

        currentBid.bidder = msg.sender;
        currentBid.amount = rentAmount;
        emit BidPlaced(poolId, epoch, msg.sender, rentAmount);
    }

    function withdrawBidCredit(address token) external {
        uint256 amount = bidCredits[token][msg.sender];
        require(amount > 0, NothingToWithdraw());
        bidCredits[token][msg.sender] = 0;
        IERC20(token).safeTransfer(msg.sender, amount);
        emit BidCreditWithdrawn(token, msg.sender, amount);
    }

    function rollEpoch(bytes32 poolId) external {
        PoolConfig storage pool = _pool(poolId);
        uint64 nextEpoch = pool.currentEpoch + 1;
        require(_epochEnded(pool, pool.currentEpoch), EpochNotEnded(poolId, pool.currentEpoch));

        Bid storage winningBid = bids[poolId][nextEpoch];
        EpochState storage nextState = epochs[poolId][nextEpoch];
        nextState.manager = winningBid.bidder;
        nextState.rentAmount = winningBid.amount;
        pool.currentEpoch = nextEpoch;

        emit EpochRolled(poolId, nextEpoch, winningBid.bidder, winningBid.amount);
    }

    function setManagerFee(bytes32 poolId, uint32 feeBps) external {
        PoolConfig storage pool = _pool(poolId);
        EpochState storage state = epochs[poolId][pool.currentEpoch];
        require(msg.sender == state.manager, NotManager(msg.sender));
        require(feeBps >= pool.minFeeBps && feeBps <= pool.maxFeeBps, FeeOutsideRange(feeBps, pool.minFeeBps, pool.maxFeeBps));
        state.feeBps = feeBps;
        emit ManagerFeeSet(poolId, pool.currentEpoch, msg.sender, feeBps);
    }

    function getAccountedFeeState(
        bytes32 orderHash,
        address,
        address taker,
        address,
        address,
        bool
    )
        external
        view
        returns (uint32 feeBps, address recipient, address recordTarget, bytes32 accountingKey)
    {
        bytes32 poolId = poolByOrderHash[orderHash];
        if (poolId == bytes32(0)) return (0, address(0), address(0), bytes32(0));

        PoolConfig storage pool = _pool(poolId);
        uint64 epochId = pool.currentEpoch;
        EpochState storage epoch = epochs[poolId][epochId];
        accountingKey = _accountingKey(poolId, epochId);
        recordTarget = address(this);

        if (epoch.manager == address(0)) {
            return (pool.defaultFeeBps, address(0), recordTarget, accountingKey);
        }
        if (taker == epoch.manager) {
            return (0, epoch.manager, recordTarget, accountingKey);
        }
        uint32 active = epoch.feeBps == 0 ? pool.defaultFeeBps : epoch.feeBps;
        return (active, epoch.manager, recordTarget, accountingKey);
    }

    function recordAccountedFee(
        bytes32 accountingKey,
        bytes32 orderHash,
        address maker,
        address,
        address tokenIn,
        address tokenOut,
        address feeToken,
        uint256 feeAmount,
        uint256,
        uint256
    )
        external
    {
        bytes32 poolId = poolByOrderHash[orderHash];
        PoolConfig storage pool = _pool(poolId);
        require(msg.sender == address(pool.router), OnlyRouter(msg.sender));

        uint64 epochId = pool.currentEpoch;
        bytes32 expectedKey = _accountingKey(poolId, epochId);
        require(accountingKey == expectedKey, InvalidAccountingKey(expectedKey, accountingKey));
        require(feeToken == tokenIn, InvalidFeeToken(feeToken));
        require((tokenIn == pool.token0 && tokenOut == pool.token1) || (tokenIn == pool.token1 && tokenOut == pool.token0), InvalidOrder());
        require(feeToken == pool.token0 || feeToken == pool.token1, InvalidFeeToken(feeToken));

        uint256 positionId = positionByOrderHash[orderHash];
        Position storage position = _position(positionId);
        require(position.maker == maker, InvalidOrder());

        uint256 feeValue = 0;
        if (feeAmount > 0) {
            feeValue = pool.feeValueOracle.valueOf(feeToken, feeAmount, address(pool.rentToken));
        }

        positionRawFeeByToken[positionId][epochId][feeToken] += feeAmount;
        epochRawFeeByToken[poolId][epochId][feeToken] += feeAmount;
        positionFeeValue[positionId][epochId] += feeValue;
        epochTotalFeeValue[poolId][epochId] += feeValue;

        emit AccountedFeeRecorded(poolId, epochId, positionId, feeToken, feeAmount, feeValue);
    }

    function claimableRent(bytes32 poolId, uint256 positionId, uint64 epoch) public view returns (uint256) {
        Position storage position = _position(positionId);
        require(position.poolId == poolId, PositionPoolMismatch(positionId, poolId));
        if (rentClaimed[positionId][epoch]) return 0;
        PoolConfig storage pool = _pool(poolId);
        if (!_epochEnded(pool, epoch)) return 0;
        uint256 totalValue = epochTotalFeeValue[poolId][epoch];
        if (totalValue == 0) return 0;
        return Math.mulDiv(epochs[poolId][epoch].rentAmount, positionFeeValue[positionId][epoch], totalValue);
    }

    function claimRent(bytes32 poolId, uint256 positionId, uint64 epoch) public returns (uint256 amount) {
        amount = _claim(poolId, positionId, epoch);
        IERC20(address(_pool(poolId).rentToken)).safeTransfer(positions[positionId].maker, amount);
        emit RentClaimed(poolId, epoch, positionId, positions[positionId].maker, amount);
    }

    function claimRentToAqua(bytes32 poolId, uint256 positionId, uint64 epoch) external returns (uint256 amount) {
        PoolConfig storage pool = _pool(poolId);
        address rentToken = address(pool.rentToken);
        require(rentToken == pool.token0 || rentToken == pool.token1, RentTokenNotInStrategy(rentToken));

        amount = _claim(poolId, positionId, epoch);
        Position storage position = positions[positionId];
        pool.rentToken.forceApprove(address(pool.aqua), amount);
        pool.aqua.push(position.maker, address(pool.router), position.orderHash, rentToken, amount);
        emit RentCompounded(poolId, epoch, positionId, position.maker, amount);
    }

    function _claim(bytes32 poolId, uint256 positionId, uint64 epoch) internal returns (uint256 amount) {
        Position storage position = _position(positionId);
        require(position.poolId == poolId, PositionPoolMismatch(positionId, poolId));
        require(!rentClaimed[positionId][epoch], RentAlreadyClaimed(positionId, epoch));
        require(_epochEnded(_pool(poolId), epoch), EpochNotEnded(poolId, epoch));

        amount = claimableRent(poolId, positionId, epoch);
        rentClaimed[positionId][epoch] = true;
    }

    function _pool(bytes32 poolId) internal view returns (PoolConfig storage pool) {
        pool = _pools[poolId];
        require(pool.exists, PoolNotFound(poolId));
    }

    function _position(uint256 positionId) internal view returns (Position storage position) {
        position = positions[positionId];
        require(position.maker != address(0), PositionNotFound(positionId));
    }

    function _epochEnded(PoolConfig storage pool, uint64 epoch) internal view returns (bool) {
        return block.number >= uint256(pool.createdAtBlock) + uint256(epoch + 1) * uint256(pool.epochLengthBlocks);
    }

    function _requireActiveStrategy(PoolConfig storage pool, address maker, bytes32 orderHash) internal view {
        (, uint8 tokensCount0) = pool.aqua.rawBalances(maker, address(pool.router), orderHash, pool.token0);
        (, uint8 tokensCount1) = pool.aqua.rawBalances(maker, address(pool.router), orderHash, pool.token1);
        require(tokensCount0 > 0 && tokensCount0 != type(uint8).max && tokensCount1 > 0 && tokensCount1 != type(uint8).max, StrategyNotActive(orderHash));
    }

    function _expectedTraits(address maker) internal pure returns (MakerTraits) {
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
            postTransferOutTarget: address(0),
            preTransferOutTarget: address(0),
            preTransferOutData: "",
            postTransferInData: "",
            postTransferOutData: "",
            program: ""
        })).traits;
    }

    function _parseExpectedProgram(bytes calldata program)
        internal
        view
        returns (bool valid, uint256 sqrtPriceMinX18, uint256 sqrtPriceMaxX18)
    {
        if (
            program.length != 122 ||
            uint8(program[0]) != AQUA_ACCOUNTED_DYNAMIC_FEE_AMOUNT_IN_XD ||
            uint8(program[1]) != 20 ||
            address(bytes20(program[2:22])) != address(this) ||
            uint8(program[22]) != XYC_CONCENTRATE_GROW_LIQUIDITY_2D ||
            uint8(program[23]) != 64 ||
            uint8(program[88]) != SALT ||
            uint8(program[89]) != 32
        ) return (false, 0, 0);

        sqrtPriceMinX18 = uint256(bytes32(program[24:56]));
        sqrtPriceMaxX18 = uint256(bytes32(program[56:88]));
        valid = 0 < sqrtPriceMinX18 && sqrtPriceMinX18 < sqrtPriceMaxX18;
    }

    function _accountingKey(bytes32 poolId, uint64 epoch) internal pure returns (bytes32) {
        return keccak256(abi.encode(poolId, epoch));
    }
}
