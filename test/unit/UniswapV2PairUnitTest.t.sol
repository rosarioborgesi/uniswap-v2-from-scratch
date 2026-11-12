// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {UniswapV2Pair} from "../../src/v2-core/UniswapV2Pair.sol";
import {IUniswapV2Pair} from "../../src/v2-core/interfaces/IUniswapV2Pair.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockUSDT} from "../mocks/MockUSDT.sol";

contract UniswapV2PairHarness is UniswapV2Pair {
    function update(uint256 balance0, uint256 balance1) external {
        (uint112 oldReserve0, uint112 oldReserve1,) = getReserves();
        _update(balance0, balance1, oldReserve0, oldReserve1);
    }

    function safeTransfer(address token, address to, uint256 value) external {
        _safeTransfer(token, to, value);
    }

    function mintFee(uint112 reserve0, uint112 reserve1) external {
        _mintFee(reserve0, reserve1);
    }
}

contract UniswapV2PairUnitTest is Test {
    UniswapV2PairHarness pair;
    MockERC20 token0;
    MockERC20 token1;
    address recipient = makeAddr("recipient");
    address protocol = makeAddr("protocol");

    // The test contract deploys the pair, so it acts as its factory.
    address public feeTo;

    function setUp() public {
        feeTo = protocol;
        pair = new UniswapV2PairHarness();
        token0 = new MockERC20(address(this), 1_000_000, 18);
        token1 = new MockERC20(address(this), 1_000_000, 18);
        pair.initialize(address(token0), address(token1));
    }

    function _deposit(uint256 amount0, uint256 amount1) internal {
        token0.transfer(address(pair), amount0);
        token1.transfer(address(pair), amount1);
    }

    ///////////////////////////////////////
    //            _safeTransfer          //
    ///////////////////////////////////////
    function test_SafeTransferCanTransferERC20() public {
        MockERC20 token = new MockERC20(address(pair), 100, 18);

        pair.safeTransfer(address(token), recipient, 40);

        assertEq(token.balanceOf(address(pair)), 60);
        assertEq(token.balanceOf(recipient), 40);
    }

    function test_SafeTransferCanTransferUSDT() public {
        MockUSDT token = new MockUSDT(address(pair), 100);

        pair.safeTransfer(address(token), recipient, 40);

        assertEq(token.balanceOf(address(pair)), 60);
        assertEq(token.balanceOf(recipient), 40);
    }

    /////////////////////////////////
    //            _update          //
    /////////////////////////////////
    function test_FirstUpdateStoresReservesAndTimestampAndEmitsSync() public {
        vm.warp(100);

        pair.update(10, 20);

        (uint112 reserve0, uint112 reserve1, uint32 timestamp) = pair.getReserves();
        assertEq(reserve0, 10);
        assertEq(reserve1, 20);
        assertEq(timestamp, 100);
        assertEq(pair.price0CumulativeLast(), 0);
        assertEq(pair.price1CumulativeLast(), 0);
    }

    function test_UpdateAccumulatesPricesUsingPreviousReserves() public {
        uint256 q112 = uint256(1) << 112;

        vm.warp(100);
        pair.update(10, 20);

        // The first ten seconds use the old reserves (10, 20).
        vm.warp(110);
        pair.update(40, 10);

        // Calculate the expected cumulative price increases over 10 seconds, using the previous reserves (10, 20)
        // For price0, the ratio is reserve1 / reserve0:
        // 20 / 10 = 2
        // Encoded price (2 * q112) × elapsed seconds (10):
        uint256 expectedPrice0 = 2 * q112 * 10;

        // For price1, the ratio is the inverse, reserve0 / reserve1:
        // 10 / 20 = 0.5
        // Encoded price (q112 / 2) × elapsed seconds (10):
        uint256 expectedPrice1 = (q112 / 2) * 10;
        assertEq(pair.price0CumulativeLast(), expectedPrice0);
        assertEq(pair.price1CumulativeLast(), expectedPrice1);

        (uint112 reserve0, uint112 reserve1, uint32 timestamp) = pair.getReserves();
        assertEq(reserve0, 40);
        assertEq(reserve1, 10);
        assertEq(timestamp, 110);

        // The next four seconds use (40, 10), adding to the existing totals.
        vm.warp(114);
        pair.update(40, 10);

        // Between timestamps 110 and 114, the reserves are (40, 10) and 4 seconds pass:
        // Price0: reserve1 / reserve0 = 10 / 40 = 0.25.
        // Its encoded value is q112 / 4, time elapsed 4 seconds, so we add (q112 / 4) * 4.
        uint256 expectedPrice0AfterSecondInterval = expectedPrice0 + (q112 / 4) * 4;

        // Price1: reserve0 / reserve1 = 40 / 10 = 4.
        // Its encoded value is 4 * q112, time elapsed 4 seconds, so we add 4 * q112 * 4.
        uint256 expectedPrice1AfterSecondInterval = expectedPrice1 + 4 * q112 * 4;

        assertEq(pair.price0CumulativeLast(), expectedPrice0AfterSecondInterval);
        assertEq(pair.price1CumulativeLast(), expectedPrice1AfterSecondInterval);
    }

    /////////////////////////////////////
    //             _mintFee            //
    /////////////////////////////////////

    function test_MintFeeMintsExpectedLPTokensToProtocol() public {
        // Establish totalSupply = 6,500 and sqrt(kLast) = 6,500.
        _deposit(6_500, 6_500);
        // mint:
        // - Records reserves of 6,500 tokens each.
        // - Creates 6,500 total LP tokens: 5,500 for recipient and 1,000 permanently locked.
        // - Sets kLast = 6,500 × 6,500, because protocol fees are enabled in setUp().
        pair.mint(recipient); // Needed to set the basiline kLast

        // _mintFee compares the supplied √k = 7,150 against the baseline √kLast = 6,500
        pair.mintFee(7_150, 7_150);

        // Protocol LP = 6,500 * (7,150 - 6,500) / (5 * 7,150 + 6,500) = 100.
        assertEq(pair.balanceOf(protocol), 100);
    }

    /////////////////////////////////
    //             mint            //
    /////////////////////////////////

    // This test verifies that the first liquidity deposit locks 1,000 LP tokens permanently and
    // gives the remaining LP tokens to the specified recipient.
    function test_MintFirstDepositLocksMinimumLiquidityAndMintsToRecipient() public {
        // Deposits 10_000 token0 and 40_000 token1 in the pair contract
        _deposit(10_000, 40_000);

        uint256 liquidity = pair.mint(recipient);

        // Initial LP supply = sqrt(10,000 × 40,000) = 20,000
        // Locked LP tokens  = 1,000
        // Recipient receives = 20,000 − 1,000 = 19,000

        // sqrt(10_000 * 40_000) = 20_000; 1_000 LP tokens are locked.
        assertEq(liquidity, 19_000); // mint() returns the amount of LP tokens minted to the recipient
        assertEq(pair.balanceOf(recipient), 19_000); // The recipient has recieved 19_000 LP tokens
        assertEq(pair.balanceOf(address(this)), 0);
        assertEq(pair.balanceOf(address(0)), pair.MINIMUM_LIQUIDITY());
        assertEq(pair.totalSupply(), 20_000); // Supply includes both the recipient's 19,000 and the locked 1,000
        assertEq(pair.balanceOf(protocol), 0); // No protocol fee is minted on the first deposit
        assertEq(pair.kLast(), 400_000_000); // 10_000 × 40_000
    }

    // Verifies that adding 50% of each reserve mints 50% of the existing LP token supply.
    function test_MintProportionalDepositMintsProportionalLiquidity() public {
        // 1. Seeds the pool with 10,000 token0 and 40,000 token1
        _deposit(10_000, 40_000);
        pair.mint(recipient);

        // The initial LP supply is:
        // sqrt(10,000 × 40,000) = 20,000 LP
        // Of that, 1,000 LP is permanently locked at address(0), and 19,000 LP goes to recipient

        // 2. Transfers more tokens into the pair.
        // Both amounts are 50% of the existing reserves, preserving the pool’s 1:4 ratio
        _deposit(5_000, 20_000);
        uint256 liquidity = pair.mint(recipient);

        // liquidity = min(5,000 × 20,000 / 10,000, 20,000 × 20,000 / 40,000)
        //           = min(10,000, 10,000)
        //           = 10,000 LP
        // The second mint returns 10,000 newly minted LP tokens.

        // Adding 50% of each reserve earns 50% of the existing LP supply.
        assertEq(liquidity, 10_000); // The second mint returns 10,000 newly minted LP tokens.
        assertEq(pair.balanceOf(recipient), 29_000); // Original 19,000 + new 10,000.
        assertEq(pair.totalSupply(), 30_000); // Original 20,000 + new 10,000.
        assertEq(pair.balanceOf(address(0)), 1_000); // Minimum liquidity is locked only on the first mint.
        assertEq(pair.balanceOf(protocol), 0); // There was no growth between liquidity events to charge a protocol fee on.
        assertEq(pair.kLast(), 900_000_000); // New reserves are 15,000 and 60,000; their product is 900,000,000.
    }

    // Verifies that an unbalanced deposit earns LP tokens based on the smaller proportional contribution.
    function test_MintUnbalancedDepositUsesLimitingToken() public {
        // 1. deposits 10,000 token0 and 40,000 token1, a 1:4 ratio
        _deposit(10_000, 40_000);
        pair.mint(recipient);

        // The initial LP supply is:
        // sqrt(10,000 × 40,000) = 20,000 LP

        // 2. Deposits 5,000 token0 and 10,000 token1
        _deposit(5_000, 10_000);
        uint256 liquidity = pair.mint(recipient);

        // token1 is the limiting token. The mint function takes the minimum
        // LP minted = min(5,000 × 20,000 / 10,000, 10,000 × 20,000 / 40,000)
        //           = min(10,000, 5,000)
        //           = 5,000

        assertEq(liquidity, 5_000); // The second deposit earns 5,000 LP
        assertEq(pair.balanceOf(recipient), 24_000); // Original 19,000 + new 5,000
        assertEq(pair.totalSupply(), 25_000); // Original 20,000 + new 5,000
        assertEq(pair.balanceOf(protocol), 0); // The recorded reserves had no growth since the previous mint, so no protocol fee is due.
        assertEq(pair.kLast(), 750_000_000); // All deposited tokens enter the reserves, giving 15,000 × 50,000
    }

    // Checks that calling mint() without depositing more tokens reverts.
    function test_MintWithoutNewDepositReverts() public {
        // 1. Deposits 10,000 token0 and 40,000 token1
        _deposit(10_000, 40_000);
        pair.mint(recipient);

        // Because no additional tokens were transferred, the pair’s balances equal its recorded reserves.
        // liquidity = min(0 × 20,000 / 10,000, 0 × 20,000 / 40,000) = 0
        vm.expectRevert(bytes("UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED"));
        pair.mint(recipient);
    }

    // Checks that mint() issues the protocol’s LP tokens first,
    // then uses the increased total supply to calculate the depositor’s LP tokens.
    function test_MintSettlesProtocolFeeBeforeCalculatingDepositorLiquidity() public {
        // 1. Deposit 10,000 token0 and 40,000 token1
        // Total LP supply: sqrt(10,000 × 40,000) = 20,000
        // Recipient receives 19,000; the remaining 1,000 are permanently locked.
        // kLast = 10,000 x 40,000 = 400,000,000
        _deposit(10_000, 40_000);
        pair.mint(recipient);

        // 2. Simulate reserve growth.
        // Transfer another 10,000 and 40,000, then call the harness’s update()
        // Recorded reserves become 20,000 and 80,000.
        // LP supply remains 20,000.
        // kLast remains 400,000,000.
        _deposit(10_000, 40_000);
        pair.update(20_000, 80_000);
        assertEq(pair.kLast(), 400_000_000);

        // Make a new liquidity deposit. Transfer 2,000 and 8,000 then call mint()
        _deposit(2_000, 8_000);
        uint256 liquidity = pair.mint(recipient);

        // the protocol fee is calculated from the reserves before this new deposit:
        // rootK     = sqrt(20,000 × 80,000) = 40,000
        // rootKLast = sqrt(400,000,000)     = 20,000
        // protocol LP (fee) = floor(20,000 × (40,000 − 20,000)/ (5 × 40,000 + 20,000)) = 1,818

        // The depositor’s LP tokens must then use that updated supply
        // liquidity = min(floor(2,000 × 21,818 / 20,000), floor(8,000 × 21,818 / 80,000))
        //           = 2,181
        assertEq(pair.balanceOf(protocol), 1_818);
        // Depositor receives 10% of the supply AFTER the protocol fee is minted.
        assertEq(liquidity, 2_181);
        assertEq(pair.balanceOf(recipient), 21_181); // 19,000 + 2,181 = 21,181 LP
        assertEq(pair.totalSupply(), 23_999); // 20,000 + 1,818 + 2,181 = 23,999 LP
        assertEq(pair.kLast(), 1_936_000_000); // 22,000 × 88,000 = 1,936,000,000
    }

    /////////////////////////////////
    //             burn            //
    /////////////////////////////////

    // burning 25% of the LP supply returns 25% of each token and updates the pool’s accounting correctly.
    function test_BurnWithdrawsProportionalTokensAndUpdatesAccounting() public {
        address provider = makeAddr("provider");

        // 1. Create the pool.
        // Deposit 10,000 token0 and 40,000 token1.
        // Minting creates 20,000 LP tokens: 19,000 for the provider and 1,000 permanently locked.
        _deposit(10_000, 40_000);
        pair.mint(provider);

        // 2. Prepare the burn.
        // The provider transfers 5,000 LP tokens to the pair.
        vm.prank(provider);
        pair.transfer(address(pair), 5_000);

        // 3. Burn LP tokens
        // SInce 5,000 / 20,000 = 25%, the expected withdrawals are:

        // Token	Calculation	      Withdrawal
        // token0	10,000 × 25%	  2,500
        // token1	40,000 × 25%	  10,000

        (uint256 amount0, uint256 amount1) = pair.burn(recipient);

        // 4. Check the result.
        // Burning 25% of the supply withdraws 25% of each underlying balance.
        assertEq(amount0, 2_500); // 10,000 × 25% = 2,500
        assertEq(amount1, 10_000); // 40,000 × 25% = 10,000
        assertEq(token0.balanceOf(recipient), 2_500); // 10,000 × 25% = 2,500
        assertEq(token1.balanceOf(recipient), 10_000); // 40,000 × 25% = 10,000

        assertEq(pair.totalSupply(), 15_000); // 20,000 - 5,000 = 15,000
        assertEq(pair.balanceOf(address(pair)), 0);

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertEq(reserve0, 7_500); // 10,000 - 2,500 = 7,500
        assertEq(reserve1, 30_000); // 40,000 - 10,000 = 30,000
    }

    /////////////////////////////////
    //             swap            //
    /////////////////////////////////

    // Checks that swapping 1,000 token0 for 3,626 token1
    function test_SwapToken0ForToken1TransfersOutputAndUpdatesReserves() public {
        // 1. Create the pool
        // _deposit transfers 10,000 token0 and 40,000 token1 to the pair.
        _deposit(10_000, 40_000);
        // Creates the LP tokens and calls _update, which records 10,000 and 40,000 as the reserves.
        pair.mint(recipient);

        // 2. Pay the input
        // We need to transfer the token to the pair before calling swap
        token0.transfer(address(pair), 1_000);
        // The pair now holds 11,000 token0, but its recorded token0 reserve is still 10,000.
        // During swap, this difference is recognized as the input.

        // With the 0.3% fee, the maximum output is

        //               amount0In × 997 × reserve1
        // amount1Out ≤ ───────────────────────────────
        //              reserve0 × 1000 + amount0In × 997

        // floor(1_000 * 997 * 40_000 / (10_000 * 1_000 + 1_000 * 997)) = 3_626.

        pair.swap(0, 3_626, recipient, ""); // Empty data means no flash swap callback.

        assertEq(token1.balanceOf(recipient), 3_626);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertEq(reserve0, 11_000); // 10,000 + 1,000 = 11,000
        assertEq(reserve1, 36_374); // 40,000 − 3,626 = 36,374
    }

    // The pair rejects a swap when the supplied input cannot pay for the requested output,
    // accounting for the 0.3% fee.
    function test_SwapRevertsWhenInputDoesNotSatisfyInvariant() public {
        // Transfers tokens to the pair
        _deposit(10_000, 40_000);
        // Creates the LP tokens and calls _update, which records 10,000 and 40,000 as the reserves.
        pair.mint(recipient);

        token0.transfer(address(pair), 1_000);

        //               amount0In × 997 × reserve1
        // amount1Out ≤ ───────────────────────────────
        //              reserve0 × 1000 + amount0In × 997

        // floor(1_000 * 997 * 40_000 / (10_000 * 1_000 + 1_000 * 997)) = 3_626.

        // The maximum output is 3_626 after the 0.3% fee.
        // Requesting one unit more breaks the fee-adjusted product invariant.
        vm.expectRevert(bytes("UniswapV2: K"));
        pair.swap(0, 3_627, recipient, "");
    }
}
