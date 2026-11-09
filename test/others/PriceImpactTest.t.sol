// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {UniswapV2Factory} from "../../src/v2-core/UniswapV2Factory.sol";
import {UniswapV2Router02} from "../../src/v2-periphery/UniswapV2Router02.sol";
import {UniswapV2Library} from "../../src/v2-periphery/libraries/UniswapV2Library.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract PriceImpactTest is Test {
    MockERC20 internal weth;
    MockERC20 internal usdc;
    UniswapV2Router02 internal router;

    address internal liquidityProvider = makeAddr("liquidityProvider");
    address internal trader = makeAddr("trader");

    uint256 internal constant INITIAL_WETH_RESERVE = 100 ether;
    uint256 internal constant INITIAL_USDC_RESERVE = 300_000 * 1e6;
    uint256 internal constant INITIAL_PRICE = 3_000 * 1e6; // USDC / WETH = 3,000
    uint256 internal constant TRADER_WETH_BALANCE = 50 ether;

    function setUp() public {       
        weth = new MockERC20(liquidityProvider, INITIAL_WETH_RESERVE + TRADER_WETH_BALANCE, 18);
        usdc = new MockERC20(liquidityProvider, INITIAL_USDC_RESERVE, 6);
        UniswapV2Factory factory = new UniswapV2Factory(address(this));
        router = new UniswapV2Router02(address(factory), address(weth));

        vm.startPrank(liquidityProvider);
        weth.transfer(trader, TRADER_WETH_BALANCE);
        weth.approve(address(router), INITIAL_WETH_RESERVE);
        usdc.approve(address(router), INITIAL_USDC_RESERVE);
        // This creates a pool with 100 WETH and 300,000 USDC
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

    // demonstrates that selling a small amount relative to the pool’s reserves produces only a small reduction in the execution price.
    function test_SmallSwapHasLowPriceImpact() public {
        // The pool contains 100 WETH and 300,000 USDC, so its initial price is 3,000 USDC per WETH
        
        // 1. Calculate the spot-price estimate (If the price stayed fixed).
        // Selling 0.1% of the WETH reserve: the spot-price estimate is 300 USDC.
        // The trader expects 0.1 WETH x 3,000 WETH/USDC = 300 USDC
        uint256 amountIn = 0.1 ether;
        uint256 spotEstimate = amountIn * INITIAL_PRICE / 1 ether;
        assertEq(spotEstimate, 300 * 1e6); // 300 USDC


        // 2. Execute the swap
        // The trader receives 298.802094 USDC for 0.1 WETH 

        // This follows the fee-adjusted constant-product formula:
        // effective input = 0.1 × 0.997 = 0.0997 WETH 
        // output = (0.0997 × 300,000) / (100 + 0.0997)
        //        ≈ 298.802094 USDC
        uint256 actualOutput = _sellWeth(amountIn);        
        assertEq(actualOutput, 298_802094); // 298.802094 USDC

        // The trader loss is 300 USDC - 299 USDC ≈ 1 USDC
    }

    // Selling a large amount relative to the pool’s reserves gives a much worse average execution price than the initial spot price.
    function test_LargeSwapHasHighPriceImpact() public {
        // The pool contains 100 WETH and 300,000 USDC, so its initial price is 3,000 USDC per WETH

        // 1. Calculate the spot-price estimate (If the price stayed fixed).
        // Selling 50% of the WETH reserve: the spot-price estimate is 150,000 USDC.
        // The trader expects 50 WETH x 3,000 WETH/USDC = 150,000 USDC
        uint256 amountIn = 50 ether;
        uint256 spotEstimate = amountIn * INITIAL_PRICE / 1 ether;
        assertEq(spotEstimate, 150_000 * 1e6); // 150,000 USDC

        // 2. Execute the swap
        // The trader receives 99,799.799799 USDC for 50 WETH

        // This follows the fee-adjusted constant-product formula:
        // effective input = 50 × 0.997 = 49.85 WETH
        // output = (49.85 × 300,000) / (100 + 49.85)
        //        ≈ 99,799.799799 USDC
        uint256 actualOutput = _sellWeth(amountIn);
        assertEq(actualOutput, 99_799_799799); // 99,799.799799 USDC

        // The trader loss is 150,000 USDC - 99,799 ≈ 50,201 USDC
    }

    // Executes a WETH → USDC swap 
    // - amountIn: how much WETH the trader sells, using 18 decimals.
    // - actualOutput: how much USDC the trader receives, using 6 decimals.
    function _sellWeth(uint256 amountIn) internal returns (uint256 actualOutput) {
        // 1. Read the reserves and verify the initial price.
        (uint256 wethReserve, uint256 usdcReserve) =
            UniswapV2Library.getReserves(router.factory(), address(weth), address(usdc));
        assertEq(router.quote(1 ether, wethReserve, usdcReserve), INITIAL_PRICE); // USDC / WETH = 3,000

        // 2. Define the swap route and obtain a quote.
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(usdc);
        // quotedAmounts[0] is the WETH input. 
        // quotedAmounts[1] is the expected USDC output, including both the fee and price impact.
        uint256[] memory quotedAmounts = router.getAmountsOut(amountIn, path);

        vm.startPrank(trader);
        weth.approve(address(router), amountIn);
        // 4. Execute the swap.
        uint256[] memory amounts =
            router.swapExactTokensForTokens(amountIn, quotedAmounts[1], path, trader, block.timestamp);
        vm.stopPrank();

        // 5. Verify the trader’s output and balances.
        // The trader starts with zero USDC, so this balance equals the amount received.
        actualOutput = usdc.balanceOf(trader);
    }
}
