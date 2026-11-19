// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {UniswapV2Factory} from "../../../src/v2-core/UniswapV2Factory.sol";
import {IUniswapV2Pair} from "../../../src/v2-core/interfaces/IUniswapV2Pair.sol";
import {UniswapV2Library} from "../../../src/v2-periphery/libraries/UniswapV2Library.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";

contract UniswapV2LibraryUnitTest is Test {
    ////////////////////////////////////
    //            sortTokens          //
    ////////////////////////////////////
    function test_SortTokensReturnsAddressesInAscendingOrder() public pure {
        address lower = address(0xA1);
        address higher = address(0xB1);

        (address token0, address token1) = UniswapV2Library.sortTokens(higher, lower);

        assertEq(token0, lower);
        assertEq(token1, higher);
    }

    /////////////////////////////////
    //            pairFor          //
    /////////////////////////////////
    function test_PairForPredictsTheFactoryDeploymentAddress() public {
        UniswapV2Factory factory = new UniswapV2Factory(address(this));
        address tokenA = address(0xA1);
        address tokenB = address(0xB1);

        address predictedPair = UniswapV2Library.pairFor(address(factory), tokenB, tokenA);
        address deployedPair = factory.createPair(tokenA, tokenB);

        assertEq(predictedPair, deployedPair);
    }

    /////////////////////////////////////
    //            getReserves          //
    /////////////////////////////////////
    function test_GetReservesReturnsReservesInRequestedTokenOrder() public {
        UniswapV2Factory factory = new UniswapV2Factory(address(this));
        MockERC20 token0 = new MockERC20(address(this), 40_000, 18);
        MockERC20 token1 = new MockERC20(address(this), 40_000, 18);
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }
        _seedPair(factory, token0, token1, 10_000, 40_000);

        // Ask for token1 first to reverse the pair's storage order.
        (uint256 reserveA, uint256 reserveB) =
            UniswapV2Library.getReserves(address(factory), address(token1), address(token0));

        assertEq(reserveA, 40_000);
        assertEq(reserveB, 10_000);
    }

    ///////////////////////////////
    //            quote          //
    ///////////////////////////////
    function test_QuoteUsesTheReserveRatio() public pure {
        // A reserve ratio of 4 B per A matches 1,000 A with 4,000 B for a liquidity deposit.
        // amountB = amountA * reserveB / reserveA = 1,000 x 40,000 / 10,000 = 4,000
        assertEq(UniswapV2Library.quote(1_000, 10_000, 40_000), 4_000);
    }

    //////////////////////////////////////
    //            getAmountOut          //
    //////////////////////////////////////
    function test_GetAmountOutAppliesTheSwapFeeAndRoundsDown() public pure {
        // amountOut = (amountIn x 997 x reserveOut) / (reserveIn x 1000 + amountIn x 997)
        //           = (997 x 40,000) / (10,000 + 997) = 39,880,000 / 10,997 = 3,626
        assertEq(UniswapV2Library.getAmountOut(1_000, 10_000, 40_000), 3_626);
    }

    /////////////////////////////////////
    //            getAmountIn          //
    /////////////////////////////////////
    function test_GetAmountInRoundsUpTheInputNeededForTheOutput() public pure {
        // Buying 4,000 B leaves 36,000 B in the pool. Accounting for the fee requires 1,115 whole units of A.
        // amountIn = (reserveIn x amountOut x 1,000) / ((reserveOut - amountOut) x 997)) + 1
        //          = (10,000 x 4,000 x 1,000) / ((40,000 - 4,000) x997) + 1 = 1,115
        assertEq(UniswapV2Library.getAmountIn(4_000, 10_000, 40_000), 1_115);
    }

    ///////////////////////////////////////
    //            getAmountsOut          //
    ///////////////////////////////////////
    // How much C do I get in return from 1,000 A, using the route A → B → C?
    function test_GetAmountsOutUsesEachHopOutputAsTheNextInput() public {
        (UniswapV2Factory factory, address[] memory path) = _twoHopRoute();

        uint256[] memory amounts = UniswapV2Library.getAmountsOut(address(factory), 1_000, path);        
        // Hop	    Pool reserves	        Input	    Quoted output
        // A → B	10,000 A and 40,000 B	1,000 A	    3,626 B
        // B → C	20,000 B and 50,000 C	3,626 B	    7,654 C

        uint256[] memory expected = new uint256[](3);
        expected[0] = 1_000; // Starting amount of A.
        expected[1] = 3_626; // B from the first pair, spent in the second pair.
        expected[2] = 7_654; // C received from the second pair.
        assertEq(amounts, expected);
    }

    // If I want 7,500 C from the route A → B → C, how much A do I need to start with?
    function test_GetAmountsInWorksBackwardFromTheFinalOutput() public {
        (UniswapV2Factory factory, address[] memory path) = _twoHopRoute();

        uint256[] memory amounts = UniswapV2Library.getAmountsIn(address(factory), 7_500, path);
        // Swap hop	    Pool reserves	        Desired output	    Required input
        // B → C	    20,000 B and 50,000 C	7,500 C	            3,541 B
        // A → B	    10,000 A and 40,000 B	3,541 B	            975 A

        uint256[] memory expected = new uint256[](3);
        expected[2] = 7_500; // Desired output of C.
        expected[1] = 3_541; // B needed to buy that C.
        expected[0] = 975; // A needed to buy that B.
        assertEq(amounts, expected);
    }

    function _twoHopRoute() internal returns (UniswapV2Factory factory, address[] memory path) {
        factory = new UniswapV2Factory(address(this));
        MockERC20 tokenA = new MockERC20(address(this), 10_000, 18);
        MockERC20 tokenB = new MockERC20(address(this), 60_000, 18);
        MockERC20 tokenC = new MockERC20(address(this), 50_000, 18);
        _seedPair(factory, tokenA, tokenB, 10_000, 40_000);
        _seedPair(factory, tokenB, tokenC, 20_000, 50_000);

        path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);
    }

    function _seedPair(UniswapV2Factory factory, MockERC20 tokenA, MockERC20 tokenB, uint256 amountA, uint256 amountB)
        internal
    {
        address pair = factory.createPair(address(tokenA), address(tokenB));
        tokenA.transfer(pair, amountA);
        tokenB.transfer(pair, amountB);
        IUniswapV2Pair(pair).mint(address(this));
    }
}
