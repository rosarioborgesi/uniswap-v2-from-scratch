// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {UniswapV2Factory} from "../../src/v2-core/UniswapV2Factory.sol";
import {IUniswapV2Pair} from "../../src/v2-core/interfaces/IUniswapV2Pair.sol";
import {UniswapV2Router02} from "../../src/v2-periphery/UniswapV2Router02.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract UniswapV2Router02Harness is UniswapV2Router02 {
    constructor(address factory_) UniswapV2Router02(factory_, address(0)) {}

    function exposedAddLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) external returns (uint256 amountA, uint256 amountB) {
        return _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
    }
}

contract UniswapV2Router02UnitTest is Test {
    ///////////////////////////////////////
    //            _addLiquidity          //
    ///////////////////////////////////////

    // Verifies that creates the missing pair and returns the desired deposit amounts
    function test_AddLiquidityCreatesPairWhenMissing() public {
        UniswapV2Factory factory = new UniswapV2Factory(address(this));
        UniswapV2Router02Harness router = new UniswapV2Router02Harness(address(factory));
        address tokenA = address(0xA1);
        address tokenB = address(0xB1);
        uint256 amountADesired = 1_000;
        uint256 amountBDesired = 4_000;

        assertEq(factory.getPair(tokenA, tokenB), address(0));

        (uint256 amountA, uint256 amountB) =
            router.exposedAddLiquidity(tokenA, tokenB, amountADesired, amountBDesired, 0, 0);

        address pair = factory.getPair(tokenA, tokenB);
        assertGt(pair.code.length, 0);
        assertEq(amountA, amountADesired);
        assertEq(amountB, amountBDesired);
    }

    // Seeds an existing pair with reserves of 10,000 token A and 40,000 token B
    function _createRouterWithSeededPair()
        private
        returns (UniswapV2Router02Harness router, MockERC20 tokenA, MockERC20 tokenB)
    {
        UniswapV2Factory factory = new UniswapV2Factory(address(this));
        router = new UniswapV2Router02Harness(address(factory));
        uint256 reserveA = 10_000;
        uint256 reserveB = 40_000;
        tokenA = new MockERC20(address(this), reserveA, 18);
        tokenB = new MockERC20(address(this), reserveB, 18);
        address pair = factory.createPair(address(tokenA), address(tokenB));
        tokenA.transfer(pair, reserveA);
        tokenB.transfer(pair, reserveB);        
        IUniswapV2Pair(pair).mint(address(this));
    }

    // Verifies that _addLiquidity keeps the desired amount of token A and
    // adjusts token B to match the existing pair’s reserve ratio when the
    // quoted amount is within the requested bounds.
    function test_AddLiquidityUsesDesiredAAndOptimalB() public {
        (UniswapV2Router02Harness router, MockERC20 tokenA, MockERC20 tokenB) = _createRouterWithSeededPair();

        // calls _addLiquidity with desired amounts of 1,000 A and 5,000 B.
        // At 4 B per A, depositing 1,000 A requires 4,000 B, exactly the minimum.
        // So the router returns 1,000 A and 4,000 B.
        // The quoted 4,000 B is below the desired 5,000 B and exactly meets the minimum.
        (uint256 amountA, uint256 amountB) =
            router.exposedAddLiquidity(address(tokenA), address(tokenB), 1_000, 5_000, 1_000, 4_000);

        assertEq(amountA, 1_000);
        assertEq(amountB, 4_000);
    }

    // Verifies that _addLiquidity keeps the desired amount of token B and
    // adjusts token A to match the existing pair's reserve ratio when B limits the deposit.
    function test_AddLiquidityUsesOptimalAAndDesiredB() public {
        (UniswapV2Router02Harness router, MockERC20 tokenA, MockERC20 tokenB) = _createRouterWithSeededPair();

        // At 4 B per A, 1,500 A would require 6,000 B. 
        // The desired 4,000 B pairs with 1,000 A.
        // With only 4,000 B desired it returns 1,000 A and 4,000 B, meeting the minimum for A exactly.
        (uint256 amountA, uint256 amountB) =
            router.exposedAddLiquidity(address(tokenA), address(tokenB), 1_500, 4_000, 1_000, 4_000);

        assertEq(amountA, 1_000);
        assertEq(amountB, 4_000);
    }    
}
