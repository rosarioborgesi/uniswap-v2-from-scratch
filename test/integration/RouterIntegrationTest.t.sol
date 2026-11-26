// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {UniswapV2Factory} from "../../src/v2-core/UniswapV2Factory.sol";
import {IUniswapV2Pair} from "../../src/v2-core/interfaces/IUniswapV2Pair.sol";
import {UniswapV2Router02} from "../../src/v2-periphery/UniswapV2Router02.sol";
import {IUniswapV2Router02} from "../../src/v2-periphery/interfaces/IUniswapV2Router02.sol";
import {UniswapV2Library} from "../../src/v2-periphery/libraries/UniswapV2Library.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockWETH} from "../mocks/MockWETH.sol";

contract RouterIntegrationTest is Test {
    address provider;
    uint256 providerKey;
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockERC20 tokenC;
    MockWETH weth;
    UniswapV2Factory factory;
    UniswapV2Router02 router;
    address recipient;

    function setUp() public {
        recipient = makeAddr("recipient");
        (provider, providerKey) = makeAddrAndKey("provider");
        tokenA = new MockERC20(address(this), 10_000 ether, 18);
        tokenB = new MockERC20(address(this), 10_000 ether, 18);
        tokenC = new MockERC20(address(this), 10_000 ether, 18);
        weth = new MockWETH();
        factory = new UniswapV2Factory(address(this));
        router = new UniswapV2Router02(address(factory), address(weth));        
    }    

    function _seedSwapPair(MockERC20 firstToken, MockERC20 secondToken, uint256 firstAmount, uint256 secondAmount)
        internal
    {
        firstToken.approve(address(router), firstAmount);
        secondToken.approve(address(router), secondAmount);
        router.addLiquidity(
            address(firstToken), address(secondToken), firstAmount, secondAmount, 0, 0, address(this), block.timestamp
        );
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
        // 1. Create and seed the pair through the router.
        tokenA.approve(address(router), 2_000 ether);
        tokenB.approve(address(router), 8_000 ether);
        router.addLiquidity(
            address(tokenA), address(tokenB), 2_000 ether, 8_000 ether, 2_000 ether, 8_000 ether, address(this), block.timestamp
        );
        address pair = factory.getPair(address(tokenA), address(tokenB));

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
        // 1. Seed the pool through the router with 2,000 token A and 10 ETH.
        vm.deal(address(this), 10 ether);
        tokenA.approve(address(router), 2_000 ether);
        router.addLiquidityETH{value: 10 ether}(
            address(tokenA), 2_000 ether, 2_000 ether, 10 ether, address(this), block.timestamp
        );
        address pair = factory.getPair(address(tokenA), address(weth));

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

    /////////////////////////////////////////
    //            removeLiquidity          //
    /////////////////////////////////////////
    function test_RemoveLiquidityReturnsBothTokens() public {
        // Seed the pair with 100 token A and 400 token B
        tokenA.approve(address(router), 100 ether);
        tokenB.approve(address(router), 400 ether);
        router.addLiquidity(
            address(tokenA), address(tokenB), 100 ether, 400 ether, 100 ether, 400 ether, provider, block.timestamp
        );
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(address(tokenA), address(tokenB)));
        // The provider has almost 200 LP tokens (sqrt(100 x 400))
        assertEq(pair.balanceOf(provider), 200 ether - pair.MINIMUM_LIQUIDITY());

        // Redeem 100 LP tokens.
        vm.startPrank(provider);
        pair.approve(address(router), 100 ether);
        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            address(tokenA), address(tokenB), 100 ether, 50 ether, 200 ether, provider, block.timestamp
        );
        vm.stopPrank();

        // The provider receives half of both the reserves
        assertEq(amountA, 50 ether); // 100 ether / 2 = 50 ether
        assertEq(amountB, 200 ether); // 400 ether / 2 = 200 ether
        assertEq(tokenA.balanceOf(provider), 50 ether);
        assertEq(tokenB.balanceOf(provider), 200 ether);

        // The provider has still half of the LP tokens (100)
        assertEq(pair.balanceOf(provider), 100 ether - pair.MINIMUM_LIQUIDITY()); 
    }

    //////////////////////////////////////////
    //           removeLiquidityETH         //
    //////////////////////////////////////////
    function test_RemoveLiquidityETHReturnsTokenAndETH() public {
        // Seed the pair through the router and mint LP tokens to the provider.
        vm.deal(address(this), 4 ether);
        tokenA.approve(address(router), 16 ether);
        router.addLiquidityETH{value: 4 ether}(
            address(tokenA), 16 ether, 16 ether, 4 ether, provider, block.timestamp
        );
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(address(tokenA), address(weth)));
        // The provider has almost 8 LP tokens (sqrt 4 x 16))
        assertEq(pair.balanceOf(provider), 8 ether - pair.MINIMUM_LIQUIDITY());

        // Redeem half of the 8 LP tokens in total supply.
        vm.startPrank(provider);
        pair.approve(address(router), 4 ether);
        (uint256 amountToken, uint256 amountETH) =
            router.removeLiquidityETH(address(tokenA), 4 ether, 8 ether, 2 ether, provider, block.timestamp);
        vm.stopPrank();

        // The provider receives half the token reserves
        assertEq(amountToken, 8 ether); // 16 ether / 2 = 8 ether
        assertEq(amountETH, 2 ether); // 4 ether / 2 = 2 ether
        assertEq(tokenA.balanceOf(provider), 8 ether);
        assertEq(provider.balance, 2 ether);

        // The provider has still half of the LP tokens (4 ether)
        assertEq(pair.balanceOf(provider), 4 ether - pair.MINIMUM_LIQUIDITY());
    }

    /////////////////////////////////////////////////
    //           removeLiquidityWithPermit         //
    /////////////////////////////////////////////////
    function _signPermit(IUniswapV2Pair pair, uint256 value, uint256 nonce, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 structHash =
            keccak256(abi.encode(pair.PERMIT_TYPEHASH(), provider, address(router), value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", pair.DOMAIN_SEPARATOR(), structHash));
        return vm.sign(providerKey, digest);
    }

    function test_RemoveLiquidityWithPermitReturnsBothTokensAndConsumesAllowance() public {
        // Seed the pair with 100 token A and 400 token B
        tokenA.approve(address(router), 100 ether);
        tokenB.approve(address(router), 400 ether);
        router.addLiquidity(
            address(tokenA), address(tokenB), 100 ether, 400 ether, 100 ether, 400 ether, provider, block.timestamp
        );
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(address(tokenA), address(tokenB)));

        // The provider has almost 200 LP tokens (sqrt(100 x 400))
        assertEq(pair.balanceOf(provider), 200 ether - pair.MINIMUM_LIQUIDITY());

        uint256 liquidity = 100 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = pair.nonces(provider);

        // The provider has not given any allowance to the router yet.
        assertEq(pair.allowance(provider, address(router)), 0);

        // Sign the message that give the router the allowance to burn liquidity (100 tokens) LP tokens
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(pair, liquidity, nonce, deadline);

        vm.prank(provider);
        (uint256 amountA, uint256 amountB) = router.removeLiquidityWithPermit(
            address(tokenA), address(tokenB), liquidity, 50 ether, 200 ether, provider, deadline, false, v, r, s
        );

        // The provider has withdrawn half of this tokens
        assertEq(amountA, 50 ether); // 100 ether / 2 = 50 ether
        assertEq(amountB, 200 ether); // 400 ether / 2 = 200 ether 
        assertEq(tokenA.balanceOf(provider), 50 ether);
        assertEq(tokenB.balanceOf(provider), 200 ether);

        // The provide now has almost half LP tokens because has burned half of his supply
        assertEq(pair.balanceOf(provider), 100 ether - pair.MINIMUM_LIQUIDITY());
        assertEq(pair.nonces(provider), nonce + 1);
        assertEq(pair.allowance(provider, address(router)), 0);
    }

    ////////////////////////////////////////////////////
    //           removeLiquidityETHWithPermit         //
    ////////////////////////////////////////////////////
    function test_RemoveLiquidityETHWithPermitReturnsTokenAndETHAndConsumesAllowance() public {
        // Seeding the pair with 4 ETH and 16 token A
        vm.deal(address(this), 4 ether);
        tokenA.approve(address(router), 16 ether);
        router.addLiquidityETH{value: 4 ether}(address(tokenA), 16 ether, 16 ether, 4 ether, provider, block.timestamp);
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(address(tokenA), address(weth)));

        // The provider has almost 8 LP tokens (sqrt 4 x 16))
        assertEq(pair.balanceOf(provider), 8 ether - pair.MINIMUM_LIQUIDITY());

        uint256 liquidity = 4 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = pair.nonces(provider);
        assertEq(pair.allowance(provider, address(router)), 0);

        // Signs the message approving the router to burn liquidity (4) LP tokens
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(pair, liquidity, nonce, deadline);

        // The provider wants to burn half of his LP tokens (4) and withdraw half of both reserves
        vm.prank(provider);
        (uint256 amountToken, uint256 amountETH) = router.removeLiquidityETHWithPermit(
            address(tokenA), liquidity, 8 ether, 2 ether, provider, deadline, false, v, r, s
        );

        // The provider has withdrawn half of the reserves
        assertEq(amountToken, 8 ether); // 16 ether / 2 = 8 ether
        assertEq(amountETH, 2 ether); // 4 ether / 2 = 4 ether
        assertEq(tokenA.balanceOf(provider), 8 ether);
        assertEq(provider.balance, 2 ether);

        // The provider now has half of the LP tokens because half has been burned
        assertEq(pair.balanceOf(provider), 4 ether - pair.MINIMUM_LIQUIDITY());
        assertEq(pair.nonces(provider), nonce + 1);
        assertEq(pair.allowance(provider, address(router)), 0);
    }

    ////////////////////////////////////////////////
    //           swapExactTokensForTokens         //
    ////////////////////////////////////////////////
    // Verifies that the router swaps exactly 1,000 token A for 2,000 token B and sends the output to a separate recipient address.
    function test_SwapExactTokensForTokensSingleHop() public {
        uint256 amountIn = 1_000 ether;     

        // Uniswap’s 0.3% swap fee gives the 1,000 A input an effective value of 997 A for pricing.
        // The extepcted output is 4,000 × 997 / (997 + 997) = 2,000 B
        uint256 expectedOut = 2_000 ether;  
        
        // 1. Seed the pool with 997 token A and 4,000 token B
        tokenA.approve(address(router), 997 ether);
        tokenB.approve(address(router), 4_000 ether);
        router.addLiquidity(
            address(tokenA), address(tokenB), 997 ether, 4_000 ether, 997 ether, 4_000 ether, address(this), block.timestamp
        );

        // We are doing a swap token A -> token B
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);        

        // The test gives provider 1,001 A
        tokenA.transfer(provider, amountIn + 1 ether);        

        // 2. Execute the swap
        // The provider swaps 1,000 token A and recipient receives the output (2,000 B)
        // The pool receives 1,000 token A and gives the recipient 2,000 token B
        vm.startPrank(provider);
        tokenA.approve(address(router), amountIn);
        router.swapExactTokensForTokens(amountIn, expectedOut, path, recipient, block.timestamp);
        vm.stopPrank();

        // Assert the provider has deposited 1,000 token A in the pool
        assertEq(tokenA.balanceOf(provider), 1 ether); // 1,001 - 1,000 = 1
        assertEq(tokenB.balanceOf(recipient), expectedOut); // The recipient has received 2,000 B

        address pair = factory.getPair(address(tokenA), address(tokenB));
        assertEq(tokenA.balanceOf(pair), 997 ether + amountIn); // 997 + 1,000 = 1,997 A
        assertEq(tokenB.balanceOf(pair), 4_000 ether - expectedOut); // 4,000 - 2,000 = 2,000 B
    }

    // verifies that the router spends exactly 1,000 A from the provider and delivers 1,500 C to a separate recipient in one transaction.
    // The path [A, B, C] has two hops because each adjacent pair of tokens is a separate swap.
    function test_SwapExactTokensForTokensTwoHops() public {
        uint256 amountIn = 1_000 ether;
        // The first hop yields 2,000 B. After the fee, 1,994 B buys half of the 3,000 C reserve.
        uint256 expectedTokenCOut = 1_500 ether;
        
        // 1. Seed the pools
        // Seed the A/B pool with 997 token A and 4,000 token B
        tokenA.approve(address(router), 997 ether);
        tokenB.approve(address(router), 4_000 ether);
        router.addLiquidity(
            address(tokenA), address(tokenB), 997 ether, 4_000 ether, 997 ether, 4_000 ether, address(this), block.timestamp
        );

        // Seed the B/C pool with 1,994 token B and 3,000 token C
        tokenB.approve(address(router), 1_994 ether);
        tokenC.approve(address(router), 3_000 ether);
        router.addLiquidity(
            address(tokenB), address(tokenC), 1_994 ether, 3_000 ether, 1_994 ether, 3_000 ether, address(this), block.timestamp
        );

        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        // The test contract gives 1,001 token A to the provider
        tokenA.transfer(provider, amountIn + 1 ether);

        // 2. Execute the swap
        // The provider swaps 1,000 token A for 1,500 token C
        vm.startPrank(provider);
        tokenA.approve(address(router), amountIn);
        router.swapExactTokensForTokens(amountIn, expectedTokenCOut, path, recipient, block.timestamp);
        vm.stopPrank();

        // Hop	    Input	    Output
        // A → B	1,000 A	    2,000 B
        // B → C	2,000 B	    1,500 C

        assertEq(tokenA.balanceOf(provider), 1 ether); // 1,001 - 1,000 = 1
        assertEq(tokenC.balanceOf(recipient), expectedTokenCOut); // 1,500 token C

        // Pool	  Token	  Before	Change	 After
        // A/B	   A	   997	    +1,000	 1,997
        // A/B	   B	   4,000	−2,000	 2,000
        // B/C	   B	   1,994	+2,000	 3,994
        // B/C	   C	   3,000	−1,500	 1,500

        uint256 tokenBAmount = 2_000 ether;

        // The A/B pair receives 1,000 A and sends 2,000 B directly to the B/C pair.
        (uint256 reserveA, uint256 reserveBInAB) =
            UniswapV2Library.getReserves(address(factory), address(tokenA), address(tokenB));
        assertEq(reserveA, 997 ether + amountIn); // 1,997 A
        assertEq(reserveBInAB, 4_000 ether - tokenBAmount); // 2,000 B

        // The B/C pair receives those 2,000 B and sends 1,500 C to the recipient.
        (uint256 reserveBInBC, uint256 reserveC) =
            UniswapV2Library.getReserves(address(factory), address(tokenB), address(tokenC));
        assertEq(reserveBInBC, 1_994 ether + tokenBAmount); // 3,994 B
        assertEq(reserveC, 3_000 ether - expectedTokenCOut); // 1,500 C
    }

    ////////////////////////////////////////////////
    //           swapTokensForExactTokens         //
    ////////////////////////////////////////////////
    // The test asks to deliver 2,000 B while spending at most 1,001 A
    function test_SwapTokensForExactTokensSingleHop() public {
        // 1. Seed the pair
        // The test seeds the pool with 997 A and 4,000 B.
        _seedSwapPair(tokenA, tokenB, 997 ether, 4_000 ether);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256 amountOut = 2_000 ether;
        uint256 amountInMax = 1_001 ether;
        // After the 0.3% fee, buying 2,000 B reserve takes 1,000 A plus one base unit for rounding.
        uint256 requiredA = 1_000 ether + 1;
        
        // The test gives provider 1,001 A
        tokenA.transfer(provider, amountInMax);

        vm.startPrank(provider);
        tokenA.approve(address(router), amountInMax);
        // provider asks to deliver 2,000 B tokens (amountOut) to recipient while spending at most 1,001 A (amountInMax)
        uint256[] memory amounts =
            router.swapTokensForExactTokens(amountOut, amountInMax, path, recipient, block.timestamp);
        vm.stopPrank();

        assertEq(amounts[0], requiredA);
        assertEq(tokenA.balanceOf(provider), 1 ether - 1); // amountInMax - requiredA = 1,001 ether - (1,000 ether + 1) = 1 ether - 1 
        assertEq(tokenB.balanceOf(recipient), amountOut); // recipient receives 2,000 token B

        address pairAB = factory.getPair(address(tokenA), address(tokenB));
        assertEq(tokenA.balanceOf(pairAB), 997 ether + requiredA); // 997 ether + ( 1,000 ether + 1) = 1,997 ether + 1
        assertEq(tokenB.balanceOf(pairAB), 2_000 ether); // 4,000 - 2,000 = 2,000
    }

    // Checks that the router can deliver exactly 1,500 C through A → B → C while spending at most 1,001 A.
    function test_SwapTokensForExactTokensTwoHops() public {
        // 1. Set Up the pools
        // The A/B pool starts with 997 A and 4,000 B.
        _seedSwapPair(tokenA, tokenB, 997 ether, 4_000 ether);
        // The B/C pool starts with 1,994 B and 3,000 C.
        _seedSwapPair(tokenB, tokenC, 1_994 ether, 3_000 ether);

        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        // 2. Calculate backward. 
        // To get 1,500 C from B/C, the router needs 2,000 ether + 1 of B (requiredB). 
        // To get that much B from A/B, it needs 1,000 ether + 2 of A (requiredA). 
        // The + 1 and + 2 are base units from the exact-output calculation.

        uint256 amountOut = 1_500 ether;
        uint256 amountInMax = 1_001 ether;
        // Buying half the C reserve takes 2,000 B plus one base unit.
        // Buying that amount of B takes 1,000 A plus two base units after rounding.
        uint256 requiredB = 2_000 ether + 1;
        uint256 requiredA = 1_000 ether + 2;

        // The provider receives 1,001 A.
        tokenA.transfer(provider, amountInMax);

        vm.startPrank(provider);
        tokenA.approve(address(router), amountInMax);
        // 3. Swap Forward
        // The router pulls the required A from the provider (1,000 ether + 2)
        // The A/B pool sends B directly to the B/C pool, which sends exactly 1,500 C to the recipient.
        uint256[] memory amounts =
            router.swapTokensForExactTokens(amountOut, amountInMax, path, recipient, block.timestamp);
        vm.stopPrank();

        assertEq(amounts[0], requiredA); //  1,000 ether + 2
        assertEq(amounts[1], requiredB); // 2,000 ether + 1
        assertEq(tokenA.balanceOf(provider), amountInMax - requiredA); // 1_001 ether - (1_000 ether + 2) = 1 ether - 2 
        assertEq(tokenC.balanceOf(recipient), amountOut); // 1,500 ether

        // The A/B pool sends B directly to the B/C pool.
        address pairAB = factory.getPair(address(tokenA), address(tokenB));
        address pairBC = factory.getPair(address(tokenB), address(tokenC));
        assertEq(tokenA.balanceOf(pairAB), 997 ether + requiredA); // 1,997 ether + 2
        assertEq(tokenB.balanceOf(pairAB), 4_000 ether - requiredB); // 2,000 ether - 1
        assertEq(tokenB.balanceOf(pairBC), 1_994 ether + requiredB); // 3,994 ether + 1
        assertEq(tokenC.balanceOf(pairBC), 3_000 ether - amountOut); // 1,500 ether
    }

    /////////////////////////////////////////////
    //           swapExactETHForTokens         //
    /////////////////////////////////////////////
    // Spend exactly 1 ETH and give the recipient at least 200 token A.
    function test_SwapExactETHForTokensSingleHop() public {
        vm.deal(address(this), 0.997 ether);
        tokenA.approve(address(router), 400 ether);
        // 1. Set up the pool
        // Seed the WETH/A pair with 0.997 WETH and 400 token A
        router.addLiquidityETH{value: 0.997 ether}(address(tokenA), 400 ether, 0, 0, address(this), block.timestamp);

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenA);

        // 2. Calculate the expected output. 
        // For pricing, Uniswap V2 applies a 0.3% fee to the 1 ETH input. 
        // That gives an effective input of 0.997 WETH, exactly equal to the starting WETH reserve. 
        // The swap formula then gives 400 × 0.997 / (0.997 + 0.997) = 200 token A.

        uint256 expectedOut = 200 ether;
        vm.deal(provider, 1 ether);
        vm.prank(provider);
        // The provider wants to swap 1 ETH and sets the minimum output to 200 token A that recipient will receive
        uint256[] memory amounts = router.swapExactETHForTokens{value: 1 ether}(
            expectedOut, path, recipient, block.timestamp
        );

        assertEq(amounts[0], 1 ether);
        assertEq(amounts[1], expectedOut); // 200 token A
        assertEq(provider.balance, 0); // The provider spent all his ETH
        assertEq(tokenA.balanceOf(recipient), expectedOut); // The recipient recieves 200 token A
        
        address pair = factory.getPair(address(weth), address(tokenA));
        assertEq(weth.balanceOf(pair), 1.997 ether); // 0.997 WETH initially plus 1 WETH from the swap
        assertEq(tokenA.balanceOf(pair), 400 ether - expectedOut); // 400 ether - 200 ether
    }


    /////////////////////////////////////////////
    //           swapTokensForExactETH         //
    /////////////////////////////////////////////
    function _seedTokenAToWETHPath() internal returns (address[] memory path) {
        vm.deal(address(this), 2 ether);
        tokenA.approve(address(router), 997 ether);
        router.addLiquidityETH{value: 2 ether}(address(tokenA), 997 ether, 0, 0, address(this), block.timestamp);

        path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(weth);
    }

    // Buy exactly 1 ETH with my token A, and spend at most 1,010 tokens
    function test_SwapTokensForExactETHSingleHop() public {
        address[] memory path = _seedTokenAToWETHPath();
        uint256 amountOut = 1 ether;
        uint256 amountInMax = 1_010 ether;
        tokenA.transfer(provider, amountInMax);

        // Buy exactly 1 ETH, allowing the router to spend up to 1,010 token A.
        vm.startPrank(provider);
        tokenA.approve(address(router), amountInMax);
        router.swapTokensForExactETH(amountOut, amountInMax, path, recipient, block.timestamp);
        vm.stopPrank();

        // The exact-output quote adds one token base unit to the calculated input.
        uint256 requiredInput = 1_000 ether + 1;
        assertEq(tokenA.balanceOf(provider), amountInMax - requiredInput);
        assertEq(recipient.balance, amountOut);
    }

    /////////////////////////////////////////////
    //           swapExactTokensForETH         //
    /////////////////////////////////////////////
    // Spend exactly 1,000 token A and send the recipient at least 0.99 ETH.
    function test_SwapExactTokensForETHSingleHop() public {
        address[] memory path = _seedTokenAToWETHPath();
        uint256 amountIn = 1_000 ether;
        uint256 amountOutMin = 0.99 ether;
        tokenA.transfer(provider, amountIn);

        // Spend exactly 1,000 token A and accept at least 0.99 ETH.
        vm.startPrank(provider);
        tokenA.approve(address(router), amountIn);
        router.swapExactTokensForETH(amountIn, amountOutMin, path, recipient, block.timestamp);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(provider), 0);
        assertEq(recipient.balance, 1 ether);
    }

    /////////////////////////////////////////////
    //           swapETHForExactTokens         //
    /////////////////////////////////////////////
    // The caller sends 2 ETH to buy exactly 200 token A through one pool.
    function test_SwapETHForExactTokensSingleHop() public {
        vm.deal(address(this), 0.997 ether);
        tokenA.approve(address(router), 400 ether);
        router.addLiquidityETH{value: 0.997 ether}(address(tokenA), 400 ether, 0, 0, address(this), block.timestamp);

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenA);

        // Buy exactly 200 token A with up to 2 ETH.
        uint256 amountOut = 200 ether;
        uint256 ethBudget = 2 ether;
        vm.deal(provider, ethBudget);
        vm.prank(provider);
        router.swapETHForExactTokens{value: ethBudget}(amountOut, path, recipient, block.timestamp);

        // Buying half the token reserve costs 1 ETH plus one wei for exact-output rounding.
        uint256 requiredETH = 1 ether + 1;
        assertEq(tokenA.balanceOf(recipient), amountOut);
        assertEq(provider.balance, ethBudget - requiredETH);
    }
}
