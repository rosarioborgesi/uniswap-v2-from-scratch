// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {MockERC20} from "../MockERC20.sol";
import {Attacker} from "./Attacker.sol";

/// @dev Separate funding source: the manipulated pair cannot be swapped against
/// recursively during its own flash-swap callback because of its lock.
contract FlashLenderMock {
    MockERC20 public immutable usdc;

    constructor(MockERC20 _usdc) {
        usdc = _usdc;
    }

    function flashLoan(Attacker receiver, uint256 amount) external {
        uint256 beforeBalance = usdc.balanceOf(address(this));
        uint256 fee = amount * 9 / 10_000; // Fixture fee: 0.09%.
        usdc.transfer(address(receiver), amount);
        receiver.onFlashLoan(amount, fee);
        require(usdc.balanceOf(address(this)) >= beforeBalance + fee, "Flash loan not repaid");
    }
}
