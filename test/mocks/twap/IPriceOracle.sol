// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @dev Both implementations quote raw USDC units for raw WETH units (6/18 decimals).
interface IPriceOracle {
    function quote(uint256 wethAmount) external view returns (uint256 usdcAmount);
}
