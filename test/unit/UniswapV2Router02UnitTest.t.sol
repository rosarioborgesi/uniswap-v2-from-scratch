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

    function exposedSwap(uint256[] memory amounts, address[] memory path, address to) external {
        _swap(amounts, path, to);
    }
}

contract UniswapV2Router02UnitTest is Test {
    UniswapV2Factory factory;
    UniswapV2Router02Harness router;
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockERC20 tokenC;
    address recipient;

    function setUp() public {
        factory = new UniswapV2Factory(address(this));
        router = new UniswapV2Router02Harness(address(factory));
        tokenA = new MockERC20(address(this), 50_000, 18);
        tokenB = new MockERC20(address(this), 50_000, 18);
        tokenC = new MockERC20(address(this), 50_000, 18);

        recipient = makeAddr("recipient");
    }

    ///////////////////////////////////////
    //            _addLiquidity          //
    ///////////////////////////////////////

    // Verifies that creates the missing pair and returns the desired deposit amounts
    function test_AddLiquidityCreatesPairWhenMissing() public {
        uint256 amountADesired = 1_000;
        uint256 amountBDesired = 4_000;

        assertEq(factory.getPair(address(tokenA), address(tokenB)), address(0));

        (uint256 amountA, uint256 amountB) =
            router.exposedAddLiquidity(address(tokenA), address(tokenB), amountADesired, amountBDesired, 0, 0);

        address pair = factory.getPair(address(tokenA), address(tokenB));
        assertGt(pair.code.length, 0);
        assertEq(amountA, amountADesired);
        assertEq(amountB, amountBDesired);
    }

    // Verifies that _addLiquidity keeps the desired amount of token A and
    // adjusts token B to match the existing pair’s reserve ratio when the
    // quoted amount is within the requested bounds.
    function test_AddLiquidityUsesDesiredAAndOptimalB() public {
        _seedPair(tokenA, tokenB, 10_000, 40_000);

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
        _seedPair(tokenA, tokenB, 10_000, 40_000);

        // At 4 B per A, 1,500 A would require 6,000 B.
        // The desired 4,000 B pairs with 1,000 A.
        // With only 4,000 B desired it returns 1,000 A and 4,000 B, meeting the minimum for A exactly.
        (uint256 amountA, uint256 amountB) =
            router.exposedAddLiquidity(address(tokenA), address(tokenB), 1_500, 4_000, 1_000, 4_000);

        assertEq(amountA, 1_000);
        assertEq(amountB, 4_000);
    }

    ///////////////////////////////////////
    //              _swap                //
    ///////////////////////////////////////
    // Checks that _swap sends the requested amount of token B to the recipient after the caller funds the A/B pair.
    function test_SwapSingleHopSendsTokenBToRecipient() public {
        // 1. Seed the pair
        // _seedPair creates the A/B pair, deposits 10,000 units of each token,
        // and mints LP tokens so the pair records those balances as its initial reserves.
        address pairAB = _seedPair(tokenA, tokenB, 10_000, 10_000);

        // 2. Specify the swap.
        // path = [A, B] describes one hop.
        // amounts = [1,000, 906] represents 1,000 units of A in and 906 units of B out.
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000;
        amounts[1] = 906; // Output after the 0.3% fee and integer rounding.

        // 3. Fund the pair
        // The test transfers 1,000 A to the pair
        tokenA.transfer(pairAB, amounts[0]);

        // 4. Execute the swap
        // The harness calls _swap, which requests 906 B from the pair.
        // Since this is the only hop, the pair sends B directly to recipient.
        router.exposedSwap(amounts, path, recipient);

        assertEq(tokenB.balanceOf(recipient), 906); // 906 B is the expected output
        assertEq(tokenA.balanceOf(pairAB), 11_000); // The pair has 11,000 A (10,000 + 1,000)
        assertEq(tokenB.balanceOf(pairAB), 9_094); // The pair has 9,094 B (10,000 - 906)
    }

    // Checks that _swap sends the intermediate token B directly from the A/B pair to the B/C pair,
    // then sends the final token C to the recipient.
    function test_SwapTwoHopsSendsTokenBToNextPairAndTokenCToRecipient() public {
        // 1. Seed both pairs
        // A/B starts with 10,000 A and 10,000 B
        // B/C starts with 10,000 B and 10,000 C
        address pairAB = _seedPair(tokenA, tokenB, 10_000, 10_000);
        address pairBC = _seedPair(tokenB, tokenC, 10_000, 10_000);

        // 2. Specify the route and amounts
        // path = [A, B, C] and amounts = [1_000, 906, 828]
        // The first hop takes 1,000 A and outputs 906 B.
        // The second uses that 906 B as input and outputs 828 C.
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1_000;
        amounts[1] = 906; // A/B outputs 906 B for 1,000 A.
        amounts[2] = 828; // B/C outputs 828 C for 906 B.

        // 3. Fund the first pair
        tokenA.transfer(pairAB, amounts[0]);

        // 4. Call the swap
        router.exposedSwap(amounts, path, recipient);

        // Step	                From	        To	        Tokens transferred
        // Fund the swap	    Test contract	A/B pair	1,000 A
        // First hop, A → B	    A/B pair	    B/C pair	906 B
        // Second hop, B → C	B/C pair	    Recipient	828 C

        // The A/B pair keeps 1,000 A as payment for the 906 B it sends to the B/C pair.
        assertEq(tokenA.balanceOf(pairAB), 11_000); // 10,000 + 1,000 = 11,000
        // A/B pair	Sends 906 B to the B/C pair
        assertEq(tokenB.balanceOf(pairAB), 9_094); // 10,000 − 906 = 9,094
        // B/C pair Receives that same 906 B as input from A/B pair
        assertEq(tokenB.balanceOf(pairBC), 10_906); // 10,000 + 906 = 10,906
        // B/C sends 828 C to the recipient
        assertEq(tokenC.balanceOf(pairBC), 9_172); // 10,000 − 828 = 9,172

        // The recipient has 828 C and a zero B balance
        assertEq(tokenB.balanceOf(recipient), 0); // The B transfer goes directly from A/B to B/C
        assertEq(tokenC.balanceOf(recipient), 828); // Receives 828 C from the B/C pair
    }

    function _seedPair(MockERC20 firstToken, MockERC20 secondToken, uint256 firstReserve, uint256 secondReserve)
        private
        returns (address pair)
    {
        pair = factory.createPair(address(firstToken), address(secondToken));
        firstToken.transfer(pair, firstReserve);
        secondToken.transfer(pair, secondReserve);
        IUniswapV2Pair(pair).mint(address(this));
    }
}
