// SPDX-License-Identifier: GPL-3.0-or-later
// Adapted from Uniswap v2-core/contracts/interfaces/IUniswapV2Callee.sol for Solidity 0.8.35.
pragma solidity 0.8.35;

interface IUniswapV2Callee {
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}
