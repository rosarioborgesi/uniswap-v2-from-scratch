// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {UniswapV2Factory} from "../../src/v2-core/UniswapV2Factory.sol";
import {UniswapV2Router02} from "../../src/v2-periphery/UniswapV2Router02.sol";
import {UniswapV2Library} from "../../src/v2-periphery/libraries/UniswapV2Library.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockCEX} from "../mocks/MockCEX.sol";

contract ArbitrageTest is Test {
    MockERC20 weth;
    MockERC20 usdc;
    UniswapV2Router02 router;
    MockCEX cex;
    address liquidityProvider = makeAddr("liquidityProvider");
    address arbitrageur = makeAddr("arbitrageur");

    uint256 constant CEX_PRICE = 3_000 * 1e6; // 1 ETH costs 3,000 USDC on the CEX
    uint256 constant INITIAL_WETH_RESERVE = 100 ether;
    uint256 constant INITIAL_USDC_RESERVE = 200_000 * 1e6;
    uint256 constant INITIAL_CEX_USDC_BALANCE = 100_000 * 1e6;

    function setUp() public {
        weth = new MockERC20(address(this), 100 ether, 18);
        usdc = new MockERC20(address(this), 310_000 * 1e6, 6);
        UniswapV2Factory factory = new UniswapV2Factory(address(this));
        router = new UniswapV2Router02(address(factory), address(weth));
        cex = new MockCEX(weth, usdc, CEX_PRICE);
        usdc.transfer(address(cex), INITIAL_CEX_USDC_BALANCE);

        // The liquidity provider receives: 100 WETH and 200,000 USDC
        weth.transfer(liquidityProvider, INITIAL_WETH_RESERVE);
        usdc.transfer(liquidityProvider, INITIAL_USDC_RESERVE);
        // The arbitrageur receives 10,000 USDC
        usdc.transfer(arbitrageur, 10_000 * 1e6);

        // The liquidity provider deposits 100 WETH and 200,000 USDC
        // The initial pool price is: 200,000 USDC / 100 WETH = 2,000 USDC per WETH
        vm.startPrank(liquidityProvider);
        weth.approve(address(router), INITIAL_WETH_RESERVE);
        usdc.approve(address(router), INITIAL_USDC_RESERVE);
        router.addLiquidity(
            address(weth),
            address(usdc),
            INITIAL_WETH_RESERVE,
            INITIAL_USDC_RESERVE,
            INITIAL_WETH_RESERVE,
            INITIAL_USDC_RESERVE,
            liquidityProvider,
            block.timestamp
        );
        vm.stopPrank();
    }

    /*
        1. Price difference: 1 WETH is worth 3,000 USDC on the CEX, while the DEX pool’s initial price is 2,000 USDC/WETH.
        2. Buy on the DEX: The arbitrageur spends 10,000 USDC and receives 4.748297375815592703 WETH.
        3. Sell on the CEX: The arbitrageur sells all that WETH at 3,000 USDC/WETH and receives 14,244.892127 USDC.
        4. Profit: 14,244.892127 − 10,000 = 4,244.892127 USDC.
        5. Final state: The DEX pool price has risen to approximately 2,204.685 USDC/WETH.
    */
    function test_doArbitrage() public {
        // 1. Verifies that the initial ETH price in the Pool is 2,000 USDC
        (uint256 wethReserve, uint256 usdcReserve) =
            UniswapV2Library.getReserves(router.factory(), address(weth), address(usdc));
        uint256 initialPrice = router.quote(1 ether, wethReserve, usdcReserve);
        assertEq(initialPrice, 2_000 * 1e6);

        // 2. Calculates how much WETH the arbitrageur receives for 10,000 USDC,
        // including the pool’s 0.3% fee and price impact:
        // WETH out = (10,000 × 0.997 × 100) / (200,000 + 10,000 × 0.997)
        //          ≈ 4.748297375815592703 WETH
        uint256 depositedUsdc = 10_000 * 1e6;
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(weth);
        uint256[] memory quote = router.getAmountsOut(depositedUsdc, path);

        // 3. Execute and verify the purchase
        vm.startPrank(arbitrageur);
        // Router transfers approved USDC directly into the pair; pair sends WETH to us.
        usdc.approve(address(router), depositedUsdc);
        router.swapExactTokensForTokens(depositedUsdc, quote[1], path, arbitrageur, block.timestamp);
        vm.stopPrank();
        uint256 wethBought = weth.balanceOf(arbitrageur);
        // Independently apply the 0.3% fee and constant-product output formula.
        uint256 expectedWeth =
            depositedUsdc * 997 * INITIAL_WETH_RESERVE / (INITIAL_USDC_RESERVE * 1000 + depositedUsdc * 997);
        assertEq(wethBought, expectedWeth); // 4.748297375815592703 WETH

        // Reserve	Before	     After
        // WETH 	100	         95.2517
        // USDC	    200,000	     210,000

        (wethReserve, usdcReserve) = UniswapV2Library.getReserves(router.factory(), address(weth), address(usdc));
        uint256 finalPrice = router.quote(1 ether, wethReserve, usdcReserve);

        // 4. Verify the pool reserves and reserve-ratio price after the purchase.
        assertEq(wethReserve, INITIAL_WETH_RESERVE - expectedWeth);
        assertEq(usdcReserve, INITIAL_USDC_RESERVE + depositedUsdc);
        assertEq(finalPrice, 2_204_684_999); // 2,204.684999 USDC per WETH, rounded down.
        assertGt(finalPrice, initialPrice);
        assertLt(finalPrice, CEX_PRICE);

        // The arbitrageur spent all their USDC and still holds the purchased WETH.
        assertEq(usdc.balanceOf(arbitrageur), 0);
        assertEq(weth.balanceOf(arbitrageur), 4_748_297_375_815_592_703); //≈ 4.74 WETH

        // 5. Sell all purchased WETH to the funded CEX at 3,000 USDC per WETH.
        vm.startPrank(arbitrageur);
        weth.approve(address(cex), wethBought);
        uint256 usdcReceived = cex.sellWeth(wethBought);
        vm.stopPrank();

        // Arbitrageur finishes with zero WETH and 14,244.892127 USDC.
        uint256 expectedUsdc = expectedWeth * CEX_PRICE / 1 ether;
        assertEq(usdcReceived, expectedUsdc);
        assertEq(weth.balanceOf(arbitrageur), 0);
        assertEq(usdc.balanceOf(arbitrageur), expectedUsdc);
        assertEq(expectedUsdc, 14_244_892_127); // 14,244.892127 USDC, rounded down.

        // Profit after the pool fee, excluding gas and CEX fees.
        // Profit is 4,244.892127 USDC.
        uint256 profit = usdc.balanceOf(arbitrageur) - depositedUsdc;
        assertEq(profit, 4_244_892_127); // 4,244.892127 USDC.

        // The CEX received the WETH and paid from its own USDC balance.
        assertEq(weth.balanceOf(address(cex)), wethBought);
        assertEq(usdc.balanceOf(address(cex)), INITIAL_CEX_USDC_BALANCE - expectedUsdc);
    }
}
