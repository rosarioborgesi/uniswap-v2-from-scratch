// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {UniswapV2Factory} from "../../src/v2-core/UniswapV2Factory.sol";
import {IUniswapV2Pair} from "../../src/v2-core/interfaces/IUniswapV2Pair.sol";
import {UniswapV2Router02} from "../../src/v2-periphery/UniswapV2Router02.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockWETH} from "../mocks/MockWETH.sol";

contract RouterIntegrationTest is Test {
    address provider;
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockWETH weth;
    UniswapV2Factory factory;
    UniswapV2Router02 router;

    function setUp() public {
        provider = makeAddr("provider");
        tokenA = new MockERC20(address(this), 10_000 ether, 18);
        tokenB = new MockERC20(address(this), 10_000 ether, 18);
        weth = new MockWETH();
        factory = new UniswapV2Factory(address(this));
        router = new UniswapV2Router02(address(factory), address(weth));
    }

    /////////////////////////////////////////
    //             addLiquidity            //
    /////////////////////////////////////////
    // Verifies that the router creates a missing pair and deposits both desired amounts.
    function test_AddLiquidityCreatesAndFundsNewPair() public {
        tokenA.transfer(provider, 100 ether);
        tokenB.transfer(provider, 400 ether);

        // The provider calls addLiquidity on the router and since the pair doesn't
        // exist we expect that the router will create a new one with 100 tokenA and
        // 400 tokenB
        vm.startPrank(provider);
        tokenA.approve(address(router), 100 ether);
        tokenB.approve(address(router), 400 ether);
        router.addLiquidity(
            address(tokenA), address(tokenB), 100 ether, 400 ether, 100 ether, 400 ether, provider, block.timestamp
        );
        vm.stopPrank();

        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(address(tokenA), address(tokenB)));
        // Verify that has created a new pair with 100 tokenA and 400 tokenB
        assertEq(tokenA.balanceOf(address(pair)), 100 ether);
        assertEq(tokenB.balanceOf(address(pair)), 400 ether);
        assertEq(pair.balanceOf(provider), 200 ether - pair.MINIMUM_LIQUIDITY());
    }

    // Verifies that the router adds liquidity to an existing pair at its reserve ratio.
    function test_AddLiquidityFundsExistingPairAtReserveRatio() public {
        // 1. Seed the pair with 2,000 token A and 8,000 token B
        address pair = factory.createPair(address(tokenA), address(tokenB));
        tokenA.transfer(pair, 2_000 ether);
        tokenB.transfer(pair, 8_000 ether);
        IUniswapV2Pair(pair).mint(address(this));

        // 2. Add Liquidity
        // The provider offers up to 100 A and 500 B, with minimums of 100 A and 400 B.
        // At the pool’s ratio, 100 A requires 400 B, 
        // so the router transfers 100 A and 400 B. 
        // The other 100 B stays with the provider.
        tokenA.transfer(provider, 100 ether);
        tokenB.transfer(provider, 500 ether);
        vm.startPrank(provider);
        tokenA.approve(address(router), 100 ether);
        tokenB.approve(address(router), 500 ether);
        router.addLiquidity(
            address(tokenA), address(tokenB), 100 ether, 500 ether, 100 ether, 400 ether, provider, block.timestamp
        );
        vm.stopPrank();

        assertEq(tokenA.balanceOf(pair), 2_100 ether);
        assertEq(tokenB.balanceOf(pair), 8_400 ether);
        assertEq(IUniswapV2Pair(pair).balanceOf(provider), 200 ether);
    }

    /////////////////////////////////////////
    //            addLiquidityETH          //
    /////////////////////////////////////////
    // checks that the router uses only the ETH needed to match an existing pool’s ratio and refunds the rest.
    function test_AddLiquidityETHWrapsRequiredETHAndRefundsExcess() public {
        // 1. Seed the pool with 2,000 tokenA and 10 WETH
        vm.deal(address(this), 10 ether);
        weth.deposit{value: 10 ether}();
        address pair = factory.createPair(address(tokenA), address(weth));
        tokenA.transfer(pair, 2_000 ether);
        weth.transfer(pair, 10 ether);
        IUniswapV2Pair(pair).mint(address(this));

        // 2. The provider is depositing 1 ETH and 100 token A
        // At the pool’s ratio of 200 tokens per WETH, depositing 100 tokens requires 0.5 WETH.
        // 0.5 ETH must be refunded to the provider
        tokenA.transfer(provider, 100 ether);
        vm.deal(provider, 1 ether);
        vm.startPrank(provider);
        tokenA.approve(address(router), 100 ether);
        router.addLiquidityETH{value: 1 ether}(
            address(tokenA), 100 ether, 100 ether, 0.5 ether, provider, block.timestamp
        );
        vm.stopPrank();

        // The pair ends with 2,100 tokens and 10.5 WETH
        assertEq(tokenA.balanceOf(pair), 2_100 ether);
        assertEq(weth.balanceOf(pair), 10.5 ether);
        // The provider was refund of 0.5 ETH
        assertEq(provider.balance, 0.5 ether);
    }
}
