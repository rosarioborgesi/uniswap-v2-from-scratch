// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.35;

import {MockERC20} from "./MockERC20.sol";

/// @notice ERC20 that collects 1% of each transfer in the token contract, rounding the fee down.
contract MockFeeOnTransferERC20 is MockERC20 {
    constructor(address holder, uint256 supply, uint8 decimals_) MockERC20(holder, supply, decimals_) {}

    function _transfer(address from, address to, uint256 value) internal override {
        uint256 fee = value / 100;
        super._transfer(from, address(this), fee); // Charges a 1% fee on the transfer
        super._transfer(from, to, value - fee);
    }
}
