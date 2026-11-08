// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

// Models USDT's no-return token operations and allowance rules without a mainnet fork.
contract MockUSDT {
    string public constant name = "Tether USD";
    string public constant symbol = "USDT";
    uint8 public constant decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(address holder, uint256 supply) {
        totalSupply = supply;
        balanceOf[holder] = supply;
        emit Transfer(address(0), holder, supply);
    }

    function approve(address spender, uint256 value) external {
        require(value == 0 || allowance[msg.sender][spender] == 0, "USDT: reset allowance first");
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
    }

    function transfer(address to, uint256 value) external {
        _transfer(msg.sender, to, value);
    }

    function transferFrom(address from, address to, uint256 value) external {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= value;
        }
        _transfer(from, to, value);
    }

    function _transfer(address from, address to, uint256 value) private {
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }
}
