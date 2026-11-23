// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {MockERC20} from "./MockERC20.sol";

contract MockWETH is MockERC20 {
    string public constant name = "Wrapped Ether";
    string public constant symbol = "WETH";

    event Deposit(address indexed account, uint256 amount);
    event Withdrawal(address indexed account, uint256 amount);

    constructor() MockERC20(address(0), 0, 18) {}

    receive() external payable {
        deposit();
    }

    fallback() external payable {
        deposit();
    }

    function deposit() public payable {
        totalSupply += msg.value;
        balanceOf[msg.sender] += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        emit Transfer(msg.sender, address(0), amount);
        emit Withdrawal(msg.sender, amount);

        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "MockWETH: ETH transfer failed");
    }
}
