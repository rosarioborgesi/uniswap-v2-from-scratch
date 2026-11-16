// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {MockERC20} from "../MockERC20.sol";
import {IPriceOracle} from "./IPriceOracle.sol";

/// @dev Minimal lending fixture: no interest or fees, and a 50% maximum LTV.
contract LendingMock {
    error ExceedsLtv();

    MockERC20 public immutable weth;
    MockERC20 public immutable usdc;
    IPriceOracle public immutable oracle;
    mapping(address => uint256) public collateral;
    mapping(address => uint256) public debt;

    /// @notice Configures the collateral token, loan token, and collateral price oracle.
    /// @param _weth The WETH token accepted as collateral.
    /// @param _usdc The USDC token available to borrow.
    /// @param _oracle The oracle that quotes raw USDC units for raw WETH units.
    constructor(MockERC20 _weth, MockERC20 _usdc, IPriceOracle _oracle) {
        weth = _weth;
        usdc = _usdc;
        oracle = _oracle;
    }

    /// @notice Deposits WETH as collateral for the caller.
    /// @dev The caller must first approve this contract to transfer the WETH.
    /// @param amount The amount of WETH to deposit, in raw token units (18 decimals).
    function deposit(uint256 amount) external {
        weth.transferFrom(msg.sender, address(this), amount);
        collateral[msg.sender] += amount;
    }

    /// @notice Returns the maximum total debt permitted for a borrower's collateral.
    /// @dev Uses 50% of the oracle-quoted collateral value, rounded down.
    /// @param borrower The account whose deposited collateral is valued.
    /// @return The total debt limit in raw USDC units (6 decimals), before subtracting existing debt.
    function borrowLimit(address borrower) public view returns (uint256) {
        uint256 amount = collateral[borrower];
        return oracle.quote(amount) / 2;
    }

    /// @notice Borrows USDC against the caller's deposited WETH collateral.
    /// @dev Reverts with ExceedsLtv if the resulting total debt exceeds the current borrow limit.
    /// @param amount The additional USDC to borrow, in raw token units (6 decimals).
    function borrow(uint256 amount) external {
        if (debt[msg.sender] + amount > borrowLimit(msg.sender)) revert ExceedsLtv();
        debt[msg.sender] += amount;
        usdc.transfer(msg.sender, amount);
    }
}
