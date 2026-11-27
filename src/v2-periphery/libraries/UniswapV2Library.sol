// SPDX-License-Identifier: GPL-3.0-or-later
// Adapted from Uniswap v2-periphery/contracts/libraries/UniswapV2Library.sol for Solidity 0.8.35.
pragma solidity 0.8.35;

import {IUniswapV2Pair} from "../../v2-core/interfaces/IUniswapV2Pair.sol";
import {UniswapV2Pair} from "../../v2-core/UniswapV2Pair.sol";

/// @notice Provides helpers for finding Uniswap V2 pairs and quoting liquidity deposits and swaps.
/// @dev Derives pair addresses from the factory and sorted token addresses, then reads reserves in
/// the requested token order. Uses reserve ratios to quote deposits and accounts for the 0.3% swap fee
/// when calculating amounts for exact-input or exact-output swaps across one or more pairs.
library UniswapV2Library {
    /// @notice Returns sorted token addresses, used to handle return values from pairs sorted in this order.
    /// @dev Reverts if tokenA == tokenB or either address is zero.
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "UniswapV2Library: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
    }

    /// @notice Calculates the CREATE2 address for a pair without making any external calls.
    /// @dev Uses the factory address, sorted token addresses as salt, and the init code hash.
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encodePacked(token0, token1)),
                            keccak256(type(UniswapV2Pair).creationCode) // Solidity 0.8.35 pair init code hash
                        )
                    )
                )
            )
        );
    }

    /// @notice Fetches and sorts the reserves for a pair.
    /// @dev Calls the pair contract's getReserves() and returns reserves matching the input token order.
    function getReserves(address factory, address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /// @notice Given an amount of tokenA and pair reserves, returns the equivalent amount of tokenB.
    /// @dev Used for calculating optimal liquidity amounts. Pure proportional math, no fee.
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        require(amountA > 0, "UniswapV2Library: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        amountB = amountA * reserveB / reserveA;
    }

    /// @notice Given an input amount and pair reserves, returns the maximum output amount (with 0.3% fee).
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");

        // x * y = k
        // (x + dx * 0.997) * (y - dy) >= x * y
        // dy = (dx * 0.997 * y) / (x + dx * 0.997)
        // dy = (dx * 997 * y) / (x * 1000 + dx * 997)
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /// @notice Given an output amount and pair reserves, returns the required input amount (with 0.3% fee).
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");

        // x * y = k
        // (x + dx * 0.997) * (y - dy) >= x * y
        // dx = (x * dy * 1000) / ((y - dy) * 997) + 1
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = numerator / denominator + 1;
    }

    // This answers “If I start with this much of the first token,
    // how much will I get at each hop?”
    // It quotes an exact-input swap using each pair’s current reserves, the 0.3% swap fee, and rounding down.
    // Each hop’s output becomes the next hop’s input.
    /// @notice Performs chained getAmountOut calculations on any number of pairs.
    /// @dev path is an array of token addresses representing the swap route.
    function getAmountsOut(address factory, uint256 amountIn, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "UniswapV2Library: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // This answers “If I want exactly this much of the final token,
    // how much do I need to start with?”
    // It takes the desired output and a token path, then works backward through the pairs.
    // Each step uses getAmountIn to account for the pair’s reserves and the 0.3% swap fee.
    /// @notice Performs chained getAmountIn calculations on any number of pairs.
    /// @dev Calculates backwards from the desired output to the required input.
    function getAmountsIn(address factory, uint256 amountOut, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "UniswapV2Library: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}
