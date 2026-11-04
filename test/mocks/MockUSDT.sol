// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

// Models USDT's no-return transfer behavior without requiring a mainnet fork.
contract MockUSDT {
    mapping(address => uint256) public balanceOf;

    constructor(address holder, uint256 supply) {
        balanceOf[holder] = supply;
    }

    function transfer(address to, uint256 value) external {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
    }
}
