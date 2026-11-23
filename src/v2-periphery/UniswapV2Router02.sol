// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IUniswapV2Factory} from "../v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "../v2-core/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {UniswapV2Library} from "./libraries/UniswapV2Library.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";

/// @notice Partial Router02 port: token liquidity, exact-input swaps, and price/output quotes only.
contract UniswapV2Router02 is IUniswapV2Router02 {
    /////////////////////////////////////////
    //            State Variables          //
    /////////////////////////////////////////
    address public immutable override factory;
    address public immutable override WETH;

    ///////////////////////////////////
    //            Modifiers          //
    ///////////////////////////////////
    // Check the deadline
    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "UniswapV2Router: EXPIRED");
        _;
    }

    ///////////////////////////////////
    //            Functions          //
    ///////////////////////////////////
    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }

    /// @dev Only accept ETH via fallback from the WETH contract.
    receive() external payable {
        require(msg.sender == WETH, "UniswapV2Router: ONLY_WETH");
    }

    ////////////////////////////////////////////
    //            External Functions          //
    //////////////////////////////////////////// 
    /// @notice Adds liquidity to a token pair and mints LP tokens to the recipient.
    /// @dev Creates the pair if needed and uses both desired amounts when both reserves are zero.
    /// Otherwise, uses the reserve ratio to quote one token amount and checks it against its minimum.
    /// The caller must approve the router to spend the amounts transferred from their balance.
    /// @param tokenA Address of the first token.
    /// @param tokenB Address of the second token.
    /// @param amountADesired Maximum amount of tokenA to deposit.
    /// @param amountBDesired Maximum amount of tokenB to deposit.
    /// @param amountAMin Minimum amount of tokenA if its amount is quoted from the reserves.
    /// @param amountBMin Minimum amount of tokenB if its amount is quoted from the reserves.
    /// @param to Recipient of the LP tokens.
    /// @param deadline Latest block timestamp at which the transaction can succeed.
    /// @return amountA Amount of tokenA transferred from the caller.
    /// @return amountB Amount of tokenB transferred from the caller.
    /// @return liquidity Amount of LP tokens minted to the recipient.
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        // Calculate the deposit amounts and create the pair if it doesn't exist
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        // Compute the pair address
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        // Transfer amountA of tokenA from msg.sender to pair
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        // Transfer amountB of tokenB from msg.sender to pair (The router doesn't hold any tokens)
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        // Mint LP tokens to to
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    /// @notice Adds liquidity to a token/WETH pair using ETH and mints LP tokens to the recipient.
    /// @dev Creates the pair if needed. When both reserves are zero, uses `amountTokenDesired` and `msg.value`.
    /// Otherwise, quotes one amount from the reserves and checks it against its minimum.
    /// The caller must approve the router to spend the token amount used. The router wraps the ETH used
    /// into WETH and refunds any excess ETH to `msg.sender`.
    /// @param token Address of the ERC-20 token paired with WETH.
    /// @param amountTokenDesired Maximum amount of the token to deposit.
    /// @param amountTokenMin Minimum token amount if it is quoted from the reserves.
    /// @param amountETHMin Minimum ETH amount in wei if it is quoted from the reserves.
    /// @param to Recipient of the LP tokens.
    /// @param deadline Latest block timestamp at which the transaction can succeed.
    /// @return amountToken Amount of the token transferred from the caller.
    /// @return amountETH Amount of ETH in wei wrapped and deposited as WETH.
    /// @return liquidity Amount of LP tokens minted to the recipient.
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        // Calculate the deposit amounts and create the pair if it doesn't exist
        (amountToken, amountETH) = _addLiquidity(token, WETH, amountTokenDesired, msg.value, amountTokenMin, amountETHMin);
        // Compute the pair address
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        // transfers amountToken of the ERC-20 token from caller to the pair
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        // Wrap amountETH into WETH
        IWETH(WETH).deposit{value: amountETH}();
        // Transfer amountETH of WETH to the pair
        // The router doesn't hold any ETH
        TransferHelper.safeTransfer(WETH, pair, amountETH);
        // The pair then mints LP tokens to to
        liquidity = IUniswapV2Pair(pair).mint(to);
        // refund excess ETH
        if(msg.value > amountETH) {
            TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
        }
    }

    /// @notice Burns approved LP tokens and withdraws both assets, enforcing minimum amounts and a deadline.
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity);
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(to);
        (address token0,) = UniswapV2Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "UniswapV2Router: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "UniswapV2Router: INSUFFICIENT_B_AMOUNT");
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    ////////////////////////////////////////////
    //            Internal Functions          //
    ////////////////////////////////////////////
    /// @notice Determines the token amounts to deposit and creates the pair if it does not exist.
    /// @dev Returns both desired amounts when both reserves are zero. Otherwise, uses one desired amount
    /// and quotes the other from the reserves, reverting if the quoted amount is below its minimum.
    /// @param tokenA Address of the first token.
    /// @param tokenB Address of the second token.
    /// @param amountADesired Maximum amount of tokenA to deposit.
    /// @param amountBDesired Maximum amount of tokenB to deposit.
    /// @param amountAMin Minimum amount of tokenA if its amount is quoted from the reserves.
    /// @param amountBMin Minimum amount of tokenB if its amount is quoted from the reserves.
    /// @return amountA Amount of tokenA to deposit.
    /// @return amountB Amount of tokenB to deposit.
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            // If both reserves are zero, use both desired amounts.
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            // Existing pair, the pool has liquidity
            // Try using all of token A.
            uint256 amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "UniswapV2Router: INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                // If that would require too much B, use all of token B
                uint256 amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, "UniswapV2Router: INSUFFICIENT_A_AMOUNT");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output))
                .swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    /////////////////////////////////////////////////////////////////
    //            External & Public View & Pure Functions          //
    /////////////////////////////////////////////////////////////////
    /// @notice Returns the reserve-ratio equivalent of amountA, excluding swap fees and price impact.
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        public
        pure
        virtual
        override
        returns (uint256 amountB)
    {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        virtual
        override
        returns (uint256 amountOut)
    {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }
}
