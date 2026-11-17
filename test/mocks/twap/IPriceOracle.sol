// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @dev Both implementations quote raw USDC units for raw WETH units (6/18 decimals).
interface IPriceOracle {
    /// @notice Values a WETH amount in USDC using the oracle's price.
    /// @param wethAmount WETH amount in raw token units (18 decimals).
    /// @return usdcAmount USDC value in raw token units (6 decimals).
    function quote(uint256 wethAmount) external view returns (uint256 usdcAmount);
}
