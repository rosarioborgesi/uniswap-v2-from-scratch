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
    uint256 providerKey;
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockWETH weth;
    UniswapV2Factory factory;
    UniswapV2Router02 router;

    function setUp() public {
        (provider, providerKey) = makeAddrAndKey("provider");
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
}
