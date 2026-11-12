// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {MockERC20} from "./MockERC20.sol";

/// @dev Narrow liquidation fixture inspired by Aave V1's
/// testLiquidationCapsRepaymentAndSendsUnderlyingCollateral.
/// Models one borrower's deposits, borrowing and liquidation; omits interest and aTokens.
/// Prices use USDC units per WETH and explicitly normalize 6/18 token decimals.
/// Combines pool and token custody; liquidators approve this mock directly.
/// This is not a deployment or integration test of the rebuilt Aave contracts.
contract MockAaveV1LendingPool {
    MockERC20 public immutable weth;
    MockERC20 public immutable usdc;
    address public immutable borrower;
    address public immutable feeCollector;

    uint256 public collateralBalance;
    uint256 public debt;
    uint256 public originationFee;
    uint256 public wethPrice;

    constructor(MockERC20 _weth, MockERC20 _usdc, address _borrower, address _feeCollector) {
        weth = _weth;
        usdc = _usdc;
        borrower = _borrower;
        feeCollector = _feeCollector;
    }

    function deposit(uint256 amount) external {
        require(msg.sender == borrower, "Only borrower");
        require(amount > 0, "Zero deposit");
        weth.transferFrom(msg.sender, address(this), amount);
        collateralBalance += amount;
    }

    function borrow(uint256 amount) external {
        require(msg.sender == borrower, "Only borrower");
        require(amount > 0, "Zero borrow");
        uint256 fee = amount * 25 / 10_000; // 0.25% origination fee
        uint256 collateralValue = collateralBalance * wethPrice / 1 ether;
        require(debt + originationFee + amount + fee <= collateralValue * 75 / 100, "Exceeds 75% LTV");

        debt += amount;
        originationFee += fee;
        usdc.transfer(msg.sender, amount);
    }

    // Unrestricted oracle setter for tests only. Independent of Uniswap reserves.
    function setWethPrice(uint256 price) external {
        require(price > 0, "Zero price");
        wethPrice = price;
    }

    function healthFactor() public view returns (uint256) {
        if (debt + originationFee == 0) return type(uint256).max;
        uint256 collateralValue = collateralBalance * wethPrice / 1 ether;
        return collateralValue * 80 / 100 * 1 ether / (debt + originationFee);
    }

    function liquidationCall(
        address collateral,
        address reserve,
        address user,
        uint256 purchaseAmount,
        bool receiveAToken
    ) external payable {
        require(collateral == address(weth) && reserve == address(usdc), "Wrong assets");
        require(user == borrower && !receiveAToken, "Unsupported liquidation");
        require(healthFactor() < 1 ether, "Healthy position");

        uint256 repayment = purchaseAmount < debt / 2 ? purchaseAmount : debt / 2;
        uint256 seizedCollateral = repayment * 1 ether / wethPrice * 105 / 100;
        uint256 feeCollateral = originationFee * 1 ether / wethPrice * 105 / 100;
        // The fixture models sufficient collateral, as in the referenced test.
        require(seizedCollateral + feeCollateral <= collateralBalance, "Insufficient collateral");

        debt -= repayment;
        originationFee = 0;
        collateralBalance -= seizedCollateral + feeCollateral;
        usdc.transferFrom(msg.sender, address(this), repayment);
        weth.transfer(msg.sender, seizedCollateral);
        weth.transfer(feeCollector, feeCollateral);
    }
}
