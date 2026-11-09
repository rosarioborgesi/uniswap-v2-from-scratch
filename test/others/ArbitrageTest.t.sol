// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {UniswapV2Factory} from "../../src/v2-core/UniswapV2Factory.sol";
import {UniswapV2Router02} from "../../src/v2-periphery/UniswapV2Router02.sol";
import {UniswapV2Library} from "../../src/v2-periphery/libraries/UniswapV2Library.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockCEX} from "../mocks/MockCEX.sol";
import {Math} from "../../src/v2-core/libraries/Math.sol";

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

    uint256 constant INITIAL_ARBITRAGEUR_USDC_BALANCE = 50_000 * 1e6;

    function setUp() public {
        weth = new MockERC20(address(this), 100 ether, 18);
        usdc = new MockERC20(address(this), 350_000 * 1e6, 6);
        UniswapV2Factory factory = new UniswapV2Factory(address(this));
        router = new UniswapV2Router02(address(factory), address(weth));
        cex = new MockCEX(weth, usdc, CEX_PRICE);
        usdc.transfer(address(cex), INITIAL_CEX_USDC_BALANCE);

        // The liquidity provider receives: 100 WETH and 200,000 USDC
        weth.transfer(liquidityProvider, INITIAL_WETH_RESERVE);
        usdc.transfer(liquidityProvider, INITIAL_USDC_RESERVE);
        // Give the arbitrageur enough capital to bring the DEX price to the CEX price.
        usdc.transfer(arbitrageur, INITIAL_ARBITRAGEUR_USDC_BALANCE);

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

    // This test demonstrates arbitrage between a CEX price of 3,000 USDC per WETH
    // and an initial DEX reserve-ratio price of 2,000 USDC per WETH.
    // The arbitrageur buys WETH on the DEX, raising its reserve-ratio price to 3,000,
    // then sells the purchased WETH on the CEX for a profit of 9,966.983303 USDC,
    // after the DEX swap fee and excluding gas and CEX fees.
    function test_doArbitrage() public {
        // 1. Verify that the initial pool reserve-ratio price is 2,000 USDC per WETH.
        (uint256 wethReserve, uint256 usdcReserve) =
            UniswapV2Library.getReserves(router.factory(), address(weth), address(usdc));
        uint256 initialPrice = router.quote(1 ether, wethReserve, usdcReserve);
        assertEq(initialPrice, 2_000 * 1e6);

        // 2. Calculate how much USDC the arbitrageur must deposit
        // to bring the ratio USDC / WETH = 3,000 USDC
        uint256 discriminant =
            9 * usdcReserve * usdcReserve + 4 * 997 * 1000 * CEX_PRICE * wethReserve * usdcReserve / 1 ether;
        // Round up to the next micro-USDC so the reserve ratio reaches the target.
        uint256 depositedUsdc = (Math.sqrt(discriminant) - 1997 * usdcReserve) / 1994 + 1; // 45,016.508349 USDC

        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(weth);
        uint256[] memory quote = router.getAmountsOut(depositedUsdc, path);

        // 3. Execute and verify the purchase
        // The arbitrageur deposits 45,016.508349 USDC and receives 18.327830550951836598 WETH
        vm.startPrank(arbitrageur);
        // Router transfers approved USDC into the pair; pair sends WETH to the arbitrageur.
        usdc.approve(address(router), depositedUsdc);
        router.swapExactTokensForTokens(depositedUsdc, quote[1], path, arbitrageur, block.timestamp);
        vm.stopPrank();
        uint256 wethBought = weth.balanceOf(arbitrageur);
        // Independently apply the 0.3% fee and constant-product output formula.
        uint256 expectedWeth =
            depositedUsdc * 997 * INITIAL_WETH_RESERVE / (INITIAL_USDC_RESERVE * 1000 + depositedUsdc * 997);
        assertEq(wethBought, expectedWeth); //  18.327830550951836598 WETH

        // Reserve    Before       After
        // WETH       100          81.672169 (approximately)
        // USDC       200,000      245,016.508349

        (wethReserve, usdcReserve) = UniswapV2Library.getReserves(router.factory(), address(weth), address(usdc));
        uint256 finalPrice = router.quote(1 ether, wethReserve, usdcReserve);

        // 4. Verify the pool reserves and reserve-ratio price after the purchase.
        assertEq(wethReserve, INITIAL_WETH_RESERVE - expectedWeth); // 100 WETH - 18.32 WETH = 81,68 WETH
        assertEq(usdcReserve, INITIAL_USDC_RESERVE + depositedUsdc); // 200,000 USDC + 45,016 USDC = 245,016
        assertEq(finalPrice, CEX_PRICE); // 3,000 USDC/WETH at USDC precision.

        assertEq(usdc.balanceOf(arbitrageur), INITIAL_ARBITRAGEUR_USDC_BALANCE - depositedUsdc);

        // 5. Sell all purchased WETH to the CEX at 3,000 USDC per WETH.
        vm.startPrank(arbitrageur);
        weth.approve(address(cex), wethBought);
        uint256 usdcReceived = cex.sellWeth(wethBought);
        vm.stopPrank();

        // Arbitrageur receives 54,983.491652 USDC from his sell
        uint256 expectedUsdc = expectedWeth * CEX_PRICE / 1 ether;
        assertEq(usdcReceived, expectedUsdc);
        assertEq(expectedUsdc, 54_983_491_652); // 18.32 WETH x 3,000 USDC/WETH = 54,983.491652 USDC, rounded down.

        assertEq(weth.balanceOf(arbitrageur), 0); // All WETH was spent
        // The arbitrageur's final balance is = 50,000 − 45,016.508349 + 54,983.491652 = 59,966.983303 USDC
        assertEq(usdc.balanceOf(arbitrageur), INITIAL_ARBITRAGEUR_USDC_BALANCE - depositedUsdc + expectedUsdc);

        // Profit after the pool fee, excluding gas and CEX fees.
        // Profit = Final balance - Initial balance = 59,966.983303 − 50,000 = 9,966.983303 USDC
        uint256 profit = usdc.balanceOf(arbitrageur) - INITIAL_ARBITRAGEUR_USDC_BALANCE;
        assertEq(profit, 9_966_983_303);

        // The CEX received the WETH and paid from its own USDC balance.
        assertEq(weth.balanceOf(address(cex)), wethBought);
        assertEq(usdc.balanceOf(address(cex)), INITIAL_CEX_USDC_BALANCE - expectedUsdc);
    }
}
