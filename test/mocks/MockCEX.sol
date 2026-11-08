// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {MockERC20} from "./MockERC20.sol";

/// @notice Simulates a CEX buying 18-decimal WETH for 6-decimal USDC at a fixed price.
/// @dev Immediate settlement, with no trading fees, order book, or price changes.
contract MockCEX {
    MockERC20 public immutable weth;
    MockERC20 public immutable usdc;
    uint256 public immutable price;

    constructor(MockERC20 _weth, MockERC20 _usdc, uint256 _price) {
        weth = _weth;
        usdc = _usdc;
        price = _price;
    }

    function sellWeth(uint256 wethAmount) external returns (uint256 usdcAmount) {
        usdcAmount = wethAmount * price / 1 ether;
        require(weth.transferFrom(msg.sender, address(this), wethAmount), "MockCEX: WETH_TRANSFER_FAILED");
        require(usdc.transfer(msg.sender, usdcAmount), "MockCEX: USDC_TRANSFER_FAILED");
    }
}
