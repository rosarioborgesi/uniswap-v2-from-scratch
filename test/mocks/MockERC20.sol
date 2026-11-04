// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

contract MockERC20 {
    mapping(address => uint256) public balanceOf;

    constructor(address holder, uint256 supply) {
        balanceOf[holder] = supply;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        return true;
    }
}
