// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {UniswapV2Factory} from "../../src/v2-core/UniswapV2Factory.sol";
import {UniswapV2Pair} from "../../src/v2-core/UniswapV2Pair.sol";
import {UniswapV2Router02} from "../../src/v2-periphery/UniswapV2Router02.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract LiquidityProviderFeesTest is Test {
    address internal provider = makeAddr("poolCreator");
    address internal user = makeAddr("liquidityUser");
    address internal largeTrader = makeAddr("largeTrader");
    address internal smallTrader = makeAddr("smallTrader");
    MockERC20 internal weth;
    MockERC20 internal usdc;
    UniswapV2Router02 internal router;
    UniswapV2Pair internal pair;

    // This test demonstrates how trading fees benefit a liquidity provider
    // In this test the protocol's fee are disbaled and all the fees go to LPs
    function test_UserEarnsFeesFromLargeAndSmallTrades() public {
        weth = new MockERC20(provider, 210.1 ether, 18);
        usdc = new MockERC20(provider, 600_000 * 1e6, 6);
        UniswapV2Factory factory = new UniswapV2Factory(address(this));
        router = new UniswapV2Router02(address(factory), address(weth));

        // 1. The provider creates a pool with 100 WETH and 300,000 USDC:
        // the initial price is 3,000 USDC per WETH. WETH is an ERC-20 mock.
        vm.startPrank(provider);
        weth.transfer(user, 100 ether);
        usdc.transfer(user, 300_000 * 1e6);
        weth.transfer(largeTrader, 10 ether);
        weth.transfer(smallTrader, 0.1 ether);
        weth.approve(address(router), 100 ether);
        usdc.approve(address(router), 300_000 * 1e6);
        router.addLiquidity(
            address(weth), address(usdc), 100 ether, 300_000 * 1e6, 100 ether, 300_000 * 1e6, provider, block.timestamp
        );
        vm.stopPrank();
        pair = UniswapV2Pair(factory.getPair(address(weth), address(usdc)));
        assertEq(router.quote(1 ether, 100 ether, 300_000 * 1e6), 3_000 * 1e6);
        // Protocol fees are disabled. The full 0.3% trading fee benefits liquidity providers.
        assertEq(factory.feeTo(), address(0)); 

        // 2. The user deposits 100 WETH and 300,000 USDC, owning exactly 50%.
        // Total pool reserves are now 200 WETH and 600,000 USDC.
        vm.startPrank(user);
        weth.approve(address(router), 100 ether);
        usdc.approve(address(router), 300_000 * 1e6);
        (,, uint256 userLiquidity) = router.addLiquidity(
            address(weth), address(usdc), 100 ether, 300_000 * 1e6, 100 ether, 300_000 * 1e6, user, block.timestamp
        );
        vm.stopPrank();
        assertEq(userLiquidity * 2, pair.totalSupply());

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(usdc);

        // 3. The large trader sells 10 WETH. The 0.3% fee is 0.03 WETH;
        // the user's 50% share is 0.015 WETH, retained inside the pool.
        // The large trader receives 28,489.784254 USDC for selling 10 WETH.
        vm.startPrank(largeTrader);
        weth.approve(address(router), 10 ether);
        router.swapExactTokensForTokens(
            10 ether, router.getAmountsOut(10 ether, path)[1], path, largeTrader, block.timestamp
        );
        vm.stopPrank();
        assertEq(usdc.balanceOf(largeTrader), 28_489_784254); // 28,489.784254 USDC

        // Reserves now:
        // WETH = 200 + 10 = 210 WETH
        // USDC = 600,000 - 28,489.784254 = 571,510.215746 USDC

        // 4. The small trader sells 0.1 WETH (100 times less). Its fee is
        // 0.0003 WETH; the user's share is 0.00015 WETH (also 100 times less).
        //The small trader receives 271.202521 USDC for selling 0.1 WETH.
        vm.startPrank(smallTrader);
        weth.approve(address(router), 0.1 ether);
        router.swapExactTokensForTokens(
            0.1 ether, router.getAmountsOut(0.1 ether, path)[1], path, smallTrader, block.timestamp
        );
        vm.stopPrank();
        assertEq(usdc.balanceOf(smallTrader), 271_202521);

        // Reserves now:
        // WETH: 210 + 0.1 = 210.1 WETH
        // USDC: 571,510.215746 − 271.202521 = 571,239.013225 USDC

        // Since the input token is WETH, the fees are calculated in WETH.

        // Fees generated:
        // Trade	  Total fee (0.3%)	  User’s 50% share   Provider’s fees (≈50%
        // 10 WETH	  0.03 WETH	          0.015 WETH         ≈0.015 WETH
        // 0.1 WETH	  0.0003 WETH	      0.00015 WETH       ≈0.00015 WETH
        // Total	  0.0303 WETH	      0.01515 WETH       ≈0.01515 WETH

        // Both provider and user own 50% of the pool, except that the provider’s share is slightly smaller because of the permanently locked minimum liquidity.

        // 5. Withdraw through the router. Selling WETH changed the pool's mix:
        // the user receives more WETH and less USDC than originally deposited.
        // The entire extra WETH is NOT fee income: most comes from the trades.
        vm.startPrank(user);
        pair.approve(address(router), userLiquidity);
        (uint256 withdrawnWeth, uint256 withdrawnUsdc) = router.removeLiquidity(
            address(weth), address(usdc), userLiquidity, 105.05 ether, 285_619_506612, user, block.timestamp
        );
        vm.stopPrank();
        // The user owns 50% of the pool, so burning all their LP tokens returns half of each reserve.
        assertEq(withdrawnWeth, 105.05 ether); // 210.1 WETH / 2 = 105.05 WETH
        assertEq(withdrawnUsdc, 285_619_506612); // 571,239.013225 USDC / 2 = 285,619.5066125 USDC
        assertEq(weth.balanceOf(user), withdrawnWeth);
        assertEq(usdc.balanceOf(user), withdrawnUsdc);
        assertEq(pair.balanceOf(user), 0);

        // The user's share of the fees charged on both swaps totals 0.01515 WETH.
        // These fees remain in the pool and are included in the user's proportional withdrawal.
    
        
        // When protocol fees are enabled, the protocol receives approximately one-sixth of fee growth, leaving five-sixths for liquidity providers.

        // The trader still pays 0.3%. The effective split is approximately:
        // - 0.25% for liquidity providers collectively.
        // - 0.05% for the protocol        
    
    }
}
